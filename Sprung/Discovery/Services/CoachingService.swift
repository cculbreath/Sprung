//
//  CoachingService.swift
//  Sprung
//
//  Main orchestration service for the Job Search Coach feature.
//
//  The session runs as one AnthropicToolLoopRunner loop against the Messages
//  API, delta-first: the coach opens with what it noticed since the last
//  session (task completion, pipeline transitions, imminent events, streaks),
//  asks at most ONE earned data-gathering question, shares a short plan, and
//  finishes through the update_daily_tasks completion tool — whose directive
//  is handed to the shared DailyTaskGenerator (the single task-generation
//  path). Question tool calls suspend inside executeTools on a continuation
//  until the user answers (submitAnswer resumes it); background research
//  tools execute immediately.
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
    /// The single daily-task generation path, shared with the Daily view's
    /// refresh and per-category regeneration.
    private let taskGenerator: DailyTaskGenerator

    /// Reference to agent service for triggering workflows like chooseBestJobs
    /// Set after initialization by coordinator to avoid circular dependency
    var agentService: DiscoveryAgentService?

    // MARK: - Observable State

    private(set) var state: CoachingState = .idle
    private(set) var currentSession: CoachingSession?
    private(set) var currentQuestion: CoachingQuestion?

    private var collectedAnswers: [CoachingAnswer] = []

    // MARK: - Session Loop State

    private var sessionSystemPrompt: String = ""
    private var sessionModelId: String = ""
    /// Data-gathering questions asked this session (policy: at most one).
    private var questionsAsked = 0
    /// Set after the plan is delivered (no-tool stall or follow-up answered)
    /// so the next turn forces the update_daily_tasks completion call.
    private var forceCompletionNextTurn = false
    /// The running session loop; cancelled by cancelSession().
    private var sessionTask: Task<Void, Never>?
    /// Monotonic token so a cancelled session's trailing error (e.g. a
    /// URLError from a torn-down request) can't clobber a newer session's state.
    private var sessionGeneration = 0
    /// Continuation parked while a question is displayed, resumed by
    /// submitAnswer with the user's selected option.
    private var pendingAnswer: CheckedContinuation<QuestionOption, Error>?

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
        weeklyGoalStore: WeeklyGoalStore,
        candidateDossierStore: CandidateDossierStore,
        knowledgeCardStore: KnowledgeCardStore,
        taskGenerator: DailyTaskGenerator
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
        self.taskGenerator = taskGenerator

        // Initialize extracted components
        self.toolHandler = CoachingToolHandler(modelContext: modelContext, jobAppStore: jobAppStore)
        self.contextBuilder = CoachingContextBuilder(
            preferencesStore: preferencesStore,
            jobAppStore: jobAppStore,
            weeklyGoalStore: weeklyGoalStore
        )
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
        collectedAnswers = []
        currentQuestion = nil
        questionsAsked = 0
        forceCompletionNextTurn = false

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

        // The delta the coach opens with: last task day + completion state,
        // today's list so far, completion streak.
        let taskDelta = contextBuilder.buildTaskDeltaSummary(
            previousDay: dailyTaskStore.previousTaskDay(),
            todaysTasks: dailyTaskStore.todaysTasks,
            streakDays: dailyTaskStore.completionStreakDays()
        )

        // Build system prompt with full context
        sessionSystemPrompt = contextBuilder.buildSystemPrompt(
            activitySummary: snapshot.textSummary(),
            recentHistory: sessionStore.recentHistorySummary(),
            taskDelta: taskDelta,
            askedCategories: sessionStore.recentAskedCategoriesSummary(),
            dossierContext: dossierContext,
            knowledgeCardsList: knowledgeCardsList,
            activeJobApps: contextBuilder.buildActiveJobAppsList()
        )

        // Drive the whole session as one shared tool loop. Question tool calls
        // suspend until the user answers; the loop completes on the
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

    /// Submit the user's selected option for the current question (data
    /// question or next-step action prompt alike).
    func submitAnswer(option: QuestionOption) {
        guard currentQuestion != nil, let continuation = pendingAnswer else {
            Logger.warning("No current question to answer", category: .ai)
            return
        }

        // Clear question immediately so UI shows loading
        pendingAnswer = nil
        currentQuestion = nil
        state = .waitingForAnswer

        continuation.resume(returning: option)
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
        [.user(
            "Start today's session. Open with what you noticed since last time — "
            + "then, only if the data warrants it, ask your one question."
        )]
    }

    func runModelTurn(messages: [AnthropicMessage]) async throws -> AnthropicTurnResult {
        let toolChoice: AnthropicToolChoice = forceCompletionNextTurn
            ? .tool(name: CoachingToolSchemas.updateDailyTasksToolName)
            : .auto
        forceCompletionNextTurn = false

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
        accumulateProse(from: result)
        return result
    }

    func executeTools(_ toolCalls: [AnthropicToolUseResponseBlock]) async -> [String: AnthropicToolOutput] {
        var outputs: [String: AnthropicToolOutput] = [:]
        var questionShownThisTurn = false

        for call in toolCalls {
            let arguments = call.input.jsonString

            if call.name == CoachingToolSchemas.multipleChoiceToolName {
                if questionShownThisTurn {
                    // One question at a time; the model gets the first answer
                    // before it may ask anything else.
                    outputs[call.id] = AnthropicToolOutput(
                        content: "Declined: only one question can be shown per turn. Continue from the answer you received.",
                        isError: true
                    )
                    continue
                }
                questionShownThisTurn = true
                outputs[call.id] = await handleQuestionToolCall(arguments: arguments)
            } else {
                let result = await handleBackgroundTool(name: call.name, arguments: arguments)
                outputs[call.id] = AnthropicToolOutput(content: result)
            }
        }
        return outputs
    }

    func parseCompletion(_ call: AnthropicToolUseResponseBlock) async throws -> Int {
        guard let session = currentSession, !session.recommendations.isEmpty else {
            // The coach tried to end the session without ever talking to the
            // user — send a corrective tool_result and keep the loop going.
            throw DiscoveryAgentError.toolExecutionFailed(
                "Not yet — share your observations and plan with the user first. "
                + "Call update_daily_tasks only at the end of the session."
            )
        }

        let directive: String
        if let data = call.input.jsonString.data(using: .utf8),
           let args = try? JSONDecoder().decode(UpdateDailyTasksArgs.self, from: data),
           !args.directive.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            directive = args.directive
        } else {
            throw DiscoveryAgentError.toolExecutionFailed(
                "Missing `directive` — pass 2-4 concrete sentences for the task generator."
            )
        }

        // Generate first: if generation fails, the runner sends a corrective
        // tool_result and the model retries the completion call — the session
        // is only finalized once tasks actually exist.
        let outcome = try await taskGenerator.generate(.coachingSession(directive: directive))
        Logger.info("✅ Daily tasks generated from coaching session", category: .ai)
        completeSession()
        return outcome.addedCount + outcome.carriedOverCount
    }

    func handleNoTool(turnCount: Int, consecutiveNoToolTurns: Int) -> AnthropicNoToolDecision {
        // A no-tool text turn is the coach's observations/plan (already
        // accumulated into session.recommendations by runModelTurn).
        state = .showingRecommendations(recommendations: currentSession?.recommendations ?? "")

        if consecutiveNoToolTurns >= 2 {
            // Converge: force the completion tool on the next turn.
            forceCompletionNextTurn = true
            return .nudge(Self.taskGenerationPrompt)
        }

        return .nudge(
            "If the session is complete, either offer the user a next-step choice with the "
            + "coaching_multiple_choice tool (options with actionId \"generate_tasks\" / \"done\"), "
            + "or call update_daily_tasks directly with your directive."
        )
    }

    func onMaxTurnsReached(messages: [AnthropicMessage]) async throws -> Int? {
        nil  // → runner throws maxTurnsError()
    }

    // MARK: - Private Implementation

    private static let taskGenerationPrompt =
        "Call update_daily_tasks now with your directive for today's task list."

    private func encodeToJSON<T: Encodable>(_ value: T) -> String {
        (try? String(data: JSONEncoder().encode(value), encoding: .utf8)) ?? "{}"
    }

    /// Append the turn's prose to the session record. Skipped for turns that
    /// only carry research tool calls (planning chatter), kept for the opener,
    /// question turns, plan turns, and the completion turn.
    private func accumulateProse(from result: AnthropicTurnResult) {
        guard let session = currentSession else { return }
        let text = result.textBlocks
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let keepsProse = result.toolCalls.isEmpty
            || result.toolCalls.contains { $0.name == CoachingToolSchemas.multipleChoiceToolName }
            || result.toolCalls.contains { $0.name == CoachingToolSchemas.updateDailyTasksToolName }
        guard keepsProse else { return }

        session.recommendations = session.recommendations.isEmpty
            ? text
            : session.recommendations + "\n\n" + text
    }

    /// Display a question tool call and suspend until the user answers.
    /// Returns the tool output carrying the user's selection.
    private func handleQuestionToolCall(arguments: String) async -> AnthropicToolOutput {
        guard let question = CoachingToolSchemas.parseQuestion(from: arguments) else {
            return AnthropicToolOutput(
                content: encodeToJSON(ToolErrorResult(error: "Failed to parse question")),
                isError: true
            )
        }

        if question.isActionPrompt {
            currentQuestion = question
            state = .askingFollowUp(question: question)
            Logger.debug("Coaching: showing next-step choice", category: .ai)
        } else {
            // Policy: at most one data-gathering question per session.
            guard questionsAsked == 0 else {
                return AnthropicToolOutput(
                    content: "Declined: you already asked your one question this session. "
                        + "Proceed to your observations and plan.",
                    isError: true
                )
            }
            questionsAsked += 1
            currentSession?.questions = (currentSession?.questions ?? []) + [question]
            currentSession?.askedCategories = (currentSession?.askedCategories ?? []) + [question.category]
            currentQuestion = question
            state = .askingQuestion(question: question)
            Logger.debug("Coaching: showing question (category: \(question.category))", category: .ai)
        }

        // Suspend until submitAnswer resumes us.
        let selection: QuestionOption
        do {
            selection = try await withCheckedThrowingContinuation { continuation in
                pendingAnswer = continuation
            }
        } catch {
            // Session cancelled while waiting — the runner's per-turn
            // cancellation check ends the loop right after this turn.
            return AnthropicToolOutput(content: "Session cancelled before the user answered.", isError: true)
        }

        if question.isActionPrompt {
            return actionAnswerOutput(for: selection)
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

    /// Map the next-step selection to its structured action identifier, then
    /// steer the model into the completion call with a matching directive.
    private func actionAnswerOutput(for selection: QuestionOption) -> AnthropicToolOutput {
        let action = selection.actionId.flatMap { CoachingFollowUpAction(rawValue: $0) }
        if let action {
            state = .executingFollowUp(action: action)
        }

        // Either way the session ends with the completion call; force it so
        // the loop converges in one more turn.
        forceCompletionNextTurn = true
        Logger.info("📋 Next-step choice: \(action?.rawValue ?? "unmapped") — requesting daily tasks", category: .ai)

        let answerJSON = encodeToJSON(ToolAnswerResult(selectedValue: selection.value, selectedLabel: selection.label))
        let steer: String
        switch action {
        case .generateTasks, .none:
            steer = "Call update_daily_tasks now with a directive summarizing today's focus from this conversation."
        case .done:
            steer = "The user is done for now. Call update_daily_tasks with a conservative directive: "
                + "carry over open tasks, retire only what is clearly stale, add nothing new unless critical."
        }
        return AnthropicToolOutput(content: answerJSON + "\n\n" + steer)
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

    /// Complete the coaching session
    private func completeSession() {
        guard let session = currentSession else { return }

        session.questionCount = collectedAnswers.count
        session.completedAt = Date()
        sessionStore.add(session)

        state = .complete(sessionId: session.id)
        Logger.info("Coaching session completed with \(collectedAnswers.count) questions", category: .ai)
    }
}
