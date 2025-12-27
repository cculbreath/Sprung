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

        // Generate activity snapshot
        let snapshot = activityReportService.generateSnapshot()

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
        state = .idle
    }

    // MARK: - Private Implementation

    private func sendInitialMessage() async throws {
        guard let convId = conversationId else { return }

        let userMessage = "Please start my coaching session for today. Ask me questions to understand how I'm doing."

        do {
            // Force the LLM to call the multiple choice tool for the first question
            let response = try await llmService.sendMessage(
                userMessage,
                conversationId: convId,
                toolChoice: .function(name: CoachingToolSchemas.multipleChoiceToolName),
                handleToolCalls: { [weak self] toolName, arguments in
                    guard let self = self else { return JSON(["error": "Service unavailable"]) }
                    return try await self.handleToolCall(name: toolName, arguments: arguments)
                }
            )

            // If we got a text response without tool calls, it's the final recommendations
            if pendingQuestions.isEmpty {
                await handleFinalRecommendations(response)
            }
        } catch SearchOpsLLMError.pausedForUserInput {
            // Expected - we displayed a question and are waiting for user input
            Logger.debug("Coaching: paused for user input after question \(questionIndex)", category: .ai)
        } catch {
            Logger.error("Failed to start coaching: \(error)", category: .ai)
            state = .error(error.localizedDescription)
            throw error
        }
    }

    private func handleToolCall(name: String, arguments: JSON) async throws -> JSON {
        if name == CoachingToolSchemas.multipleChoiceToolName {
            // Parse the question from tool arguments
            guard let question = CoachingToolSchemas.parseQuestionFromJSON(arguments) else {
                return JSON(["error": "Failed to parse question"])
            }

            // Add to pending questions
            pendingQuestions.append(question)
            currentSession?.questions = (currentSession?.questions ?? []) + [question]

            // Update state to present question to user
            questionIndex += 1
            currentQuestion = question
            state = .askingQuestion(question: question, index: questionIndex, total: 2)

            // Return acknowledgment (tool result) with pause signal
            return JSON([
                "status": "question_displayed",
                "question_id": question.id.uuidString,
                "_pauseForUser": true
            ])
        }

        return JSON(["error": "Unknown tool: \(name)"])
    }

    private func continueWithAnswer(_ answer: CoachingAnswer) async throws {
        guard let convId = conversationId else { return }

        state = .waitingForAnswer

        // Send the answer back to the LLM
        let answerMessage = """
            User answered: "\(answer.selectedLabel)" (value: \(answer.selectedValue))
            """

        // Force tool call if we haven't collected 2 questions yet
        let forceToolCall = collectedAnswers.count < 2
        let toolChoice: ToolChoice? = forceToolCall
            ? .function(name: CoachingToolSchemas.multipleChoiceToolName)
            : nil

        do {
            let response = try await llmService.sendMessage(
                answerMessage,
                conversationId: convId,
                toolChoice: toolChoice,
                handleToolCalls: { [weak self] toolName, arguments in
                    guard let self = self else { return JSON(["error": "Service unavailable"]) }
                    return try await self.handleToolCall(name: toolName, arguments: arguments)
                }
            )

            // Check if LLM asked another question (would have been handled in handleToolCall)
            // If no new questions, this is the final recommendations
            if currentQuestion == nil || pendingQuestions.count == collectedAnswers.count {
                await handleFinalRecommendations(response)
            }
        } catch SearchOpsLLMError.pausedForUserInput {
            // Expected - we displayed a question and are waiting for user input
            Logger.debug("Coaching: paused for user input after question \(questionIndex)", category: .ai)
        } catch {
            Logger.error("Failed to continue coaching: \(error)", category: .ai)
            state = .error(error.localizedDescription)
            throw error
        }
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
