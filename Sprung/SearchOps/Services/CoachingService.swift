//
//  CoachingService.swift
//  Sprung
//
//  Main orchestration service for the Job Search Coach feature.
//  Manages the coaching flow: activity report -> questions -> recommendations.
//

import Foundation
import SwiftData
import SwiftyJSON
import SwiftOpenAI

@Observable
@MainActor
final class CoachingService {
    private let modelContext: ModelContext
    private let llmService: SearchOpsLLMService
    private let activityReportService: ActivityReportService
    private let sessionStore: CoachingSessionStore
    private let settingsStore: SearchOpsSettingsStore
    private let preferencesStore: SearchPreferencesStore

    // MARK: - Observable State

    private(set) var state: CoachingState = .idle
    private(set) var currentSession: CoachingSession?
    private(set) var currentQuestion: CoachingQuestion?

    private var conversationId: UUID?
    private var pendingQuestions: [CoachingQuestion] = []
    private var collectedAnswers: [CoachingAnswer] = []
    private var questionIndex: Int = 0
    private var pendingToolCallId: String?

    // MARK: - Initialization

    init(
        modelContext: ModelContext,
        llmService: SearchOpsLLMService,
        activityReportService: ActivityReportService,
        sessionStore: CoachingSessionStore,
        settingsStore: SearchOpsSettingsStore,
        preferencesStore: SearchPreferencesStore
    ) {
        self.modelContext = modelContext
        self.llmService = llmService
        self.activityReportService = activityReportService
        self.sessionStore = sessionStore
        self.settingsStore = settingsStore
        self.preferencesStore = preferencesStore
    }

    // MARK: - Public API

    /// Get today's completed session if it exists
    var todaysSession: CoachingSession? {
        sessionStore.todaysSession()
    }

    /// Check if coaching should auto-start (no session in 24+ hours)
    var shouldAutoStart: Bool {
        guard coachingModelId != nil else { return false }

        // Check if there's a recent session (within 24 hours)
        let twentyFourHoursAgo = Date().addingTimeInterval(-86400)
        if let lastSession = sessionStore.lastSessionDate(), lastSession > twentyFourHoursAgo {
            return false
        }

        // No recent session, should auto-start
        return true
    }

    /// Auto-start coaching in background if conditions are met
    /// Call this after discovery onboarding is complete
    func autoStartIfNeeded() {
        guard shouldAutoStart else { return }

        // Cancel any in-progress session if we're starting fresh after 24 hours
        if state != .idle {
            Logger.info("🔄 Clearing stale coaching session for fresh start", category: .ai)
            cancelSession()
        }

        Logger.info("🤖 Auto-starting coaching session in background", category: .ai)

        Task {
            do {
                try await startSession()
            } catch {
                Logger.error("Failed to auto-start coaching: \(error)", category: .ai)
            }
        }
    }

    /// Check if there's a completed session for today
    var hasSessionToday: Bool {
        sessionStore.hasCompletedSessionToday
    }

    /// Get the currently selected model ID for coaching (OpenRouter model)
    /// Returns nil if no coaching model is configured
    var coachingModelId: String? {
        let id = UserDefaults.standard.string(forKey: "discoveryCoachingModelId") ?? ""
        return id.isEmpty ? nil : id
    }

    /// Start a new coaching session
    func startSession() async throws {
        // Reset state
        state = .generatingReport
        pendingQuestions = []
        collectedAnswers = []
        questionIndex = 0
        currentQuestion = nil

        // Calculate activity window: since last session that was at least 12 hours ago
        // Sessions within 12 hours don't reset context (allows multiple sessions per day)
        // If no qualifying session, show all activity
        let twelveHoursAgo = Date().addingTimeInterval(-43200)
        let sinceDate = sessionStore.lastSessionDate(before: twelveHoursAgo) ?? .distantPast

        // Generate activity snapshot
        let snapshot = activityReportService.generateSnapshot(since: sinceDate)

        // Create new session
        let session = CoachingSession()
        session.activitySummary = snapshot
        session.daysSinceLastSession = sessionStore.daysSinceLastSession()
        session.llmModel = coachingModelId
        currentSession = session

        // Build system prompt
        let systemPrompt = buildSystemPrompt(
            activitySummary: snapshot.textSummary(),
            recentHistory: sessionStore.recentHistorySummary()
        )

        // Start conversation with coaching tools (use OpenRouter model)
        guard let modelId = coachingModelId else {
            state = .error("No coaching model configured. Please select a model in Settings.")
            return
        }

        conversationId = llmService.startConversation(
            systemPrompt: systemPrompt,
            tools: CoachingToolSchemas.allTools,
            overrideModelId: modelId
        )

        // Send initial message to trigger tool calls
        try await sendInitialMessage()
    }

