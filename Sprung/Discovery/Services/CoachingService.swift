//
//  CoachingService.swift
//  Sprung
//
//  Main orchestration service for the Job Search Coach feature.
//  Manages the coaching flow: activity report -> questions -> recommendations.
//
//  The session runs as one AnthropicToolLoopRunner loop against the Messages
//  API. Question tool calls suspend inside executeTools on a continuation
//  until the user answers (submitAnswer / submitFollowUpAnswer resume it);
//  background research tools execute immediately. The forced
//  update_daily_tasks call is the loop's completion tool.
//

import Foundation
import SwiftData
import SwiftOpenAI

@Observable
@MainActor
final class CoachingService: AnthropicToolLoopDelegate {
    private let modelContext: ModelContext
    private let llmFacade: LLMFacade
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

    private var pendingQuestions: [CoachingQuestion] = []
    private var collectedAnswers: [CoachingAnswer] = []
    private var questionIndex: Int = 0

    // MARK: - Session Loop State

    /// Where the session is in the coaching script; drives per-turn tool choice.
    private enum SessionPhase {
        /// Asking questions / researching until the model gives recommendations.
        case gatheringAnswers
        /// Recommendations shown; the model was asked to offer a follow-up.
        case awaitingFollowUp
        /// Terminal phase: the update_daily_tasks completion tool is forced.
        case generatingTasks
    }

    private var phase: SessionPhase = .gatheringAnswers
    private var sessionSystemPrompt: String = ""
    private var sessionModelId: String = ""
    /// The running session loop; cancelled by cancelSession().
    private var sessionTask: Task<Void, Never>?
    /// Monotonic token so a cancelled session's trailing error (e.g. a
    /// URLError from a torn-down request) can't clobber a newer session's state.
    private var sessionGeneration = 0
    /// Continuation parked while a question is displayed, resumed by
    /// submitAnswer / submitFollowUpAnswer with the user's selection.
    private var pendingAnswer: CheckedContinuation<(value: Int, label: String), Error>?
    /// Text of the most recent assistant turn (captured for the
    /// recommendations no-tool turn).
    private var lastTurnText: String = ""

    private static let maxResponseTokens = 8192

    // MARK: - Initialization

