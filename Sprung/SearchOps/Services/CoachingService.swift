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

        // Calculate activity window: since last coaching session or 24 hours, whichever is longer
        // If no previous session, show all activity (first-time user)
        let sinceDate: Date
        if let lastSession = sessionStore.lastSessionDate() {
            let twentyFourHoursAgo = Date().addingTimeInterval(-86400)
            sinceDate = min(lastSession, twentyFourHoursAgo)
        } else {
            sinceDate = .distantPast
        }

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

    /// Regenerate recommendations (re-run coaching with same questions/answers)
    func regenerateRecommendations() async throws {
        guard let session = currentSession else { return }

        state = .generatingRecommendations

        // Re-run the final recommendation step
        try await generateFinalRecommendations(session: session)
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

        let toolChoice: ToolChoice? = forceQuestion
            ? .function(name: CoachingToolSchemas.multipleChoiceToolName)
            : nil

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

        state = .generatingRecommendations

        // Update session with recommendations
        session.recommendations = recommendations
        session.questionCount = collectedAnswers.count
        session.completedAt = Date()

        // Save session
        sessionStore.add(session)

        // Clean up
        if let convId = conversationId {
            llmService.endConversation(convId)
        }
        conversationId = nil

        state = .complete(sessionId: session.id)
        Logger.info("Coaching session completed with \(collectedAnswers.count) questions", category: .ai)
    }

    private func generateFinalRecommendations(session: CoachingSession) async throws {
        // Build a summary of Q&A for regeneration
        var qaContext = "Based on the user's responses:\n"
        for (index, answer) in session.answers.enumerated() {
            if let question = session.questions.first(where: { $0.id == answer.questionId }) {
                qaContext += "\(index + 1). \(question.questionText)\n   Answer: \(answer.selectedLabel)\n"
            }
        }

        let prompt = """
            \(qaContext)

            Please provide fresh, personalized coaching recommendations for today's job search activities.
            Be specific about what actions to take, which job boards to check, and any networking follow-ups.
            """

        let systemPrompt = buildSystemPrompt(
            activitySummary: session.activitySummary?.textSummary() ?? "No recent activity",
            recentHistory: sessionStore.recentHistorySummary()
        )

        do {
            let recommendations = try await llmService.executeText(
                prompt: prompt,
                systemPrompt: systemPrompt,
                temperature: 0.7
            )

            session.recommendations = recommendations
            session.completedAt = Date()
            sessionStore.update(session)

            state = .complete(sessionId: session.id)
        } catch {
            Logger.error("Failed to regenerate recommendations: \(error)", category: .ai)
            state = .error(error.localizedDescription)
            throw error
        }
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
            """
    }
}