    /// Submit answer to current question
    func submitAnswer(value: Int, label: String) async throws {
        guard let question = currentQuestion else {
            Logger.warning("No current question to answer", category: .ai)
            return
        }

        // Clear question immediately so UI shows loading
        currentQuestion = nil
        state = .waitingForAnswer

        // Record answer
        let answer = CoachingAnswer(
            questionId: question.id,
            selectedValue: value,
            selectedLabel: label
        )
        collectedAnswers.append(answer)
        currentSession?.answers = collectedAnswers

        // Continue conversation with the answer
        try await continueWithAnswer(answer)
    }

    /// Regenerate by deleting current session and re-running full coaching flow
    func regenerateRecommendations(for session: CoachingSession? = nil) async throws {
        // Delete the existing session
        if let targetSession = session ?? currentSession ?? todaysSession {
            sessionStore.delete(targetSession)
        }

        // Cancel any in-progress state
        cancelSession()

        // Start fresh
        try await startSession()
    }

    /// Cancel the current coaching session
    func cancelSession() {
        if let convId = conversationId {
            llmService.endConversation(convId)
        }
        conversationId = nil
        currentSession = nil
        currentQuestion = nil
        pendingQuestions = []
        collectedAnswers = []
        pendingToolCallId = nil
        state = .idle
    }

    // MARK: - Private Implementation

    private func sendInitialMessage() async throws {
        guard let convId = conversationId else { return }

        // Add initial user message
        llmService.addUserMessage(
            conversationId: convId,
            message: "Please start my coaching session for today. Ask me questions to understand how I'm doing."
        )

        // Get first response (should be a tool call for a question)
        try await processNextResponse(forceQuestion: true)
    }

    /// Process the next LLM response, handling tool calls or final text
    private func processNextResponse(forceQuestion: Bool) async throws {
        guard let convId = conversationId else { return }

        // Force question tool for first 2 questions, then disable all tools to get recommendations
        let toolChoice: ToolChoice = forceQuestion
            ? .function(name: CoachingToolSchemas.multipleChoiceToolName)
            : .none

        do {
            let message = try await llmService.sendMessageSingleTurn(
                conversationId: convId,
                toolChoice: toolChoice
            )

            // Check for tool calls
            if let toolCalls = message.toolCalls, let toolCall = toolCalls.first {
                let toolName = toolCall.function.name ?? ""
                let toolCallId = toolCall.id ?? UUID().uuidString

                if toolName == CoachingToolSchemas.multipleChoiceToolName {
                    let arguments = JSON(parseJSON: toolCall.function.arguments)
                    guard let question = CoachingToolSchemas.parseQuestionFromJSON(arguments) else {
                        Logger.error("Failed to parse coaching question", category: .ai)
                        state = .error("Failed to parse question from coach")
                        return
                    }

                    // Store question and pending tool call
                    pendingQuestions.append(question)
                    currentSession?.questions = (currentSession?.questions ?? []) + [question]
                    pendingToolCallId = toolCallId

                    // Update UI state - user must answer before we continue
                    questionIndex += 1
                    currentQuestion = question
                    state = .askingQuestion(question: question, index: questionIndex, total: 2)

                    Logger.debug("Coaching: showing question \(questionIndex), waiting for user", category: .ai)
                    // STOP HERE - wait for user to call submitAnswer()
                    return
                }
            }

            // No tool call - this is the final recommendations
            let recommendations = message.content ?? ""
            await handleFinalRecommendations(recommendations)

        } catch {
            Logger.error("Failed to get coaching response: \(error)", category: .ai)
            state = .error(error.localizedDescription)
            throw error
        }
    }

    private func continueWithAnswer(_ answer: CoachingAnswer) async throws {
        guard let convId = conversationId,
              let toolCallId = pendingToolCallId else { return }

        state = .waitingForAnswer
        pendingToolCallId = nil

        // Send tool result with user's answer as content
        let toolResult = JSON([
            "selected_value": answer.selectedValue,
            "selected_label": answer.selectedLabel
        ])
        llmService.addToolResult(
            conversationId: convId,
            toolCallId: toolCallId,
            result: toolResult.rawString() ?? "{}"
        )

        // Force another question if we haven't collected 2 yet
        let forceQuestion = collectedAnswers.count < 2

        // Get next response
        try await processNextResponse(forceQuestion: forceQuestion)
    }