    init(
        modelContext: ModelContext,
        llmFacade: LLMFacade,
        activityReportService: ActivityReportService,
        sessionStore: CoachingSessionStore,
        dailyTaskStore: DailyTaskStore,
        preferencesStore: SearchPreferencesStore,
        jobAppStore: JobAppStore,
        candidateDossierStore: CandidateDossierStore,
        knowledgeCardStore: KnowledgeCardStore
    ) {
        self.modelContext = modelContext
        self.llmFacade = llmFacade
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
        self.taskGenerator = DailyTaskGenerator(dailyTaskStore: dailyTaskStore)
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

    /// The currently selected Anthropic model ID for Discovery coaching,
    /// or nil if none is configured.
    var coachingModelId: String? {
        let id = UserDefaults.standard.string(forKey: DiscoveryAgentService.anthropicModelSettingKey) ?? ""
        return id.isEmpty ? nil : id
    }

    /// Start a new coaching session
    func startSession() async throws {
        // Tear down any in-flight session first
        cancelSession()

        // Reset state
        state = .generatingReport
        pendingQuestions = []
        collectedAnswers = []
        questionIndex = 0
        currentQuestion = nil
        phase = .gatheringAnswers
        lastTurnText = ""

        // Model must be user-configured — never substituted.
        guard let modelId = coachingModelId else {
            state = .error("No coaching model configured. Please select a model in Settings.")
            throw ModelConfigurationError.modelNotConfigured(
                settingKey: DiscoveryAgentService.anthropicModelSettingKey,
                operationName: "Discovery Coaching"
            )
        }
        sessionModelId = modelId

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
        session.llmModel = modelId
        currentSession = session

        // Build dossier context from CandidateDossier
        let dossierContext = candidateDossierStore.dossier?.exportForDiscovery() ?? "No dossier available."

        // Build knowledge cards list from KnowledgeCardStore
        let knowledgeCardsList = contextBuilder.buildKnowledgeCardsList(from: knowledgeCardStore.knowledgeCards)

        // Build system prompt with full context
        sessionSystemPrompt = contextBuilder.buildSystemPrompt(
            activitySummary: snapshot.textSummary(),
            recentHistory: sessionStore.recentHistorySummary(),
            dossierContext: dossierContext,
            knowledgeCardsList: knowledgeCardsList,
            activeJobApps: contextBuilder.buildActiveJobAppsList()
        )

        // Drive the whole session as one shared tool loop. Question tool calls
        // suspend until the user answers; the loop completes on the forced
        // update_daily_tasks call.
        sessionGeneration += 1
        let generation = sessionGeneration
        sessionTask = Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await AnthropicToolLoopRunner(delegate: self).run()
            } catch is CancellationError {
                // cancelSession() already reset the UI state.
            } catch {
                guard self.sessionGeneration == generation else { return }
                Logger.error("Coaching session failed: \(error)", category: .ai)
                self.state = .error(error.localizedDescription)
            }
        }
    }

    /// Submit answer to current question
    func submitAnswer(value: Int, label: String) async throws {
        guard currentQuestion != nil, let continuation = pendingAnswer else {
            Logger.warning("No current question to answer", category: .ai)
            return
        }

        // Clear question immediately so UI shows loading
        pendingAnswer = nil
        currentQuestion = nil
        state = .waitingForAnswer

        continuation.resume(returning: (value: value, label: label))
    }

    /// Handle follow-up answer selection
    func submitFollowUpAnswer(value: Int, label: String) async throws {
        guard let question = currentQuestion,
              question.questionType == .followUp,
              let continuation = pendingAnswer else {
            Logger.warning("No follow-up question to answer or missing context", category: .ai)
            return
        }

        pendingAnswer = nil
        currentQuestion = nil
        state = .waitingForAnswer

        continuation.resume(returning: (value: value, label: label))
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
        sessionGeneration += 1
        sessionTask?.cancel()
        sessionTask = nil
        if let continuation = pendingAnswer {
            pendingAnswer = nil
            continuation.resume(throwing: CancellationError())
        }
        currentSession = nil
        currentQuestion = nil
        pendingQuestions = []
        collectedAnswers = []
        state = .idle
    }

    // MARK: - Tool Loop Delegate

    var maxTurns: Int { 40 }
    var completionToolName: String { CoachingToolSchemas.updateDailyTasksToolName }

    func maxTurnsError() -> Error {
        DiscoveryAgentError.toolLoopExceeded
    }

    func initialMessages() -> [AnthropicMessage] {
        [.user("Please start my coaching session for today. Ask me questions to understand how I'm doing.")]
    }

    func runModelTurn(messages: [AnthropicMessage]) async throws -> AnthropicTurnResult {
        // Tool choice based on conversation phase:
        // - generating tasks: force update_daily_tasks (session terminal)
        // - exactly 1 answer collected: force a second question
        // - otherwise: .auto — the model can research, ask, or recommend
        let toolChoice: AnthropicToolChoice
        switch phase {
        case .generatingTasks:
            toolChoice = .tool(name: CoachingToolSchemas.updateDailyTasksToolName)
        case .gatheringAnswers where collectedAnswers.count == 1:
            toolChoice = .tool(name: CoachingToolSchemas.multipleChoiceToolName)
        default:
            toolChoice = .auto
        }

        let parameters = AnthropicMessageParameter(
            model: sessionModelId,
            messages: messages,
            system: .blocks([AnthropicSystemBlock(text: sessionSystemPrompt, cacheControl: .ephemeral)]),
            maxTokens: Self.maxResponseTokens,
            stream: false,
            tools: CoachingToolSchemas.allTools,
            toolChoice: toolChoice
        )
        let response = try await llmFacade.anthropicMessages(parameters: parameters)
        let usage = response.usage
        Logger.debug(
            "🧑‍🏫 Coaching usage (\(sessionModelId)): input=\(usage.inputTokens) cache_read=\(usage.cacheReadInputTokens ?? 0) output=\(usage.outputTokens)",
            category: .ai
        )
        let result = AnthropicTurnResult(response: response)
        lastTurnText = result.textBlocks.joined(separator: "\n")
        return result
    }

    func executeTools(_ toolCalls: [AnthropicToolUseResponseBlock]) async -> [String: AnthropicToolOutput] {
        var outputs: [String: AnthropicToolOutput] = [:]

        // Question tool calls in this turn, displayed one at a time (each
        // suspends until the user answers). Count them up front so the
        // progress indicator can show how many are queued.
        var remainingQuestionCalls = toolCalls.filter { $0.name == CoachingToolSchemas.multipleChoiceToolName }.count

        for call in toolCalls {
            let arguments = call.input.jsonString

            if call.name == CoachingToolSchemas.multipleChoiceToolName {
                remainingQuestionCalls -= 1
                outputs[call.id] = await handleQuestionToolCall(
                    arguments: arguments,
                    questionsQueuedAfter: remainingQuestionCalls
                )
            } else {
                let result = await handleBackgroundTool(name: call.name, arguments: arguments)
                outputs[call.id] = AnthropicToolOutput(content: result)
            }
        }
        return outputs
    }

    func parseCompletion(_ call: AnthropicToolUseResponseBlock) async throws -> Int {
        guard phase == .generatingTasks else {
            // Premature update_daily_tasks call — send a corrective tool_result
            // and keep the conversation going (pre-runner behavior never let a
            // mid-session call end the session).
            throw DiscoveryAgentError.toolExecutionFailed(
                "Not yet — continue the coaching conversation first. Daily tasks are requested at the end of the session."
            )
        }

        let count = taskGenerator.handleUpdateDailyTasksToolCall(
            arguments: call.input.jsonString,
            session: currentSession
        )
        Logger.info("✅ Daily tasks generated from coaching session", category: .ai)
        completeSession()
        return count
    }

    func handleNoTool(turnCount: Int, consecutiveNoToolTurns: Int) -> AnthropicNoToolDecision {
        switch phase {
        case .gatheringAnswers:
            // A no-tool text turn is the final recommendations.
            handleFinalRecommendations(lastTurnText)
            phase = .awaitingFollowUp
            return .nudge(
                "Based on our conversation, what would be most helpful for me to do next? "
                + "Offer me a contextual follow-up action using the coaching_multiple_choice tool."
            )
        case .awaitingFollowUp:
            // No follow-up question offered — move straight to task generation.
            phase = .generatingTasks
            return .nudge(Self.taskGenerationPrompt)
        case .generatingTasks:
            // Shouldn't happen (tool choice is forced); re-issue the instruction.
            return .nudge(Self.taskGenerationPrompt)
        }
    }

    func onMaxTurnsReached(messages: [AnthropicMessage]) async throws -> Int? {
        nil  // → runner throws maxTurnsError()
    }

    // MARK: - Private Implementation

    private static let taskGenerationPrompt =
        "Now generate my daily task list based on our coaching conversation. "
        + "Use the update_daily_tasks tool to create 3-6 specific, actionable tasks."

    private func encodeToJSON<T: Encodable>(_ value: T) -> String {
        (try? String(data: JSONEncoder().encode(value), encoding: .utf8)) ?? "{}"
    }

    /// Display a question tool call and suspend until the user answers.
    /// Returns the tool output carrying the user's selection.
    private func handleQuestionToolCall(
        arguments: String,
        questionsQueuedAfter: Int
    ) async -> AnthropicToolOutput {
        guard var question = CoachingToolSchemas.parseQuestion(from: arguments) else {
            return AnthropicToolOutput(
                content: encodeToJSON(ToolErrorResult(error: "Failed to parse question")),
                isError: true
            )
        }

        let isFollowUp = phase == .awaitingFollowUp
        if isFollowUp {
            // Ensure it's marked as follow-up type
            question = CoachingQuestion(
                questionText: question.questionText,
                options: question.options,
                questionType: .followUp
            )
            currentQuestion = question
            state = .askingFollowUp(question: question)
            Logger.debug("Coaching: showing follow-up question", category: .ai)
        } else {
            pendingQuestions.append(question)
            currentSession?.questions = (currentSession?.questions ?? []) + [question]
            questionIndex += 1
            currentQuestion = question
            state = .askingQuestion(
                question: question,
                index: questionIndex,
                total: max(3, questionIndex + questionsQueuedAfter)
            )
            Logger.debug("Coaching: showing question \(questionIndex) (queued: \(questionsQueuedAfter) remaining)", category: .ai)
        }

        // Suspend until submitAnswer / submitFollowUpAnswer resumes us.
        let selection: (value: Int, label: String)
        do {
            selection = try await withCheckedThrowingContinuation { continuation in
                pendingAnswer = continuation
            }
        } catch {
            // Session cancelled while waiting — the runner's per-turn
            // cancellation check ends the loop right after this turn.
            return AnthropicToolOutput(content: "Session cancelled before the user answered.", isError: true)
        }

        if isFollowUp {
            return followUpAnswerOutput(value: selection.value, label: selection.label)
        }

        // Record answer
        let answer = CoachingAnswer(
            questionId: question.id,
            selectedValue: selection.value,
            selectedLabel: selection.label
        )
        collectedAnswers.append(answer)
        currentSession?.answers = collectedAnswers

        return AnthropicToolOutput(content: encodeToJSON(ToolAnswerResult(
            selectedValue: answer.selectedValue,
            selectedLabel: answer.selectedLabel
        )))
    }

    /// Map the follow-up selection to an action, apply its side effects, and
    /// build the tool output that steers the model into task generation.
    private func followUpAnswerOutput(value: Int, label: String) -> AnthropicToolOutput {
        let action = mapFollowUpAnswer(value: value, label: label)

        if action == .generateTasks, let session = currentSession {
            state = .executingFollowUp(action: action)
            session.recommendations += "\n\n---\n**Task List**: Your daily tasks were automatically generated from this coaching session. Check the Today view to see your prioritized task list."
            sessionStore.update(session)
        }

        // Either way the session ends with task generation (pre-runner behavior).
        phase = .generatingTasks
        Logger.info("📋 Requesting daily tasks from coach", category: .ai)

        let answerJSON = encodeToJSON(ToolAnswerResult(selectedValue: value, selectedLabel: label))
        return AnthropicToolOutput(content: answerJSON + "\n\n" + Self.taskGenerationPrompt)
    }

    /// Handle background research tool calls (knowledge cards, job descriptions, resumes)
    private func handleBackgroundTool(name: String, arguments: String) async -> String {
        switch name {
        case CoachingToolSchemas.getKnowledgeCardToolName:
            return toolHandler.handleGetKnowledgeCard(arguments: arguments, knowledgeCards: knowledgeCardStore.knowledgeCards)

        case CoachingToolSchemas.getJobDescriptionToolName:
            return toolHandler.handleGetJobDescription(arguments: arguments)

        case CoachingToolSchemas.getResumeToolName:
            return await toolHandler.handleGetResume(arguments: arguments)

        case CoachingToolSchemas.chooseBestJobsToolName:
            return await toolHandler.handleChooseBestJobs(
                arguments: arguments,
                agentService: agentService,
                knowledgeCards: knowledgeCardStore.knowledgeCards,
                dossier: candidateDossierStore.dossier
            )

        default:
            return encodeToJSON(ToolErrorResult(error: "Unknown tool: \(name)"))
        }
    }

    private func handleFinalRecommendations(_ recommendations: String) {
        guard let session = currentSession else { return }

        // Store recommendations (tasks are generated via the forced
        // update_daily_tasks completion call at the end of the session)
        session.recommendations = recommendations
        session.questionCount = collectedAnswers.count

        state = .showingRecommendations(recommendations: recommendations)
    }

    /// Map follow-up answer to action (based on value or label matching)
    private func mapFollowUpAnswer(value: Int, label: String) -> CoachingFollowUpAction {
        let lowerLabel = label.lowercased()

        if lowerLabel.contains("task") || lowerLabel.contains("to-do") || lowerLabel.contains("todo") {
            return .generateTasks
        } else if lowerLabel.contains("done") || lowerLabel.contains("good") || lowerLabel.contains("later") {
            return .done
        }

        // Default based on value (lower values = more actionable options typically)
        return value <= 2 ? .generateTasks : .done
    }

    /// Complete the coaching session
    private func completeSession() {
        guard let session = currentSession else { return }

        session.completedAt = Date()
        sessionStore.add(session)

        state = .complete(sessionId: session.id)
        Logger.info("Coaching session completed with \(collectedAnswers.count) questions", category: .ai)
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
            throw ModelConfigurationError.modelNotConfigured(
                settingKey: DiscoveryAgentService.anthropicModelSettingKey,
                operationName: "Task Regeneration"
            )
        }

        Logger.info("🔄 Regenerating \(category.displayName) tasks with feedback", category: .ai)

        // Build the prompt with context
        let prompt = taskGenerator.buildRegenerationPrompt(
            category: category,
            feedback: feedback,
            coachingRecommendations: session.recommendations,
            activitySummary: session.activitySummary?.textSummary() ?? "No activity data available"
        )

        // Execute structured request against the coaching model
        let response: TaskRegenerationResponse = try await llmFacade.executeStructuredWithAnthropicCaching(
            systemContent: [AnthropicSystemBlock(text: """
                You are a job search coach helping regenerate daily tasks based on user feedback.
                Generate practical, actionable tasks that address the user's concerns.
                Only generate tasks for the specified category: \(category.displayName).
                """)],
            userPrompt: prompt,
            modelId: modelId,
            responseType: TaskRegenerationResponse.self,
            schema: CoachingToolSchemas.buildTaskRegenerationSchema()
        )

        // Clear existing tasks for this category and add new ones
        taskGenerator.replaceTasksForCategory(category, with: response.tasks)

        Logger.info("✅ Regenerated \(response.tasks.count) \(category.displayName) tasks", category: .ai)
    }
}
