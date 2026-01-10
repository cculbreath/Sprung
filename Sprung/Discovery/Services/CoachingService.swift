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
    private let llmService: DiscoveryLLMService
    private let activityReportService: ActivityReportService
    private let sessionStore: CoachingSessionStore
    private let dailyTaskStore: DailyTaskStore
    private let preferencesStore: SearchPreferencesStore
    private let jobAppStore: JobAppStore
    private let candidateDossierStore: CandidateDossierStore
    private let knowledgeCardStore: KnowledgeCardStore

    // Extracted component handlers
    private let toolHandler: CoachingToolHandler
    private let contextBuilder: CoachingContextBuilder
    private let taskGenerator: DailyTaskGenerator

    /// Reference to agent service for triggering workflows like chooseBestJobs
    /// Set after initialization by coordinator to avoid circular dependency
    var agentService: DiscoveryAgentService?

    // MARK: - Observable State

    private(set) var state: CoachingState = .idle
    private(set) var currentSession: CoachingSession?
    private(set) var currentQuestion: CoachingQuestion?

    private var conversationId: UUID?
    private var pendingQuestions: [CoachingQuestion] = []
    private var collectedAnswers: [CoachingAnswer] = []
    private var questionIndex: Int = 0

    /// Queue of pending question tool calls (toolCallId, question)
    private var pendingQuestionToolCalls: [(toolCallId: String, question: CoachingQuestion)] = []
    /// The tool call ID for the currently displayed question
    private var currentQuestionToolCallId: String?

    // MARK: - Initialization

    init(
        modelContext: ModelContext,
        llmService: DiscoveryLLMService,
        activityReportService: ActivityReportService,
        sessionStore: CoachingSessionStore,
        dailyTaskStore: DailyTaskStore,
        preferencesStore: SearchPreferencesStore,
        jobAppStore: JobAppStore,
        candidateDossierStore: CandidateDossierStore,
        knowledgeCardStore: KnowledgeCardStore
    ) {
        self.modelContext = modelContext
        self.llmService = llmService
        self.activityReportService = activityReportService
        self.sessionStore = sessionStore
        self.dailyTaskStore = dailyTaskStore
        self.preferencesStore = preferencesStore
        self.jobAppStore = jobAppStore
        self.candidateDossierStore = candidateDossierStore
        self.knowledgeCardStore = knowledgeCardStore

        // Initialize extracted components
        self.toolHandler = CoachingToolHandler(modelContext: modelContext, jobAppStore: jobAppStore)
        self.contextBuilder = CoachingContextBuilder(preferencesStore: preferencesStore, jobAppStore: jobAppStore)
        self.taskGenerator = DailyTaskGenerator(dailyTaskStore: dailyTaskStore, llmService: llmService)
    }

    // MARK: - Public API

    /// Get today's completed session if it exists
    var todaysSession: CoachingSession? {
        sessionStore.todaysSession()
    }

    /// Check if coaching should auto-start (no active session and no completed session in 24+ hours)
    var shouldAutoStart: Bool {
        guard coachingModelId != nil else { return false }

        // Don't auto-start if there's already an active session in progress
        if state.isActive {
            return false
        }

        // Check if there's a recent completed session (within 24 hours)
        let twentyFourHoursAgo = Date().addingTimeInterval(-86400)
        if let lastSession = sessionStore.lastSessionDate(), lastSession > twentyFourHoursAgo {
            return false
        }

        // No active session and no recent completed session, should auto-start
        return true
    }

    /// Auto-start coaching in background if conditions are met
    /// Call this after discovery onboarding is complete
    func autoStartIfNeeded() {
        guard shouldAutoStart else { return }

        // shouldAutoStart already ensures no active session, so we can start fresh
        Logger.info("🤖 Auto-starting coaching session in background", category: .ai)

        Task {
            do {
                try await startSession()
            } catch {
                Logger.error("Failed to auto-start coaching: \(error)", category: .ai)
            }
        }
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

        // Build dossier context from CandidateDossier
        let dossierContext = candidateDossierStore.dossier?.exportForDiscovery() ?? "No dossier available."

        // Build knowledge cards list from KnowledgeCardStore
        let knowledgeCardsList = contextBuilder.buildKnowledgeCardsList(from: knowledgeCardStore.knowledgeCards)

        // Build system prompt with full context
        let systemPrompt = contextBuilder.buildSystemPrompt(
            activitySummary: snapshot.textSummary(),
            recentHistory: sessionStore.recentHistorySummary(),
            dossierContext: dossierContext,
            knowledgeCardsList: knowledgeCardsList,
            activeJobApps: contextBuilder.buildActiveJobAppsList()
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
        pendingQuestionToolCalls = []
        currentQuestionToolCallId = nil
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

        // Get first response - uses .auto so LLM can research before asking first question
        try await processNextResponse()
    }

    /// Process the next LLM response, handling tool calls or final text
    private func processNextResponse() async throws {
        guard let convId = conversationId else { return }

        // Tool choice based on conversation phase:
        // - 0 answers: .auto - LLM can research + ask first question
        // - 1 answer: Force second question
        // - 2+ answers: .auto - can ask Q3, give recommendations, or research more
        let toolChoice: ToolChoice
        switch collectedAnswers.count {
        case 0:
            // First call - allow research tools alongside question
            toolChoice = .auto
        case 1:
            // After first answer - force second question
            toolChoice = .function(name: CoachingToolSchemas.multipleChoiceToolName)
        default:
            // After 2+ answers - flexible: can ask more, recommend, or research
            toolChoice = .auto
        }

        do {
            // parallelToolCalls is enabled by default in LLMRequestBuilder
            let message = try await llmService.sendMessageSingleTurn(
                conversationId: convId,
                toolChoice: toolChoice
            )

            // Handle all tool calls (may be multiple in parallel)
            if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                // Collect question tool calls and handle research tools immediately
                var questionToolCalls: [(toolCallId: String, question: CoachingQuestion)] = []

                for toolCall in toolCalls {
                    let toolName = toolCall.function.name ?? ""
                    let toolCallId = toolCall.id ?? UUID().uuidString

                    if toolName == CoachingToolSchemas.multipleChoiceToolName {
                        // Parse and queue the question
                        let arguments = JSON(parseJSON: toolCall.function.arguments)
                        if let question = CoachingToolSchemas.parseQuestionFromJSON(arguments) {
                            questionToolCalls.append((toolCallId: toolCallId, question: question))
                        } else {
                            // Send error response for unparseable question
                            llmService.addToolResult(conversationId: convId, toolCallId: toolCallId, result: "{\"error\": \"Failed to parse question\"}")
                        }
                    } else {
                        // Handle background research tools immediately
                        let result = await handleBackgroundTool(name: toolName, arguments: toolCall.function.arguments)
                        llmService.addToolResult(conversationId: convId, toolCallId: toolCallId, result: result)
                    }
                }

                // If we have question tool calls, queue them and show the first one
                if !questionToolCalls.isEmpty {
                    pendingQuestionToolCalls = questionToolCalls
                    Logger.debug("Coaching: queued \(questionToolCalls.count) question(s)", category: .ai)
                    showNextQueuedQuestion()
                    return
                }

                // If we only handled background tools, continue for next response
                try await processNextResponse()
                return
            }

            // No tool call - this is the final recommendations
            let recommendations = message.content ?? ""
            await handleFinalRecommendations(recommendations)

        } catch {
            // Check for missing tool output error and try to recover
            if let toolCallId = extractMissingToolCallId(from: error) {
                Logger.warning("⚠️ Missing tool output for \(toolCallId), sending error response", category: .ai)
                llmService.addToolResult(
                    conversationId: convId,
                    toolCallId: toolCallId,
                    result: "{\"error\": \"Tool call was not processed. Please continue without this information.\"}"
                )
                // Retry after providing the error response
                try await processNextResponse()
                return
            }

            Logger.error("Failed to get coaching response: \(error)", category: .ai)
            state = .error(error.localizedDescription)
            throw error
        }
    }

    /// Extract tool call ID from "No tool output found" error message
    private func extractMissingToolCallId(from error: Error) -> String? {
        let errorString = String(describing: error)
        // Pattern: "No tool output found for function call call_XXXXX"
        guard errorString.contains("No tool output found for function call") else {
            return nil
        }

        // Extract the call_XXXXX identifier
        let pattern = "call_[A-Za-z0-9]+"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: errorString, range: NSRange(errorString.startIndex..., in: errorString)),
              let range = Range(match.range, in: errorString) else {
            return nil
        }

        return String(errorString[range])
    }

    /// Handle background research tool calls (knowledge cards, job descriptions, resumes)
    private func handleBackgroundTool(name: String, arguments: String) async -> String {
        let args = JSON(parseJSON: arguments)

        switch name {
        case CoachingToolSchemas.getKnowledgeCardToolName:
            return toolHandler.handleGetKnowledgeCard(args, knowledgeCards: knowledgeCardStore.knowledgeCards)

        case CoachingToolSchemas.getJobDescriptionToolName:
            return toolHandler.handleGetJobDescription(args)

        case CoachingToolSchemas.getResumeToolName:
            return await toolHandler.handleGetResume(args)

        case CoachingToolSchemas.chooseBestJobsToolName:
            return await toolHandler.handleChooseBestJobs(
                args,
                agentService: agentService,
                knowledgeCards: knowledgeCardStore.knowledgeCards,
                dossier: candidateDossierStore.dossier
            )

        default:
            return JSON(["error": "Unknown tool: \(name)"]).rawString() ?? "{}"
        }
    }

    private func continueWithAnswer(_ answer: CoachingAnswer) async throws {
        guard let convId = conversationId else { return }

        state = .waitingForAnswer

        // Send tool result for this answer
        let toolResult = JSON([
            "selected_value": answer.selectedValue,
            "selected_label": answer.selectedLabel
        ])

        // Get the tool call ID for this question (it was just answered, so it's the one we just showed)
        // The current question's tool call ID was removed from the queue when we showed it
        // We stored it separately when showing the question
        if let toolCallId = currentQuestionToolCallId {
            llmService.addToolResult(
                conversationId: convId,
                toolCallId: toolCallId,
                result: toolResult.rawString() ?? "{}"
            )
            currentQuestionToolCallId = nil
        }

        // Check if there are more queued questions from parallel tool calls
        if !pendingQuestionToolCalls.isEmpty {
            showNextQueuedQuestion()
            return
        }

        // No more queued questions - get next response from LLM
        try await processNextResponse()
    }

    /// Show the next question from the queue
    private func showNextQueuedQuestion() {
        guard !pendingQuestionToolCalls.isEmpty else { return }

        let (toolCallId, question) = pendingQuestionToolCalls.removeFirst()
        currentQuestionToolCallId = toolCallId

        // Store question
        pendingQuestions.append(question)
        currentSession?.questions = (currentSession?.questions ?? []) + [question]

        // Update UI state
        questionIndex += 1
        currentQuestion = question
        state = .askingQuestion(question: question, index: questionIndex, total: max(3, questionIndex + pendingQuestionToolCalls.count))

        Logger.debug("Coaching: showing question \(questionIndex) (queued: \(pendingQuestionToolCalls.count) remaining)", category: .ai)
    }

    private func handleFinalRecommendations(_ recommendations: String) async {
        guard let session = currentSession else { return }

        // Store recommendations (tasks will be generated via forced tool call at end of session)
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
            // No conversation - still generate tasks before completing
            await generateDailyTasksViaToolCall()
            return
        }

        // Add a user message prompting for follow-up
        llmService.addUserMessage(
            conversationId: convId,
            message: "Based on our conversation, what would be most helpful for me to do next? Offer me a contextual follow-up action using the coaching_multiple_choice tool."
        )

        do {
            // Use .auto to allow research tools alongside follow-up question
            let message = try await llmService.sendMessageSingleTurn(
                conversationId: convId,
                toolChoice: .auto
            )

            // Handle any tool calls (research tools + question tool)
            if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                var questionToolCallId: String?
                var questionToolArgs: String?

                // Process background tools first
                for toolCall in toolCalls {
                    let toolName = toolCall.function.name ?? ""
                    let toolCallId = toolCall.id ?? UUID().uuidString

                    if toolName == CoachingToolSchemas.multipleChoiceToolName {
                        questionToolCallId = toolCallId
                        questionToolArgs = toolCall.function.arguments
                    } else {
                        // Handle research tools
                        let result = await handleBackgroundTool(name: toolName, arguments: toolCall.function.arguments)
                        llmService.addToolResult(conversationId: convId, toolCallId: toolCallId, result: result)
                    }
                }

                // Now handle the follow-up question if present
                if let toolCallId = questionToolCallId, let argsString = questionToolArgs {
                    let arguments = JSON(parseJSON: argsString)
                    if var question = CoachingToolSchemas.parseQuestionFromJSON(arguments) {
                        // Ensure it's marked as follow-up type
                        question = CoachingQuestion(
                            questionText: question.questionText,
                            options: question.options,
                            questionType: .followUp
                        )

                        currentQuestionToolCallId = toolCallId
                        currentQuestion = question
                        state = .askingFollowUp(question: question)

                        Logger.debug("Coaching: showing follow-up question", category: .ai)
                        return
                    }
                }
            }

            // No follow-up question offered - generate tasks and complete
            await generateDailyTasksViaToolCall()

        } catch {
            Logger.warning("Failed to get follow-up offer: \(error)", category: .ai)
            // Not critical - still generate tasks before completing
            await generateDailyTasksViaToolCall()
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
              question.questionType == .followUp,
              let convId = conversationId,
              let toolCallId = currentQuestionToolCallId else {
            Logger.warning("No follow-up question to answer or missing context", category: .ai)
            return
        }

        currentQuestion = nil
        currentQuestionToolCallId = nil

        // Send tool result for the follow-up question
        let toolResult = JSON([
            "selected_value": value,
            "selected_label": label
        ])
        llmService.addToolResult(
            conversationId: convId,
            toolCallId: toolCallId,
            result: toolResult.rawString() ?? "{}"
        )

        // Map the answer to an action
        let action = mapFollowUpAnswer(value: value, label: label)

        if action == .done {
            // User chose to end session - still generate tasks first
            await generateDailyTasksViaToolCall()
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
            actionResult = "\n\n---\n**Task List**: Your daily tasks were automatically generated from this coaching session. Check the Today view to see your prioritized task list."

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

        // Force task generation before completing
        await generateDailyTasksViaToolCall()
    }

    /// Force the LLM to generate daily tasks via tool call
    private func generateDailyTasksViaToolCall() async {
        guard let convId = conversationId else {
            await completeSession()
            return
        }

        Logger.info("📋 Requesting daily tasks from coach", category: .ai)

        // Add instruction to generate tasks
        llmService.addUserMessage(
            conversationId: convId,
            message: "Now generate my daily task list based on our coaching conversation. Use the update_daily_tasks tool to create 3-6 specific, actionable tasks."
        )

        do {
            // Force the update_daily_tasks tool
            let message = try await llmService.sendMessageSingleTurn(
                conversationId: convId,
                toolChoice: .function(name: CoachingToolSchemas.updateDailyTasksToolName)
            )

            // Handle the tool call
            if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                for toolCall in toolCalls {
                    let toolName = toolCall.function.name ?? ""
                    let toolCallId = toolCall.id ?? UUID().uuidString

                    if toolName == CoachingToolSchemas.updateDailyTasksToolName {
                        _ = taskGenerator.handleUpdateDailyTasksToolCall(
                            arguments: toolCall.function.arguments,
                            session: currentSession
                        )
                        // Send acknowledgment
                        llmService.addToolResult(
                            conversationId: convId,
                            toolCallId: toolCallId,
                            result: "{\"success\": true, \"message\": \"Tasks saved successfully\"}"
                        )
                    }
                }
            }

            Logger.info("✅ Daily tasks generated from coaching session", category: .ai)

        } catch {
            Logger.error("Failed to generate daily tasks: \(error)", category: .ai)
        }

        await completeSession()
    }

    // MARK: - Task Regeneration

    /// Regenerate tasks for a specific category based on user feedback
    /// Uses the coaching session's recommendations as context
    func regenerateTasksForCategory(
        _ category: TaskCategory,
        feedback: String
    ) async throws {
        guard let session = todaysSession else {
            throw DiscoveryLLMError.conversationNotFound
        }

        guard let modelId = coachingModelId else {
            throw DiscoveryLLMError.modelNotConfigured
        }

        Logger.info("🔄 Regenerating \(category.displayName) tasks with feedback", category: .ai)

        // Build the prompt with context
        let prompt = taskGenerator.buildRegenerationPrompt(
            category: category,
            feedback: feedback,
            coachingRecommendations: session.recommendations,
            activitySummary: session.activitySummary?.textSummary() ?? "No activity data available"
        )

        // Execute structured request
        let response: TaskRegenerationResponse = try await llmService.executeStructured(
            prompt: prompt,
            systemPrompt: """
                You are a job search coach helping regenerate daily tasks based on user feedback.
                Generate practical, actionable tasks that address the user's concerns.
                Only generate tasks for the specified category: \(category.displayName).
                """,
            as: TaskRegenerationResponse.self,
            temperature: 0.7,
            backend: .openRouter,
            modelId: modelId,
            schema: CoachingToolSchemas.buildTaskRegenerationSchema(),
            schemaName: "task_regeneration"
        )

        // Clear existing tasks for this category and add new ones
        taskGenerator.replaceTasksForCategory(category, with: response.tasks)

        Logger.info("✅ Regenerated \(response.tasks.count) \(category.displayName) tasks", category: .ai)
    }
}