    private func handleFinalRecommendations(_ recommendations: String) async {
        guard let session = currentSession else { return }

        // Update session with recommendations
        session.recommendations = recommendations
        session.questionCount = collectedAnswers.count

        // Show recommendations and request follow-up offer
        state = .showingRecommendations(recommendations: recommendations)

        // Request a contextual follow-up offer from the model
        await requestFollowUpOffer()
    }

    /// Request the model to offer a contextual follow-up action
    private func requestFollowUpOffer() async {
        guard let convId = conversationId else {
            // No conversation, just complete
            await completeSession()
            return
        }

        // Add a user message prompting for follow-up
        llmService.addUserMessage(
            conversationId: convId,
            message: "Based on our conversation, what would be most helpful for me to do next? Offer me a contextual follow-up action."
        )

        do {
            // Force the model to use the MC tool for follow-up
            let message = try await llmService.sendMessageSingleTurn(
                conversationId: convId,
                toolChoice: .function(name: CoachingToolSchemas.multipleChoiceToolName)
            )

            // Parse the follow-up question
            if let toolCalls = message.toolCalls, let toolCall = toolCalls.first {
                let arguments = JSON(parseJSON: toolCall.function.arguments)
                if var question = CoachingToolSchemas.parseQuestionFromJSON(arguments) {
                    // Ensure it's marked as follow-up type
                    question = CoachingQuestion(
                        questionText: question.questionText,
                        options: question.options,
                        questionType: .followUp
                    )

                    pendingToolCallId = toolCall.id ?? UUID().uuidString
                    currentQuestion = question
                    state = .askingFollowUp(question: question)

                    Logger.debug("Coaching: showing follow-up question", category: .ai)
                    return
                }
            }

            // If no follow-up question, complete the session
            await completeSession()

        } catch {
            Logger.warning("Failed to get follow-up offer: \(error)", category: .ai)
            // Not critical - just complete without follow-up
            await completeSession()
        }
    }

    /// Complete the coaching session
    private func completeSession() async {
        guard let session = currentSession else { return }

        session.completedAt = Date()
        sessionStore.add(session)

        // Clean up conversation
        if let convId = conversationId {
            llmService.endConversation(convId)
        }
        conversationId = nil

        state = .complete(sessionId: session.id)
        Logger.info("Coaching session completed with \(collectedAnswers.count) questions", category: .ai)
    }

    /// Handle follow-up answer selection
    func submitFollowUpAnswer(value: Int, label: String) async throws {
        guard let question = currentQuestion,
              question.questionType == .followUp else {
            Logger.warning("No follow-up question to answer", category: .ai)
            return
        }

        currentQuestion = nil

        // Map the answer to an action
        let action = mapFollowUpAnswer(value: value, label: label)

        if action == .done {
            // User chose to end session
            await completeSession()
            return
        }

        // Execute the follow-up action
        state = .executingFollowUp(action: action)

        do {
            try await executeFollowUpAction(action)
        } catch {
            Logger.error("Failed to execute follow-up action: \(error)", category: .ai)
            // Still complete the session even if follow-up fails
            await completeSession()
        }
    }

    /// Map follow-up answer to action (based on value or label matching)
    private func mapFollowUpAnswer(value: Int, label: String) -> CoachingFollowUpAction {
        let lowerLabel = label.lowercased()

        if lowerLabel.contains("focus job") || lowerLabel.contains("prioritize") || lowerLabel.contains("pick") {
            return .chooseFocusJobs
        } else if lowerLabel.contains("task") || lowerLabel.contains("to-do") || lowerLabel.contains("todo") {
            return .generateTasks
        } else if lowerLabel.contains("stale") || lowerLabel.contains("follow-up") || lowerLabel.contains("followup") {
            return .staleAppCheck
        } else if lowerLabel.contains("network") || lowerLabel.contains("contact") || lowerLabel.contains("reach out") {
            return .networkingSuggestions
        } else if lowerLabel.contains("quick") || lowerLabel.contains("momentum") || lowerLabel.contains("easy") {
            return .quickWins
        } else if lowerLabel.contains("done") || lowerLabel.contains("good") || lowerLabel.contains("later") {
            return .done
        }

        // Default based on value (lower values = more actionable options typically)
        return value <= 2 ? .generateTasks : .done
    }

    /// Execute the selected follow-up action
    private func executeFollowUpAction(_ action: CoachingFollowUpAction) async throws {
        guard let session = currentSession else { return }

        // For now, append action result to recommendations
        // In future, these could trigger actual tool executions

        let actionResult: String

        switch action {
        case .chooseFocusJobs:
            actionResult = "\n\n---\n**Focus Jobs**: I'll help you pick your top focus jobs. Check the Pipeline view to see AI-recommended priorities."

        case .generateTasks:
            actionResult = "\n\n---\n**Task List**: Your daily tasks have been queued for generation. Check the Today view for your prioritized task list."

        case .staleAppCheck:
            actionResult = "\n\n---\n**Stale Applications**: Review applications in the Pipeline view - filter by 'Applied' stage and sort by date to find ones needing follow-up."

        case .networkingSuggestions:
            actionResult = "\n\n---\n**Networking**: Check your Contacts view for relationship health indicators. Reach out to any marked as 'Needs Attention'."

        case .quickWins:
            actionResult = "\n\n---\n**Quick Wins**:\n• Update your LinkedIn headline\n• Star 3 promising saved jobs\n• Send one brief check-in message\n• Review one pending application status"

        case .done:
            actionResult = ""
        }

        if !actionResult.isEmpty {
            session.recommendations += actionResult
            sessionStore.update(session)
        }

        await completeSession()
    }

    // MARK: - Prompt Building

    private func buildSystemPrompt(activitySummary: String, recentHistory: String) -> String {
        let preferences = preferencesStore.current()

        return """
            You are a supportive and insightful job search coach. Your role is to help the user stay motivated, focused, and strategic in their job search journey.

            ## Your Coaching Style
            - Be warm, encouraging, and empathetic
            - Acknowledge challenges without being patronizing
            - Provide specific, actionable advice based on their actual data
            - Reference the user's real activity and progress
            - Celebrate wins, no matter how small
            - Offer perspective when they're struggling

            ## Today's Activity Report (Last 24 Hours)
            \(activitySummary)

            ## Recent Coaching History
            \(recentHistory)

            ## User's Job Search Goals
            - Target Sectors: \(preferences.targetSectors.joined(separator: ", "))
            - Primary Location: \(preferences.primaryLocation)
            - Remote Acceptable: \(preferences.remoteAcceptable ? "Yes" : "No")
            - Weekly Application Target: \(preferences.weeklyApplicationTarget)
            - Weekly Networking Target: \(preferences.weeklyNetworkingTarget)
            - Preferred Company Size: \(preferences.companySizePreference.rawValue)

            ## Instructions

            1. BEFORE providing any recommendations, you MUST call the `coaching_multiple_choice` tool at least TWO times to gather context about the user's current state.

            2. Your questions should cover different aspects:
               - How they're feeling about their job search (motivation/energy)
               - What challenges or blockers they're facing
               - What they want to focus on today

            3. Design thoughtful questions with 3-5 distinct options that capture the range of how someone might feel or what they might prioritize.

            4. AFTER receiving answers to at least 2 questions, provide personalized recommendations that:
               - Reference their specific activity data from the report
               - Acknowledge their stated feelings and challenges
               - Suggest 2-3 concrete next actions tailored to their energy level and focus
               - Include which job boards/sources to check based on their patterns
               - Mention specific job applications to follow up on if relevant
               - Suggest networking actions if appropriate given their state
               - Offer encouragement tailored to their responses

            5. Keep your final recommendations concise but warm - aim for 3-4 paragraphs.

            6. DO NOT make up activity data - only reference what is in the activity report.

            7. If the user hasn't been active recently, be understanding rather than judgmental. Life happens, and that's okay.

            8. Adjust your tone based on their motivation level - more encouraging if they're struggling, more action-oriented if they're energized.

            ## Follow-Up Offers

            After providing recommendations, you may be asked to offer a contextual follow-up action. When this happens:

            1. Use the `coaching_multiple_choice` tool with `question_type: "follow_up"`

            2. Offer ONE contextual suggestion based on what the user shared, plus alternatives:
               - If they mentioned finding roles is hard → suggest "Pick my top focus jobs for today"
               - If they're low energy → suggest "Give me some quick wins"
               - If they're motivated → suggest "Generate my task list"
               - If they mentioned networking → suggest "Suggest networking contacts to reach out to"
               - If they have many applications → suggest "Check for applications needing follow-up"

            3. Always include "I'm good for now" as the last option

            4. Keep the follow-up question brief and actionable
            """
    }
}
