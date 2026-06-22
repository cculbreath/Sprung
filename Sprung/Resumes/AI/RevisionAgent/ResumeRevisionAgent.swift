import Foundation
import Observation
import SwiftOpenAI
import SwiftData

// MARK: - Resume Revision Agent

@Observable
@MainActor
class ResumeRevisionAgent {
    // Dependencies
    private let workspaceService: ResumeRevisionWorkspaceService
    private weak var llmFacade: LLMFacade?
    private let modelId: String
    private let resume: Resume
    private let pdfGenerator: NativePDFGenerator
    private let modelContext: ModelContext
    private let pdfRenderer: RevisionPDFRenderer

    // State
    private(set) var status: RevisionAgentStatus = .idle
    private(set) var messages: [RevisionMessage] = []
    private(set) var currentProposal: ChangeProposal?
    private(set) var currentQuestion: String?
    private(set) var currentCompletionSummary: String?
    private(set) var turnCount: Int = 0
    private(set) var currentAction: String = ""
    private(set) var latestPDFData: Data?
    /// True only when the user cancelled (Cancel button, window close, or task
    /// cancellation from window teardown). `.cancelled` status iff this is set.
    private var isCancelled = false
    /// Set by `acceptCurrentState()` (Save): the main loop builds a new resume
    /// from the workspace at its exit boundary before deleting it — avoiding
    /// the race where a separate Task read from an already-deleted workspace.
    private var shouldBuildResumeOnExit = false
    private var consecutiveNoToolTurns = 0
    /// Count of `write_json_file` calls that succeeded this session. Any value
    /// > 0 means applied work exists in the workspace that must never be
    /// silently discarded on an early exit.
    private var successfulWriteCount = 0
    /// Consecutive stream failures (thrown transport errors or in-stream error
    /// events). Reset on any successful turn.
    private var consecutiveStreamFailures = 0
    private var activeStreamTask: Task<RevisionAgentStreamResult, Error>?
    /// In-flight completion-gate verification service. Registered so Cancel,
    /// ESC, and window teardown interrupt verification passes just like a
    /// turn's stream — without this, a cancel during "Verifying changes…"
    /// would wait out the passes' stall watchdogs while burning tokens.
    private var activeVerificationService: RevisionVerificationService?
    /// Timestamp of the most recent event received on the active stream.
    /// The per-turn watchdog cancels the stream only when this goes stale
    /// for `streamStallTimeoutSeconds` — total turn duration is unbounded.
    private var lastStreamEventDate = Date()
    /// Set by the watchdog when it cancels a stalled stream, so the
    /// cancellation path can distinguish a stall (counted as a stream
    /// failure, model nudged to split the work) from a user interrupt.
    private var streamStallDetected = false
    /// Wall-clock deadline for the session. Reset whenever the user responds to
    /// a human-in-the-loop prompt (proposal, question, completion) so idle time
    /// waiting for user input doesn't count toward the timeout.
    private var timeoutDeadline: Date = .distantFuture

    // Continuations for human-in-the-loop tools
    private var proposalContinuation: CheckedContinuation<ProposalResponse, Never>?
    private var questionContinuation: CheckedContinuation<String, Never>?
    private var completionContinuation: CheckedContinuation<Bool, Never>?

    // Conversation state (Anthropic messages). Clean history — cache
    // breakpoints are applied at request-build time only, never persisted
    // (byte-stability invariant: history is append-only so cache prefixes
    // keep matching turn over turn).
    private var conversationMessages: [AnthropicMessage] = []

    // Session-cumulative token usage (logged once at session end; per-turn
    // values are logged as each turn's usage event arrives).
    private var sessionInputTokens = 0
    private var sessionCacheReadTokens = 0
    private var sessionCacheCreationTokens = 0
    private var sessionOutputTokens = 0
    private var usageTurnCount = 0

    // Queued user messages (injected between turns)
    private var pendingUserMessages: [String] = []

    // MARK: Completion-Boundary Verification State

    /// Advisory findings for the completion card currently presented (ground
    /// truth diff vs accepted proposals, grounding audit, coherence pass).
    private(set) var currentAdvisoryReport: RevisionAdvisoryReport?

    /// Everything the user explicitly accepted (or hand-edited) in proposal
    /// reviews this session. The completion gate matches the real workspace
    /// diff against this ledger to flag writes that bypassed review.
    private struct AcceptedChangeRecord {
        let section: String
        let type: String
        let beforeText: String
        let afterText: String
    }
    private var acceptedChangeLedger: [AcceptedChangeRecord] = []

    /// Question/answer pairs from ask_user, fed to the grounding audit as a
    /// valid evidence source ("user-provided answer").
    private var askUserExchanges: [(question: String, answer: String)] = []

    /// System content and tool list for the session — stored so completion
    /// gate continuations send the byte-identical prefix every turn sent.
    private var sessionSystemContent: AnthropicSystemContent?
    private var sessionTools: [AnthropicTool] = []

    // MARK: Session Toggles (LD-1)

    /// Read ONCE at agent creation and frozen for the session (byte-stability:
    /// the tool list and prompts derived from these must never change
    /// mid-session). Defaults mirror @AppStorage semantics: true when unset.
    private let askUserToolEnabled: Bool
    private let coherencePassEnabled: Bool

    // Limits
    private let maxTurns = 50
    private let timeoutSeconds: TimeInterval = 1800 // 30 min
    private let maxConsecutiveStreamFailures = 3
    /// Output budget per turn. Section rewrites stream large JSON tool inputs;
    /// a small budget truncates them into undecodable tool calls.
    private let maxOutputTokensPerTurn = 32_000
    /// Inactivity threshold for the per-turn stream watchdog. The watchdog
    /// only fires when NO stream events arrive for this long — a healthy
    /// stream emits deltas continuously, so even a maximal 32K-token write
    /// is never cut off mid-flight; a genuinely stalled connection is.
    private let streamStallTimeoutSeconds: TimeInterval = 180

    /// Cache control for every prompt-cache breakpoint in this agent. The
    /// session is human-in-the-loop: idle gaps while the user reviews
    /// proposals routinely exceed the default 5-minute cache TTL, so all
    /// breakpoints use the 1-hour TTL (2x write cost, paid back many times
    /// over by 0.1x reads across a multi-turn session).
    private static let oneHourCacheControl = AnthropicCacheControl(type: "ephemeral", ttl: "1h")

    /// Shared message-tier breakpoint placement for this agent: 1-hour TTL and a
    /// reserved budget of 2 (the last-tool breakpoint + the system block). The
    /// moving tail and >20-block lookback are the only message-tier candidates; the
    /// single PDF rides inside the cached prefix the chain extends over — see
    /// AnthropicCacheBreakpointPlanner.
    private static let breakpointPlanner = AnthropicCacheBreakpointPlanner(
        cacheControl: oneHourCacheControl,
        reservedBreakpointCount: 2
    )

    // MARK: - Init

    private let titleSets: [TitleSetRecord]
    /// Canonical writer's-voice block (CoverRefStore.writersVoice), inlined
    /// into the system prompt. Static for the session.
    private let writersVoice: String
    /// Phrases the user has explicitly banned (VoiceProfile.avoidPhrases),
    /// surfaced as a NEVER-use list in the system prompt.
    private let avoidPhrases: [String]

    init(
        resume: Resume,
        llmFacade: LLMFacade,
        modelId: String,
        pdfGenerator: NativePDFGenerator,
        modelContext: ModelContext,
        titleSets: [TitleSetRecord] = [],
        writersVoice: String = "",
        avoidPhrases: [String] = []
    ) {
        self.resume = resume
        self.llmFacade = llmFacade
        self.modelId = modelId
        self.pdfGenerator = pdfGenerator
        self.modelContext = modelContext
        self.workspaceService = ResumeRevisionWorkspaceService()
        self.titleSets = titleSets
        self.writersVoice = writersVoice
        self.avoidPhrases = avoidPhrases
        // LD-1: both toggles are read once here and frozen for the session.
        // `object(forKey:) == nil ? true : bool(forKey:)` matches @AppStorage
        // defaulting (default true when the key has never been written).
        let defaults = UserDefaults.standard
        self.askUserToolEnabled = defaults.object(forKey: "enableResumeCustomizationTools") == nil
            ? true
            : defaults.bool(forKey: "enableResumeCustomizationTools")
        self.coherencePassEnabled = defaults.object(forKey: "enableCoherencePass") == nil
            ? true
            : defaults.bool(forKey: "enableCoherencePass")
        self.pdfRenderer = RevisionPDFRenderer(
            workspaceService: workspaceService,
            pdfGenerator: pdfGenerator,
            modelContext: modelContext
        )
    }

    // MARK: - Public API

    /// Run the revision agent loop.
    func run(jobDescription: String, knowledgeCards: [KnowledgeCard], skills: [Skill], coverRefs: [CoverRef]) async throws {
        guard let facade = llmFacade else {
            // Status is the source of truth for the view even on the earliest
            // possible failure.
            status = .failed(RevisionAgentError.noLLMFacade.localizedDescription)
            throw RevisionAgentError.noLLMFacade
        }

        status = .running
        turnCount = 0
        messages = []
        conversationMessages = []
        isCancelled = false
        shouldBuildResumeOnExit = false
        consecutiveNoToolTurns = 0
        successfulWriteCount = 0
        consecutiveStreamFailures = 0
        pendingUserMessages.removeAll()
        acceptedChangeLedger.removeAll()
        askUserExchanges.removeAll()
        currentAdvisoryReport = nil
        sessionInputTokens = 0
        sessionCacheReadTokens = 0
        sessionCacheCreationTokens = 0
        sessionOutputTokens = 0
        usageTurnCount = 0

        // Session totals are logged on every exit path (completion, Save,
        // cancel, error) — run() is the only entry point to the loop.
        defer { logSessionUsageTotals() }

        do {
            // 1. Create workspace and export materials
            currentAction = "Setting up workspace..."
            let workspacePath = try workspaceService.createWorkspace()

            try await workspaceService.exportResumePDF(resume: resume, pdfGenerator: pdfGenerator)
            let manifest = try workspaceService.exportModifiableTreeNodes(from: resume)
            try workspaceService.exportJobDescription(jobDescription)
            var jobRequirementsExported = false
            if let jobApp = resume.jobApp {
                try workspaceService.exportJobMetadata(for: jobApp)
                jobRequirementsExported = try workspaceService.exportJobRequirements(jobApp.extractedRequirements)
            }
            try workspaceService.exportKnowledgeCards(
                knowledgeCards,
                relevantCardIds: resume.jobApp?.relevantCardIds
            )
            try workspaceService.exportSkillBank(skills)
            let voiceExport = try workspaceService.exportVoiceMaterials(coverRefs)
            try workspaceService.exportFontSizeNodes(resume.fontSizeNodes)
            try workspaceService.exportTitleSets(titleSets)

            // 2. Build system prompt — static for the session, with a cache
            // breakpoint on the system block. Together with the breakpoint on
            // the last tool, this caches the full tools → system prefix
            // (tools render before system in the prompt).
            let systemPrompt = ResumeRevisionAgentPrompts.systemPrompt(
                targetPageCount: manifest.targetPageCount,
                hasTitleSets: !titleSets.isEmpty,
                writersVoice: writersVoice,
                avoidPhrases: avoidPhrases,
                askUserEnabled: askUserToolEnabled
            )
            let systemContent: AnthropicSystemContent = .blocks([
                AnthropicSystemBlock(text: systemPrompt, cacheControl: Self.oneHourCacheControl)
            ])
            sessionSystemContent = systemContent

            // 3. Build initial user message with PDF attachment
            let pdfPath = workspacePath.appendingPathComponent("resume.pdf")
            let pdfData = try Data(contentsOf: pdfPath)
            let pdfBase64 = pdfData.base64EncodedString()

            let userText = ResumeRevisionAgentPrompts.initialUserMessage(
                jobDescription: jobDescription,
                jobRequirementsAvailable: jobRequirementsExported,
                writingSamplesAvailable: voiceExport.samplesExported > 0
            )

            let initialMessage = AnthropicMessage(
                role: "user",
                content: .blocks([
                    .document(AnthropicDocumentBlock(
                        source: AnthropicDocumentSource(
                            mediaType: "application/pdf",
                            data: pdfBase64
                        )
                    )),
                    .text(AnthropicTextBlock(text: userText))
                ])
            )
            conversationMessages.append(initialMessage)

            // 4. Build tools
            let tools = buildAnthropicTools()
            sessionTools = tools

            // 5. Agent loop
            timeoutDeadline = Date().addingTimeInterval(timeoutSeconds)

            while turnCount < maxTurns {
                if shouldExitLoop() {
                    guard await confirmExitAfterCompletionGate() else { continue }
                    await handleExitCleanup(errorMessage: nil)
                    return
                }

                if Date() > timeoutDeadline {
                    throw RevisionAgentError.timeout
                }

                turnCount += 1
                currentAction = "Turn \(turnCount): Calling LLM..."
                Logger.info("RevisionAgent: Turn \(turnCount) of \(maxTurns)", category: .ai)

                // Inject any queued user messages before calling the LLM
                if !pendingUserMessages.isEmpty {
                    let combined = pendingUserMessages.joined(separator: "\n\n")
                    pendingUserMessages.removeAll()
                    // Ensure conversation ends with a user message (Anthropic requirement)
                    if conversationMessages.last?.role == "user" {
                        // Append to existing user message — don't replace, because
                        // the existing message may contain tool_result blocks that
                        // must be preserved for API alternation requirements.
                        let lastIndex = conversationMessages.count - 1
                        let existing = conversationMessages[lastIndex]
                        let userTextBlock = AnthropicContentBlock.text(AnthropicTextBlock(text: combined))
                        switch existing.content {
                        case .text(let text):
                            conversationMessages[lastIndex] = AnthropicMessage(
                                role: "user",
                                content: .blocks([
                                    .text(AnthropicTextBlock(text: text)),
                                    userTextBlock
                                ])
                            )
                        case .blocks(var blocks):
                            blocks.append(userTextBlock)
                            conversationMessages[lastIndex] = AnthropicMessage(
                                role: "user",
                                content: .blocks(blocks)
                            )
                        }
                    } else {
                        conversationMessages.append(AnthropicMessage.user(combined))
                    }
                }

                // SAFETY NET: the loop answers every tool_use id in the
                // immediately following user message (including siblings of
                // complete_revision and tools skipped during exit), so this
                // should never repair anything. If it does, that's a loop bug
                // and the repairer logs it as an error.
                AnthropicConversationRepairer.repairOrphanedToolUse(in: &conversationMessages)

                // Call Anthropic. The message-tier cache breakpoints are
                // applied to a per-request copy — conversationMessages itself
                // stays marker-free so the breakpoints move naturally each
                // turn and turn N+1 reads the prefix turn N wrote.
                let parameters = AnthropicMessageParameter(
                    model: modelId,
                    messages: Self.breakpointPlanner.plan(messages: conversationMessages),
                    system: systemContent,
                    maxTokens: maxOutputTokensPerTurn,
                    stream: true,
                    tools: tools,
                    toolChoice: .auto
                )

                let turnStart = ContinuousClock.now
                logTurnRequest(turn: turnCount, messageCount: conversationMessages.count)

                let stream: AsyncThrowingStream<AnthropicStreamEvent, Error>
                do {
                    stream = try await facade.anthropicMessagesStream(parameters: parameters)
                } catch is CancellationError {
                    // Task torn down while opening the stream — exit at the top.
                    continue
                } catch {
                    try await backOffOrAbort(after: error)
                    continue
                }

                // Process stream in a child task so it can be cancelled by
                // sendUserMessage() or the per-turn stall watchdog.
                streamStallDetected = false
                lastStreamEventDate = Date()
                let streamTask = Task { @MainActor [weak self] () -> RevisionAgentStreamResult in
                    guard let self else { return RevisionAgentStreamResult() }
                    var processor = RevisionStreamProcessor()
                    var result = RevisionAgentStreamResult()

                    do {
                        for try await event in stream {
                            try Task.checkCancellation()
                            // Any raw event counts as stream activity for the
                            // stall watchdog, including pings and unknown events.
                            self.lastStreamEventDate = Date()

                            let domainEvents = processor.process(event)
                            for domainEvent in domainEvents {
                                switch domainEvent {
                                case .textDelta(let text):
                                    self.appendOrUpdateAssistantMessage(text)

                                case .textFinalized(let fullText):
                                    result.textBlocks.append(.text(AnthropicTextBlock(text: fullText)))

                                case .toolCallReady(let id, let name, let arguments):
                                    result.toolCalls.append(RevisionStreamProcessor.ToolCallInfo(
                                        id: id, name: name, arguments: arguments
                                    ))
                                    let inputDict = self.parseToolArguments(arguments)
                                    result.toolCallBlocks.append(.toolUse(AnthropicToolUseBlock(
                                        id: id, name: name, input: inputDict
                                    )))

                                case .stopReason(let reason):
                                    result.stopReason = reason

                                case .usage(let input, let cacheRead, let cacheCreation, let output):
                                    self.recordTurnUsage(
                                        input: input,
                                        cacheRead: cacheRead,
                                        cacheCreation: cacheCreation,
                                        output: output
                                    )

                                case .streamError(let message):
                                    result.streamErrors.append(message)
                                    Logger.error("RevisionAgent: Stream error event on turn \(self.turnCount): \(message)", category: .ai)
                                }
                            }
                        }
                    } catch {
                        // Stream torn down mid-message (transport error, stall
                        // cancellation, user interrupt): the .usage event only
                        // fires at message_stop, so log the partial usage the
                        // API already counted — session totals stay honest.
                        if let usage = processor.pendingUsage {
                            self.recordTurnUsage(
                                input: usage.inputTokens,
                                cacheRead: usage.cacheReadTokens,
                                cacheCreation: usage.cacheCreationTokens,
                                output: usage.outputTokens
                            )
                        }
                        throw error
                    }

                    return result
                }
                activeStreamTask = streamTask

                // Inactivity watchdog: cancel the stream only when no events
                // have arrived for `streamStallTimeoutSeconds`. This is NOT a
                // total-duration cap — long healthy streams (large
                // write_json_file inputs under the 32K output budget) keep
                // producing events and are never cut off.
                let turnTimeoutTask = Task { @MainActor [weak self] in
                    while !Task.isCancelled {
                        try await Task.sleep(for: .seconds(15))
                        guard let self else { return }
                        if Date().timeIntervalSince(self.lastStreamEventDate) >= self.streamStallTimeoutSeconds {
                            self.streamStallDetected = true
                            Logger.warning("RevisionAgent: Turn \(self.turnCount) stream stalled — no events for \(Int(self.streamStallTimeoutSeconds))s, cancelling", category: .ai)
                            streamTask.cancel()
                            return
                        }
                    }
                }

                var streamResult: RevisionAgentStreamResult
                var streamWasInterrupted = false
                var streamFailure: Error?

                do {
                    // streamTask is unstructured, so cancellation of run()'s
                    // own task (window teardown) does not propagate to it.
                    // Forward it explicitly so the loop exits promptly instead
                    // of waiting for the stream to finish naturally.
                    streamResult = try await withTaskCancellationHandler {
                        try await streamTask.value
                    } onCancel: {
                        streamTask.cancel()
                    }
                } catch is CancellationError {
                    // Stream was interrupted by user message, timeout, or cancel
                    streamResult = RevisionAgentStreamResult()
                    streamWasInterrupted = !isCancelled
                    if streamWasInterrupted {
                        Logger.info("RevisionAgent: Stream interrupted on turn \(turnCount)", category: .ai)
                    }
                } catch {
                    // Transport error mid-stream — classified below for
                    // backoff/abort once the turn bookkeeping is done.
                    streamResult = RevisionAgentStreamResult()
                    streamFailure = error
                    Logger.error("RevisionAgent: Stream error on turn \(turnCount): \(error.localizedDescription)", category: .ai)
                }

                turnTimeoutTask.cancel()
                activeStreamTask = nil

                // Log response to transcript
                let turnDuration = turnStart.duration(to: .now)
                let turnMs = Int(turnDuration.components.seconds * 1000 + turnDuration.components.attoseconds / 1_000_000_000_000_000)
                logTurnResponse(
                    turn: turnCount,
                    messageCount: conversationMessages.count,
                    toolNames: tools.map { tool in
                        switch tool {
                        case .function(let f): return f.name
                        case .serverTool(let s): return s.name ?? s.type
                        }
                    },
                    result: streamResult,
                    interrupted: streamWasInterrupted,
                    durationMs: turnMs
                )

                // Cancellation exits immediately (this turn's output is
                // discarded, as before). A pending Save deliberately falls
                // through instead of exiting here: the completed turn is
                // persisted below — its tool calls answered with synthesized
                // "interrupted" results by the execution loop's exit checks —
                // and the TOP-of-loop boundary runs the save gate, so a user
                // who declines the gate never loses a finished turn.
                // shouldExitLoop() runs first for its Task-cancellation fold.
                if shouldExitLoop() && isCancelled {
                    await handleExitCleanup(errorMessage: nil)
                    return
                }

                // The watchdog cancelled a stalled stream. Partial output was
                // discarded (tool calls only materialize at message_stop), so
                // tell the model the turn was cut off and to retry in smaller
                // pieces — and count the stall toward consecutive stream
                // failures so a pathological session aborts with backoff
                // instead of silently re-issuing the same request to maxTurns.
                // `streamWasInterrupted` guards the race where the watchdog
                // fires just as the stream completes: a completed turn's
                // result is used normally, never discarded as a stall.
                if streamStallDetected && streamWasInterrupted {
                    pendingUserMessages.append(
                        "Your previous turn was cut off because the response stream stalled, and any tool calls from that turn were discarded. Retry in smaller pieces — for example, write one section at a time or fewer entries per write_json_file call."
                    )
                    try await backOffOrAbort(
                        message: "Stream stalled (no events for \(Int(streamStallTimeoutSeconds))s) on turn \(turnCount)",
                        isFatal: false
                    )
                    continue
                }

                // Classify stream failures: transient errors back off and
                // retry; fatal errors (auth, bad request) abort immediately.
                if let streamFailure {
                    try await backOffOrAbort(after: streamFailure)
                    continue
                }
                if let streamErrorMessage = streamResult.streamErrors.first {
                    try await backOffOrAbort(
                        message: streamErrorMessage,
                        isFatal: RevisionStreamFailureClassifier.isFatalStreamErrorEvent(streamErrorMessage)
                    )
                    continue
                }
                consecutiveStreamFailures = 0

                // Interrupted streams may have partial tool calls — discard them
                let assistantTextBlocks = streamResult.textBlocks
                var toolCallBlocks = streamResult.toolCallBlocks
                var pendingToolCalls = streamResult.toolCalls
                if streamWasInterrupted {
                    toolCallBlocks.removeAll()
                    pendingToolCalls.removeAll()
                }

                // Build and append assistant message to conversation
                let allBlocks = assistantTextBlocks + toolCallBlocks
                if !allBlocks.isEmpty {
                    let assistantMessage = AnthropicMessage(
                        role: "assistant",
                        content: .blocks(allBlocks)
                    )
                    conversationMessages.append(assistantMessage)
                }

                // If stream was interrupted (user message or timeout) with no
                // complete tool calls, just loop back so the pending message or
                // a retry gets injected at the top of the next turn.
                if pendingToolCalls.isEmpty && streamWasInterrupted {
                    Logger.info("RevisionAgent: Stream interrupted with no tool calls, continuing to next turn", category: .ai)
                    continue
                }

                // A text-only turn truncated at the output limit is not a
                // "no progress" signal — tell the model and let it continue.
                if pendingToolCalls.isEmpty && streamResult.stopReason == "max_tokens" {
                    Logger.warning("RevisionAgent: Turn \(turnCount) text truncated at max_tokens", category: .ai)
                    conversationMessages.append(AnthropicMessage.user(
                        "Your previous response was cut off at the output-token limit. Continue from where you stopped, more concisely."
                    ))
                    continue
                }

                // If no tool calls and we weren't interrupted,
                // nudge once, then let the user settle the session.
                if pendingToolCalls.isEmpty {
                    consecutiveNoToolTurns += 1
                    if consecutiveNoToolTurns >= 2 {
                        if await finishAfterStalledSession() { return }
                        consecutiveNoToolTurns = 0
                        continue
                    }
                    conversationMessages.append(AnthropicMessage.user(
                        "If you have finished all changes, please call `complete_revision` with a summary. Otherwise, continue with your next action."
                    ))
                    continue
                }
                consecutiveNoToolTurns = 0

                // Check for completion tool. Sibling tool calls in the same
                // turn are executed (or explicitly answered) first so every
                // tool_use id receives a tool_result.
                if let completionIndex = pendingToolCalls.firstIndex(where: { $0.name == CompleteRevisionTool.name }) {
                    let completionCall = pendingToolCalls[completionIndex]
                    var resultBlocks = await executeCompletionSiblings(
                        pendingToolCalls,
                        completionIndex: completionIndex
                    )

                    // Completion gate (once per completion attempt): ground-
                    // truth diff → unreviewed-write check → grounding audit →
                    // coherence pass. Its continuation request must answer
                    // every pending tool_use id, so hand it the real sibling
                    // results plus an ephemeral pending placeholder for
                    // complete_revision itself (never persisted — the real
                    // result is appended below once the user decides).
                    var gateToolResults: [AnthropicContentBlock] = []
                    for (index, call) in pendingToolCalls.enumerated() {
                        if index == completionIndex {
                            gateToolResults.append(.toolResult(AnthropicToolResultBlock(
                                toolUseId: call.id,
                                content: "{\"status\": \"pending_user_review\"}"
                            )))
                        } else if let block = resultBlocks[index] {
                            gateToolResults.append(block)
                        }
                    }
                    let advisoryReport = await runCompletionGate(pendingToolResults: gateToolResults)
                    currentAdvisoryReport = advisoryReport.isEmpty ? nil : advisoryReport

                    let accepted = await handleCompleteRevision(arguments: completionCall.arguments)
                    currentAdvisoryReport = nil
                    resultBlocks[completionIndex] = .toolResult(AnthropicToolResultBlock(
                        toolUseId: completionCall.id,
                        content: accepted ? "{\"accepted\": true}" : "{\"accepted\": false}"
                    ))

                    let userBlocks = resultBlocks.compactMap { $0 }
                    conversationMessages.append(AnthropicMessage(
                        role: "user",
                        content: .blocks(userBlocks)
                    ))

                    if accepted {
                        do {
                            try await buildAndActivateResumeFromWorkspace()
                            status = .completed
                            cleanUpWorkspace()
                        } catch {
                            handleBuildFailure(error)
                        }
                        return
                    }
                    // If rejected, continue the loop
                    continue
                }

                // Execute tool calls and collect results.
                // Anthropic requires all tool_result blocks before any other
                // content types in the user message, so we collect them separately.
                var toolResultBlocks: [AnthropicContentBlock] = []
                var hadWriteCall = false

                for toolCall in pendingToolCalls {
                    // If the session is exiting (cancel/Save), don't start more
                    // tools — especially interactive ones that would suspend
                    // with no one left to answer. Synthesize results so the
                    // conversation stays well-formed; the wording also holds
                    // when a declined save gate continues the session (the
                    // model simply re-issues the interrupted calls).
                    if shouldExitLoop() {
                        toolResultBlocks.append(.toolResult(AnthropicToolResultBlock(
                            toolUseId: toolCall.id,
                            content: "{\"error\": \"The session was interrupted before this tool ran. Call it again if it is still needed.\"}",
                            isError: true
                        )))
                        continue
                    }

                    // A tool call whose input JSON was truncated at the output
                    // limit cannot be executed — tell the model to split it.
                    if streamResult.stopReason == "max_tokens", !RevisionStreamFailureClassifier.isCompleteJSONObject(toolCall.arguments) {
                        Logger.warning("RevisionAgent: Tool call \(toolCall.name) truncated at max_tokens — asking model to split", category: .ai)
                        toolResultBlocks.append(.toolResult(AnthropicToolResultBlock(
                            toolUseId: toolCall.id,
                            content: "{\"error\": \"Tool input was truncated at the output-token limit. Split this into smaller pieces — for example, write one section at a time or fewer entries per call — and try again.\"}",
                            isError: true
                        )))
                        continue
                    }

                    currentAction = "Turn \(turnCount): \(toolDisplayName(toolCall.name))"
                    messages.append(RevisionMessage(
                        role: .toolActivity(toolCall.name),
                        content: toolDisplayName(toolCall.name)
                    ))

                    let result = await executeTool(
                        name: toolCall.name,
                        arguments: toolCall.arguments
                    )

                    toolResultBlocks.append(.toolResult(AnthropicToolResultBlock(
                        toolUseId: toolCall.id,
                        content: result.text,
                        isError: result.isError
                    )))

                    if toolCall.name == WriteJsonFileTool.name && !result.isError {
                        hadWriteCall = true
                    }
                }

                // After all tools complete, render page images ONCE for the LLM.
                // Each write_json_file already updated the preview pane; this
                // single render avoids sending N duplicate image sets.
                var trailingImageBlocks: [AnthropicContentBlock] = []
                if hadWriteCall, let pdfData = latestPDFData {
                    trailingImageBlocks = pdfRenderer.renderPDFPageImages(pdfData)
                }

                // All tool_result blocks first, then images
                let userBlocks = toolResultBlocks + trailingImageBlocks
                let toolResultMessage = AnthropicMessage(
                    role: "user",
                    content: .blocks(userBlocks)
                )
                conversationMessages.append(toolResultMessage)
            }

            // Max turns exceeded
            throw RevisionAgentError.maxTurnsExceeded

        } catch {
            if error is CancellationError {
                isCancelled = true
            }
            await handleExitCleanup(errorMessage: isCancelled ? nil : error.localizedDescription)
            // Status is the source of truth for the view; rethrow only for
            // genuine failures so callers that key off the throw stay correct.
            if case .failed = status {
                throw error
            }
        }
    }

    // MARK: - User Response Methods

    func respondToProposal(_ response: ProposalResponse) {
        guard let cont = proposalContinuation else { return }
        currentProposal = nil
        proposalContinuation = nil
        timeoutDeadline = Date().addingTimeInterval(timeoutSeconds)
        let responseText: String
        switch response {
        case .accepted:
            responseText = "Changes accepted"
        case .rejected:
            responseText = "Changes rejected"
        case .modified(let feedback):
            responseText = feedback
        case .itemized(let items):
            let accepted = items.filter { $0.kind == .accept }.count
            let rejected = items.filter { $0.kind == .reject }.count
            let feedback = items.filter { $0.kind == .feedback }.count
            let edited = items.filter { $0.kind == .edit }.count
            var parts: [String] = []
            if accepted > 0 { parts.append("\(accepted) accepted") }
            if edited > 0 { parts.append("\(edited) edited") }
            if rejected > 0 { parts.append("\(rejected) rejected") }
            if feedback > 0 { parts.append("\(feedback) with feedback") }
            responseText = "Reviewed items — " + (parts.isEmpty ? "no changes" : parts.joined(separator: ", "))
        }
        messages.append(RevisionMessage(role: .user, content: responseText))
        cont.resume(returning: response)
    }

    func respondToQuestion(_ answer: String) {
        guard let cont = questionContinuation else { return }
        currentQuestion = nil
        questionContinuation = nil
        timeoutDeadline = Date().addingTimeInterval(timeoutSeconds)
        messages.append(RevisionMessage(role: .user, content: answer))
        cont.resume(returning: answer)
    }

    func respondToCompletion(_ accepted: Bool) {
        guard let cont = completionContinuation else { return }
        completionContinuation = nil
        currentCompletionSummary = nil
        timeoutDeadline = Date().addingTimeInterval(timeoutSeconds)
        messages.append(RevisionMessage(
            role: .user,
            content: accepted ? "Revision accepted" : "Continue editing"
        ))
        cont.resume(returning: accepted)
    }

    /// Queue a free-form user message to be delivered at the next turn boundary.
    /// The active stream continues undisturbed; the message is injected before
    /// the next LLM call once the current turn completes naturally.
    ///
    /// If the agent is blocked on a human-in-the-loop continuation (proposal,
    /// question, or completion acceptance), the chat message unblocks it:
    /// - **Completion**: rejected so the loop continues with the user's new request.
    /// - **Proposal**: treated as modification feedback.
    /// - **Question**: treated as the answer.
    /// We resume the continuation directly (not via the `respond*` helpers) to
    /// avoid appending duplicate UI messages.
    func sendUserMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        pendingUserMessages.append(trimmed)
        messages.append(RevisionMessage(role: .user, content: trimmed))
        consecutiveNoToolTurns = 0

        if let cont = completionContinuation {
            // Reject — the user wants more changes.
            completionContinuation = nil
            currentCompletionSummary = nil
            timeoutDeadline = Date().addingTimeInterval(timeoutSeconds)
            cont.resume(returning: false)
        } else if let cont = proposalContinuation {
            currentProposal = nil
            proposalContinuation = nil
            timeoutDeadline = Date().addingTimeInterval(timeoutSeconds)
            cont.resume(returning: .modified(feedback: trimmed))
        } else if let cont = questionContinuation {
            currentQuestion = nil
            questionContinuation = nil
            timeoutDeadline = Date().addingTimeInterval(timeoutSeconds)
            cont.resume(returning: trimmed)
        }
    }

    /// Queue a message AND immediately cancel the active stream so the agent
    /// processes it on the very next loop iteration. Use this when the user
    /// wants to interrupt work-in-progress (e.g., Shift+Enter or "Send Now").
    func interruptWithMessage(_ text: String) {
        sendUserMessage(text)
        cancelActiveStream()
    }

    /// Cancel the active LLM stream without queuing a message.
    /// Mapped to ESC key — stops the current turn but keeps queued messages.
    /// During the completion gate this interrupts the verification passes
    /// instead (the remaining passes degrade to advisory notes).
    func cancelActiveStream() {
        activeStreamTask?.cancel()
        activeVerificationService?.cancel()
    }

    /// Accept the current workspace state and create a new resume from it.
    /// If a completion continuation is active (the agent called complete_revision),
    /// we approve it and the completion path builds. Otherwise we flag the main
    /// loop to build the resume from the workspace at its exit boundary and
    /// unblock any suspended human-in-the-loop tool so the loop can reach that
    /// boundary — Save works at any moment. Pending (unwritten) proposals are
    /// rejected; only changes already applied to the workspace are kept.
    func acceptCurrentState() {
        // If waiting on completion tool, approve it
        if completionContinuation != nil {
            respondToCompletion(true)
            return
        }
        shouldBuildResumeOnExit = true
        resumePendingContinuationsForExit()
        activeStreamTask?.cancel()
    }

    /// Single teardown entry point. Idempotent: safe to call multiple times
    /// and after the session has already ended. Cancels the active stream and
    /// resumes ANY pending continuation so none can leak; the loop then exits
    /// at its next boundary with status `.cancelled` and cleans up.
    func cancel() {
        guard !isCancelled else { return }
        isCancelled = true
        activeStreamTask?.cancel()
        activeVerificationService?.cancel()
        resumePendingContinuationsForExit()
    }

    /// Resume any suspended human-in-the-loop continuation so the agent loop
    /// can reach its exit boundary. Take-then-nil ordering guarantees no
    /// continuation is ever resumed twice.
    private func resumePendingContinuationsForExit() {
        if let cont = proposalContinuation {
            proposalContinuation = nil
            currentProposal = nil
            cont.resume(returning: .rejected)
        }
        if let cont = questionContinuation {
            questionContinuation = nil
            currentQuestion = nil
            cont.resume(returning: "")
        }
        if let cont = completionContinuation {
            completionContinuation = nil
            currentCompletionSummary = nil
            cont.resume(returning: false)
        }
    }

    // MARK: - Exit Handling

    /// True when the loop should exit: user cancel, Save, or structured-
    /// concurrency cancellation (window teardown). Folds `Task.isCancelled`
    /// into the internal flag so every exit path shares one source of truth.
    private func shouldExitLoop() -> Bool {
        if Task.isCancelled {
            isCancelled = true
        }
        return isCancelled || shouldBuildResumeOnExit
    }

    /// Settle every early exit (Save, user cancel, task cancellation, or error).
    /// Order is binding: settle the keep/discard decision first, then build if
    /// keeping, then set the honest final status, then delete the workspace.
    ///
    /// Status semantics: `.cancelled` if and only if the user cancelled;
    /// `.failed(message)` for every error exit (even when applied work was
    /// kept); `.completed` only when the Save path built successfully.
    private func handleExitCleanup(errorMessage: String?) async {
        var shouldBuild = shouldBuildResumeOnExit

        // Error exit with applied work the user hasn't decided about: offer to
        // keep the changes BEFORE anything is deleted.
        if let errorMessage, !shouldBuild, !isCancelled, successfulWriteCount > 0 {
            let summary = """
            The revision session ended early: \(errorMessage)
            \(successfulWriteCount) change(s) had already been applied to the working copy. \
            Accept to keep them in a revised resume. Choosing "Continue Editing" will \
            discard them and end the session.
            """
            messages.append(RevisionMessage(role: .assistant, content: summary))
            Logger.warning("RevisionAgent: Error exit with \(successfulWriteCount) applied write(s) — offering to keep changes", category: .ai)
            let keep = await presentCompletionCard(summary: summary)
            // `shouldBuildResumeOnExit` re-read: Save can race in while the
            // card is presented (the card then resumes false), and the Save
            // intent must still be honored. Cancel always wins: discard.
            if (keep || shouldBuildResumeOnExit) && !isCancelled {
                shouldBuild = true
            }
        }

        if shouldBuild {
            do {
                try await buildAndActivateResumeFromWorkspace()
                if let errorMessage {
                    status = .failed("\(errorMessage) The changes applied before the failure were kept.")
                } else {
                    status = .completed
                }
            } catch {
                handleBuildFailure(error)
                // Workspace was moved aside for salvage — see handleBuildFailure.
                return
            }
        } else if isCancelled {
            status = .cancelled
        } else if let errorMessage {
            status = .failed(errorMessage)
        } else {
            // Defensive: no error, not cancelled, nothing to build — treat as
            // a cancellation so the exit stays silent rather than lying about
            // completion.
            status = .cancelled
        }

        cleanUpWorkspace()
    }

    /// The model produced no tool calls on two consecutive turns. With no
    /// applied writes the session completes quietly; with applied work the
    /// user decides whether to keep it — applied work is never silently
    /// deleted. Returns true when run() should return, false to continue.
    private func finishAfterStalledSession() async -> Bool {
        guard successfulWriteCount > 0 else {
            Logger.info("RevisionAgent: No tool calls for two turns and no applied changes — completing", category: .ai)
            messages.append(RevisionMessage(
                role: .assistant,
                content: "Revision session complete."
            ))
            status = .completed
            cleanUpWorkspace()
            return true
        }

        let summary = """
        The assistant stopped taking actions without formally completing the revision, \
        but \(successfulWriteCount) change(s) were already applied to the working copy. \
        Accept to keep them in a revised resume, or choose "Continue Editing" to keep working.
        """
        messages.append(RevisionMessage(role: .assistant, content: summary))
        Logger.warning("RevisionAgent: Stalled with \(successfulWriteCount) applied write(s) — asking user to keep or continue", category: .ai)

        let accepted = await presentCompletionCard(summary: summary)

        if accepted {
            do {
                try await buildAndActivateResumeFromWorkspace()
                status = .completed
                cleanUpWorkspace()
            } catch {
                handleBuildFailure(error)
            }
            return true
        }

        if shouldExitLoop() {
            // The decision was settled by cancel()/Save, not the user clicking
            // "Continue Editing" — let the loop's boundary handle the exit.
            return false
        }

        // User chose to continue — give the model a fresh instruction.
        conversationMessages.append(AnthropicMessage.user(
            "The user chose to continue the session. Ask what they would like to change next, or proceed with any remaining improvements."
        ))
        return false
    }

    /// Terminal path when applying the workspace to a new resume fails after
    /// the keep decision was already settled. The workspace holds the only
    /// copy of the applied work, so it is moved OUT of the swept
    /// `revision-workspace/` base directory — which the next session's
    /// startup sweep clears wholesale — and the preserved location is
    /// included in the failure message so the user can salvage the JSON.
    private func handleBuildFailure(_ error: Error) {
        Logger.error("RevisionAgent: Failed to build revised resume: \(error.localizedDescription)", category: .ai)
        var message = "Could not apply the revised resume: \(error.localizedDescription)"
        if let workspace = workspaceService.workspacePath {
            if let preserved = preserveFailedSessionWorkspace(at: workspace) {
                message += " The changes applied during this session were preserved at: \(preserved.path)"
            } else {
                message += " The changes applied during this session are still at: \(workspace.path) — salvage them before starting another revision session, which clears that directory."
            }
        }
        messages.append(RevisionMessage(role: .assistant, content: message))
        status = .failed(message)
    }

    /// Move a failed session's workspace to a sibling of the swept base
    /// directory (`<base>-failed/<session-id>/`) so the next session's
    /// stale-sibling sweep cannot destroy the only copy of the applied work.
    /// The salvage destination is derived from the service-provided workspace
    /// path, never constructed independently. Returns the preserved location,
    /// or nil when the move failed (the workspace then remains at its
    /// original, sweep-exposed path).
    private func preserveFailedSessionWorkspace(at workspace: URL) -> URL? {
        let fileManager = FileManager.default
        let sweptBase = workspace.deletingLastPathComponent()
        let salvageRoot = sweptBase
            .deletingLastPathComponent()
            .appendingPathComponent(sweptBase.lastPathComponent + "-failed", isDirectory: true)
        let destination = salvageRoot.appendingPathComponent(workspace.lastPathComponent, isDirectory: true)
        do {
            try fileManager.createDirectory(at: salvageRoot, withIntermediateDirectories: true)
            pruneOldSalvageDirectories(in: salvageRoot)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: workspace, to: destination)
            Logger.warning("RevisionAgent: Preserved failed-session workspace at \(destination.path)", category: .ai)
            return destination
        } catch {
            Logger.error("RevisionAgent: Could not preserve failed-session workspace: \(error.localizedDescription)", category: .ai)
            return nil
        }
    }

    /// Remove salvage directories older than 30 days so failed sessions
    /// cannot accumulate unbounded. Best-effort: failures are logged and
    /// never block preservation of the current session.
    private func pruneOldSalvageDirectories(in salvageRoot: URL) {
        let fileManager = FileManager.default
        let cutoff = Date().addingTimeInterval(-30 * 24 * 60 * 60)
        let contents: [URL]
        do {
            contents = try fileManager.contentsOfDirectory(
                at: salvageRoot,
                includingPropertiesForKeys: [.contentModificationDateKey]
            )
        } catch {
            Logger.warning("RevisionAgent: Could not enumerate salvage directory for pruning: \(error.localizedDescription)", category: .ai)
            return
        }
        for item in contents {
            guard let modified = (try? item.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                  modified < cutoff else { continue }
            do {
                try fileManager.removeItem(at: item)
                Logger.info("RevisionAgent: Pruned expired salvage directory '\(item.lastPathComponent)'", category: .ai)
            } catch {
                Logger.warning("RevisionAgent: Could not prune salvage item '\(item.lastPathComponent)': \(error.localizedDescription)", category: .ai)
            }
        }
    }

    /// Delete the workspace, logging (never swallowing) failures.
    private func cleanUpWorkspace() {
        do {
            try workspaceService.deleteWorkspace()
        } catch {
            Logger.error("RevisionAgent: Failed to delete workspace: \(error.localizedDescription)", category: .ai)
        }
    }

    // MARK: - Stream Failure Classification

    /// Classify a thrown stream failure, then back off (transient) or abort
    /// the session (fatal / too many consecutive failures).
    private func backOffOrAbort(after error: Error) async throws {
        let classification = RevisionStreamFailureClassifier.classifyStreamFailure(error)
        try await backOffOrAbort(message: classification.message, isFatal: classification.isFatal)
    }

    private func backOffOrAbort(message: String, isFatal: Bool) async throws {
        if isFatal {
            Logger.error("RevisionAgent: Fatal stream failure: \(message)", category: .ai)
            throw RevisionAgentError.streamFailed(message)
        }
        consecutiveStreamFailures += 1
        guard consecutiveStreamFailures < maxConsecutiveStreamFailures else {
            Logger.error("RevisionAgent: Aborting after \(consecutiveStreamFailures) consecutive stream failures: \(message)", category: .ai)
            throw RevisionAgentError.streamFailed("\(message) (failed \(consecutiveStreamFailures) times in a row)")
        }
        let delaySeconds = pow(2.0, Double(consecutiveStreamFailures)) // 2s, 4s
        Logger.warning("RevisionAgent: Transient stream failure (\(message)) — retrying in \(Int(delaySeconds))s", category: .ai)
        currentAction = "Connection issue — retrying in \(Int(delaySeconds))s..."
        try await Task.sleep(for: .seconds(delaySeconds))
    }

    // MARK: - Tool Building

    /// Fixed, deterministic tool order (prompt-cache invariant: tools render
    /// at position 0; any reorder invalidates the entire cache). The cache
    /// breakpoint on the LAST tool caches the whole tool block. AskUserTool
    /// is registered only when the user enabled AI follow-up questions —
    /// the toggle is frozen at session start, so the list never changes
    /// mid-session.
    private func buildAnthropicTools() -> [AnthropicTool] {
        var tools: [AnthropicTool] = [
            AnthropicSchemaConverter.anthropicTool(from: ReadFileTool.self),
            AnthropicSchemaConverter.anthropicTool(from: ListDirectoryTool.self),
            AnthropicSchemaConverter.anthropicTool(from: GlobSearchTool.self),
            AnthropicSchemaConverter.anthropicTool(from: GrepSearchTool.self),
            AnthropicSchemaConverter.anthropicTool(from: WriteJsonFileTool.self),
            AnthropicSchemaConverter.anthropicTool(from: ProposeChangesTool.self)
        ]
        if askUserToolEnabled {
            tools.append(AnthropicSchemaConverter.anthropicTool(from: AskUserTool.self))
        }
        tools.append(AnthropicSchemaConverter.anthropicTool(from: CompleteRevisionTool.self, cacheControl: Self.oneHourCacheControl))
        return tools
    }

    // MARK: - Usage Tracking

    /// Log per-turn token usage and accumulate session totals. From turn 2
    /// onward cache_read should cover tools + system + prior conversation
    /// (including the resume PDF and accumulated page images); a zero there
    /// is the regression signal.
    private func recordTurnUsage(input: Int, cacheRead: Int, cacheCreation: Int, output: Int) {
        Logger.info(
            "🤖 RevisionAgent turn \(turnCount) usage (\(modelId)): input=\(input) cache_read=\(cacheRead) cache_create=\(cacheCreation) output=\(output)",
            category: .ai
        )
        sessionInputTokens += input
        sessionCacheReadTokens += cacheRead
        sessionCacheCreationTokens += cacheCreation
        sessionOutputTokens += output
        usageTurnCount += 1
    }

    /// Log session-cumulative usage once, on every exit path out of run().
    private func logSessionUsageTotals() {
        guard usageTurnCount > 0 else { return }
        Logger.info(
            "🤖 RevisionAgent session usage (\(modelId)): turns=\(usageTurnCount) input=\(sessionInputTokens) cache_read=\(sessionCacheReadTokens) cache_create=\(sessionCacheCreationTokens) output=\(sessionOutputTokens)",
            category: .ai
        )
    }

    // MARK: - Tool Execution Result

    /// Result from executing a tool.
    private struct ToolExecutionResult {
        let text: String
        var isError: Bool = false
    }

    // MARK: - Tool Execution

    private func executeTool(name: String, arguments: String) async -> ToolExecutionResult {
        guard let workspacePath = workspaceService.workspacePath else {
            return ToolExecutionResult(text: "Error: Workspace not initialized", isError: true)
        }

        do {
            let argsData = arguments.data(using: .utf8) ?? Data()

            switch name {
            case ReadFileTool.name:
                let params = try JSONDecoder().decode(ReadFileTool.Parameters.self, from: argsData)
                let result = try ReadFileTool.execute(parameters: params, repoRoot: workspacePath)
                return ToolExecutionResult(text: formatReadResult(result))

            case ListDirectoryTool.name:
                let params = try JSONDecoder().decode(ListDirectoryTool.Parameters.self, from: argsData)
                let result = try ListDirectoryTool.execute(parameters: params, repoRoot: workspacePath)
                return ToolExecutionResult(text: result.formattedTree)

            case GlobSearchTool.name:
                let params = try JSONDecoder().decode(GlobSearchTool.Parameters.self, from: argsData)
                let result = try GlobSearchTool.execute(parameters: params, repoRoot: workspacePath)
                return ToolExecutionResult(text: formatGlobResult(result))

            case GrepSearchTool.name:
                let params = try JSONDecoder().decode(GrepSearchTool.Parameters.self, from: argsData)
                let result = try GrepSearchTool.execute(parameters: params, repoRoot: workspacePath)
                return ToolExecutionResult(text: formatGrepResult(result))

            case WriteJsonFileTool.name:
                let params = try JSONDecoder().decode(WriteJsonFileTool.Parameters.self, from: argsData)
                let result = try WriteJsonFileTool.execute(parameters: params, repoRoot: workspacePath)
                successfulWriteCount += 1
                // Auto-render for the live preview pane (no images for LLM yet —
                // a single set of page images is appended after all tools complete)
                let renderInfo = await pdfRenderer.autoRenderResume(from: resume)
                latestPDFData = renderInfo.pdfData
                let text = "{\"success\": true, \"path\": \"\(result.path)\", \"itemCount\": \(result.itemCount), \"pageCount\": \(renderInfo.pageCount), \"renderSuccess\": \(renderInfo.success)}"
                return ToolExecutionResult(text: text)

            case ProposeChangesTool.name:
                let params = try JSONDecoder().decode(ProposeChangesTool.Parameters.self, from: argsData)
                return ToolExecutionResult(text: await executeProposal(params))

            case AskUserTool.name:
                let params = try JSONDecoder().decode(AskUserTool.Parameters.self, from: argsData)
                return ToolExecutionResult(text: await executeAskUser(params))

            default:
                return ToolExecutionResult(text: "Unknown tool: \(name)", isError: true)
            }
        } catch {
            Logger.error("RevisionAgent tool error (\(name)): \(error.localizedDescription)", category: .ai)
            return ToolExecutionResult(text: "Error: \(error.localizedDescription)", isError: true)
        }
    }

    /// Execute (or explicitly answer) every sibling of a `complete_revision`
    /// call so each tool_use id receives a tool_result. Workspace tools run
    /// normally; interactive tools are answered with an explanatory error so
    /// the model can re-issue them if the user continues the session.
    /// Returns a slot array aligned with `pendingToolCalls`; the completion
    /// slot is left nil for the caller to fill.
    private func executeCompletionSiblings(
        _ pendingToolCalls: [RevisionStreamProcessor.ToolCallInfo],
        completionIndex: Int
    ) async -> [AnthropicContentBlock?] {
        var resultBlocks: [AnthropicContentBlock?] = Array(repeating: nil, count: pendingToolCalls.count)

        for (index, call) in pendingToolCalls.enumerated() where index != completionIndex {
            if call.name == CompleteRevisionTool.name {
                resultBlocks[index] = .toolResult(AnthropicToolResultBlock(
                    toolUseId: call.id,
                    content: "{\"error\": \"Duplicate complete_revision call in the same turn was ignored\"}",
                    isError: true
                ))
            } else if call.name == ProposeChangesTool.name || call.name == AskUserTool.name {
                resultBlocks[index] = .toolResult(AnthropicToolResultBlock(
                    toolUseId: call.id,
                    content: "{\"error\": \"Not shown to the user: complete_revision was called in the same turn. If the user continues the session, call this tool again in its own turn.\"}",
                    isError: true
                ))
            } else if shouldExitLoop() {
                resultBlocks[index] = .toolResult(AnthropicToolResultBlock(
                    toolUseId: call.id,
                    content: "{\"error\": \"The session was interrupted before this tool ran. Call it again if it is still needed.\"}",
                    isError: true
                ))
            } else {
                currentAction = "Turn \(turnCount): \(toolDisplayName(call.name))"
                messages.append(RevisionMessage(
                    role: .toolActivity(call.name),
                    content: toolDisplayName(call.name)
                ))
                let result = await executeTool(name: call.name, arguments: call.arguments)
                resultBlocks[index] = .toolResult(AnthropicToolResultBlock(
                    toolUseId: call.id,
                    content: result.text,
                    isError: result.isError
                ))
            }
        }

        return resultBlocks
    }

    // MARK: - Human-in-the-Loop Tools

    private func executeProposal(_ params: ProposeChangesTool.Parameters) async -> String {
        // Ground-truth verification: check each before-preview against the
        // ACTUAL workspace content so the user reviews reality, not the
        // model's claims about reality.
        let proposal = ChangeProposal(
            summary: params.summary,
            changes: params.changes,
            verifications: workspaceService.verifyProposedChanges(params.changes)
        )

        currentProposal = proposal
        messages.append(RevisionMessage(
            role: .assistant,
            content: "Proposed changes: \(params.summary)"
        ))

        let response = await awaitProposalDecision()
        currentProposal = nil
        recordAcceptedChanges(from: proposal, response: response)
        return response.toolResultJSON
    }

    /// Record what the user actually approved, so the completion gate can
    /// flag workspace writes that match no accepted proposal.
    private func recordAcceptedChanges(from proposal: ChangeProposal, response: ProposalResponse) {
        func record(_ change: ProposeChangesTool.ChangeDetail, editedText: String? = nil) {
            acceptedChangeLedger.append(AcceptedChangeRecord(
                section: change.section,
                type: change.type,
                beforeText: change.beforePreview ?? "",
                afterText: editedText ?? change.afterPreview ?? ""
            ))
        }

        switch response {
        case .accepted:
            for change in proposal.changes { record(change) }
        case .rejected, .modified:
            break
        case .itemized(let items):
            for item in items {
                guard proposal.changes.indices.contains(item.index) else { continue }
                switch item.kind {
                case .accept:
                    record(proposal.changes[item.index])
                case .edit:
                    record(proposal.changes[item.index], editedText: item.editedText)
                case .reject, .feedback:
                    break
                }
            }
        }
    }

    private func executeAskUser(_ params: AskUserTool.Parameters) async -> String {
        currentQuestion = params.question
        messages.append(RevisionMessage(
            role: .assistant,
            content: params.question
        ))

        let answer = await awaitQuestionAnswer()
        currentQuestion = nil
        if !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Evidence source for the grounding audit ("user-provided answer").
            askUserExchanges.append((question: params.question, answer: answer))
        }

        let payload = ["answer": answer]
        if let data = try? JSONSerialization.data(withJSONObject: payload),
           let json = String(data: data, encoding: .utf8) {
            return json
        }
        return "{\"answer\": \"\"}"
    }

    /// Present the completion card and wait for the user's decision.
    /// Used by `complete_revision` and by every work-preserving exit offer.
    private func handleCompleteRevision(arguments: String) async -> Bool {
        let summary: String
        do {
            guard let data = arguments.data(using: .utf8) else {
                throw RevisionAgentError.invalidToolCall("complete_revision arguments were not valid UTF-8")
            }
            summary = try JSONDecoder().decode(CompleteRevisionTool.Parameters.self, from: data).summary
        } catch {
            Logger.error("RevisionAgent: Malformed complete_revision arguments: \(error.localizedDescription)", category: .ai)
            summary = "The assistant signaled that the revision is complete."
        }

        messages.append(RevisionMessage(
            role: .assistant,
            content: "Revision complete: \(summary)"
        ))

        // The card consumes a pending Save: Accept builds (satisfying the
        // Save) with the just-computed advisories in view, instead of
        // silently rejecting the completion and re-running the entire gate
        // at the loop's exit boundary.
        return await presentCompletionCard(summary: summary, consumingSaveIntent: true)
    }

    // MARK: - Completion Gate (Ground Truth → Grounding → Coherence)

    /// Assemble the advisory report for a completion attempt. Order is fixed:
    /// ground-truth diff → unreviewed-write check → grounding audit →
    /// coherence pass (when enabled). An empty diff skips both LLM passes
    /// entirely. Advisory by design: every failure degrades to a note and the
    /// completion proceeds — verification is a quality gate, never a blocker.
    /// Runs once per completion attempt, so a later attempt after further
    /// edits re-audits the updated diff.
    private func runCompletionGate(pendingToolResults: [AnthropicContentBlock]) async -> RevisionAdvisoryReport {
        var report = RevisionAdvisoryReport()

        // A cancelled session is being torn down — don't spend LLM calls on a
        // completion card that will never be answered.
        guard !isCancelled else { return report }

        let diff: RevisionWorkspaceDiff
        do {
            diff = try workspaceService.computeWorkspaceDiff()
        } catch {
            Logger.warning("RevisionAgent: Completion gate could not compute the workspace diff: \(error.localizedDescription)", category: .ai)
            return report
        }
        guard !diff.isEmpty else { return report }

        currentAction = "Verifying changes..."

        // 1. Unreviewed writes: real changes that match no accepted proposal.
        report.unreviewedWrites = diff.entries.filter { !isCoveredByAcceptedProposal($0) }

        // 2 & 3. LLM verification passes, issued as continuations of the live
        // session conversation so the cached prefix is read, not re-billed.
        guard let facade = llmFacade, let systemContent = sessionSystemContent, !sessionTools.isEmpty else {
            report.notes.append("Verification passes could not run (session context unavailable).")
            return report
        }
        let service = RevisionVerificationService(llmFacade: facade, modelId: modelId)
        // Register so Cancel/ESC/teardown can interrupt the in-flight pass.
        activeVerificationService = service
        defer { activeVerificationService = nil }
        let baseMessages = Self.breakpointPlanner.plan(messages: conversationMessages)
        let usageCallback: RevisionVerificationService.UsageCallback = { [weak self] input, cacheRead, cacheCreation, output in
            self?.accumulateVerificationUsage(input: input, cacheRead: cacheRead, cacheCreation: cacheCreation, output: output)
        }

        let corpusResult = workspaceService.readGroundingCorpus()
        if let groundingFlags = await service.verifyGrounding(
            baseMessages: baseMessages,
            pendingToolResults: pendingToolResults,
            system: systemContent,
            tools: sessionTools,
            diff: diff,
            corpus: corpusResult.corpus,
            askUserExchanges: askUserExchanges,
            onUsage: usageCallback
        ) {
            report.grounding = groundingFlags
            if diff.entries.count > RevisionVerificationService.maxAuditedChanges {
                report.notes.append(
                    "Only the first \(RevisionVerificationService.maxAuditedChanges) of \(diff.entries.count) changes were fact-checked."
                )
            }
            if corpusResult.wasTruncated {
                report.notes.append(
                    "The evidence corpus was truncated for length — the audit ran on partial evidence, so some \"unsupported\" flags may be false positives."
                )
            }
        } else {
            report.notes.append("The grounding check could not run — claims in the changes were not independently verified.")
        }

        // Cancel/ESC during the grounding pass must not start the coherence
        // call (and a torn-down session gets no card at all).
        guard !isCancelled else { return report }

        if coherencePassEnabled {
            let resumeText = (try? workspaceService.renderCurrentResumeText()) ?? ""
            if !resumeText.isEmpty {
                if let coherenceFlags = await service.verifyCoherence(
                    baseMessages: baseMessages,
                    pendingToolResults: pendingToolResults,
                    system: systemContent,
                    tools: sessionTools,
                    resumeText: resumeText,
                    onUsage: usageCallback
                ) {
                    report.coherence = coherenceFlags
                } else {
                    report.notes.append("The coherence check could not run for this completion.")
                }
            } else {
                report.notes.append("The coherence check could not run for this completion.")
            }
        }

        return report
    }

    /// Gate a Save exit (`acceptCurrentState`) on the completion verification.
    /// Returns true when the loop should proceed to exit (build + cleanup),
    /// false when the user reviewed the advisories and chose to keep editing.
    private func confirmExitAfterCompletionGate() async -> Bool {
        // Only a Save (build) intent is gated; cancellation always exits.
        guard shouldBuildResumeOnExit, !isCancelled else { return true }

        let report = await runCompletionGate(pendingToolResults: [])
        // Notes alone never gate a save — a failed check must not block it.
        guard report.hasActionableFlags, !isCancelled else { return true }

        // Present the completion card with the advisories. The card consumes
        // the pending Save intent (it IS the save decision); Cancel and a
        // racing second Save are honored by the re-checks below.
        currentAdvisoryReport = report
        let summary = "Save requested — the verification pass flagged the items below. "
            + "Accept to save the revised resume anyway, or choose \"Continue Editing\" to address them first."
        messages.append(RevisionMessage(role: .assistant, content: summary))
        Logger.info(
            "RevisionAgent: Save gated on \(report.unreviewedWrites.count) unreviewed write(s), \(report.grounding.count) grounding flag(s), \(report.coherence.count) coherence flag(s)",
            category: .ai
        )

        let accepted = await presentCompletionCard(summary: summary, consumingSaveIntent: true)
        currentAdvisoryReport = nil

        if accepted || shouldBuildResumeOnExit || isCancelled {
            // Cancel wins (discard); otherwise the save intent is restored.
            if !isCancelled { shouldBuildResumeOnExit = true }
            return true
        }

        // The user chose to keep editing: hand the findings to the model so
        // the next turn addresses them.
        pendingUserMessages.append(
            "I asked to save, but the pre-save verification flagged issues, and I chose to continue editing instead. Please address these findings:\n\(report.modelReadableSummary)"
        )
        return false
    }

    /// True when a ground-truth diff entry is plausibly covered by a change
    /// the user accepted (or hand-edited) in a proposal review. Heuristic by
    /// necessity — proposal previews are free text — and used for ADVISORY
    /// flags only, never to block anything.
    private func isCoveredByAcceptedProposal(_ entry: RevisionNodeDiff) -> Bool {
        func covered(_ value: String, by recordText: KeyPath<AcceptedChangeRecord, String>) -> Bool {
            let target = RevisionGroundTruth.normalizedForMatch(value)
            guard !target.isEmpty else { return true }
            for record in acceptedChangeLedger {
                let text = RevisionGroundTruth.normalizedForMatch(record[keyPath: recordText])
                guard !text.isEmpty else { continue }
                // Equality, or the node value appearing inside the reviewed
                // preview (list proposals render whole lists in one preview).
                if text == target || text.contains(target) { return true }
                // The reviewed preview appearing inside the node value, with
                // a length guard so trivia cannot match everything.
                if target.count >= 24, text.count >= 24, target.contains(text) { return true }
            }
            return false
        }

        switch entry.kind {
        case .modified, .added:
            guard let newValue = entry.newValue else { return true }
            return covered(newValue, by: \.afterText)
        case .removed:
            // A removal is covered when the removed text appeared in a
            // reviewed before-preview (the user saw it on its way out).
            guard let oldValue = entry.oldValue else { return true }
            return covered(oldValue, by: \.beforeText)
        }
    }

    /// Fold verification-pass usage into the session totals (the per-call
    /// line is logged by the verification service itself).
    private func accumulateVerificationUsage(input: Int, cacheRead: Int, cacheCreation: Int, output: Int) {
        sessionInputTokens += input
        sessionCacheReadTokens += cacheRead
        sessionCacheCreationTokens += cacheCreation
        sessionOutputTokens += output
        usageTurnCount += 1
    }

    // MARK: - Continuation Awaits

    /// All three awaits short-circuit when the session is already exiting and
    /// are wrapped in a cancellation handler that funnels into `cancel()`, so
    /// window teardown can never leak a continuation even if the teardown hook
    /// is missed.

    /// The exit re-check inside each `withCheckedContinuation` body is load-
    /// bearing: `cancel()`/`acceptCurrentState()` can interleave on the actor
    /// at the awaits between the early check and the assignment. The body runs
    /// synchronously on the MainActor, so a continuation is either resumed
    /// immediately or assigned while the session is still live — it can never
    /// be assigned after the teardown sweep already ran.

    private func awaitProposalDecision() async -> ProposalResponse {
        if shouldExitLoop() { return .rejected }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<ProposalResponse, Never>) in
                if self.shouldExitLoop() {
                    continuation.resume(returning: .rejected)
                } else {
                    self.proposalContinuation = continuation
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel() }
        }
    }

    private func awaitQuestionAnswer() async -> String {
        if shouldExitLoop() { return "" }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
                if self.shouldExitLoop() {
                    continuation.resume(returning: "")
                } else {
                    self.questionContinuation = continuation
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel() }
        }
    }

    /// Present the completion card and wait for the user's decision.
    ///
    /// `consumingSaveIntent` is set by callers for whom the card itself IS
    /// the save decision (the complete_revision path and the save gate):
    /// there, a pending Save does not skip the card — the intent is consumed
    /// and the user decides with the advisories in view; Accept builds, which
    /// satisfies the Save. Without it (error exit, stalled session), a
    /// pending Save short-circuits as before so the caller's own save
    /// handling (handleExitCleanup's re-read, the loop boundary) stays in
    /// charge. Cancellation short-circuits in every case.
    private func presentCompletionCard(summary: String, consumingSaveIntent: Bool = false) async -> Bool {
        if cardShortCircuits(consumingSaveIntent: consumingSaveIntent) { return false }
        currentCompletionSummary = summary
        let accepted = await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                if self.cardShortCircuits(consumingSaveIntent: consumingSaveIntent) {
                    continuation.resume(returning: false)
                } else {
                    self.completionContinuation = continuation
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel() }
        }
        currentCompletionSummary = nil
        return accepted
    }

    /// Exit check for the completion card. Mirrors `shouldExitLoop()`'s
    /// Task-cancellation folding; when the caller consumes save intents, a
    /// pending Save is cleared (the card replaces it as the save decision)
    /// instead of short-circuiting the card into a silent rejection.
    private func cardShortCircuits(consumingSaveIntent: Bool) -> Bool {
        if Task.isCancelled { isCancelled = true }
        if isCancelled { return true }
        guard shouldBuildResumeOnExit else { return false }
        guard consumingSaveIntent else { return true }
        shouldBuildResumeOnExit = false
        return false
    }

    // MARK: - Build & Activate

    /// Build a new resume from the current workspace state and activate it.
    ///
    /// CRITICAL ORDERING: All synchronous work (node import, resume creation,
    /// selection, and modelContext.save()) happens BEFORE any async work (PDF
    /// generation). This guarantees the data is persisted even if the user
    /// closes the window immediately after clicking Save — SwiftUI cancels the
    /// `.task`, but the save has already hit the persistent store.
    private func buildAndActivateResumeFromWorkspace() async throws {
        let revisedNodes = try workspaceService.importRevisedTreeNodes()
        let revisedFontSizes = try workspaceService.importRevisedFontSizes()
        let newResume = try workspaceService.buildNewResume(
            from: resume,
            revisedNodes: revisedNodes,
            revisedFontSizes: revisedFontSizes,
            context: modelContext
        )

        // Activate and persist BEFORE any async work. Everything above and
        // below this comment is synchronous — no suspension points — so task
        // cancellation cannot prevent the save from completing.
        resume.jobApp?.selectedRes = newResume
        try modelContext.save()
        Logger.info("RevisionAgent: Persisted revised resume and activated in editor", category: .ai)

        // Surface import discrepancies (sections skipped, unmatched ids,
        // blocked edits, pruned nodes, manual-edit conflicts) in the transcript.
        if let report = workspaceService.lastImportReport, !report.isEmpty {
            messages.append(RevisionMessage(
                role: .assistant,
                content: "Import notes:\n\(report.summaryText)"
            ))
            Logger.warning("RevisionAgent: Import report — \(report.summaryText)", category: .ai)
        }

        // Best-effort PDF generation. If the window closes (task cancelled)
        // during this step the resume data is already saved. The main window
        // will regenerate the PDF on next display if needed.
        do {
            let template = try pdfGenerator.resolveTemplate(for: newResume)
            let pdfData = try await pdfGenerator.generatePDF(for: newResume, template: template.slug)
            newResume.pdfData = pdfData
            try modelContext.save()
        } catch {
            Logger.error("RevisionAgent: Post-save PDF generation failed (data is safe): \(error)", category: .ai)
        }
    }

    // MARK: - Message Helpers

    private func appendOrUpdateAssistantMessage(_ delta: String) {
        if let last = messages.last, case .assistant = last.role {
            // Update the last assistant message by replacing it
            let updated = RevisionMessage(
                role: .assistant,
                content: last.content + delta
            )
            messages[messages.count - 1] = updated
        } else {
            messages.append(RevisionMessage(role: .assistant, content: delta))
        }
    }

    // MARK: - Formatting Helpers

    private func formatReadResult(_ result: ReadFileTool.Result) -> String {
        var output = "File content (lines \(result.startLine)-\(result.endLine) of \(result.totalLines)):\n"
        output += result.content
        if result.hasMore {
            output += "\n\n[File has more content. Use offset=\(result.endLine + 1) to read more.]"
        }
        return output
    }

    private func formatGlobResult(_ result: GlobSearchTool.Result) -> String {
        var lines: [String] = ["Found \(result.totalMatches) files:"]
        for file in result.files {
            lines.append("  \(file.relativePath)")
        }
        if result.truncated {
            lines.append("  ... and \(result.totalMatches - result.files.count) more")
        }
        return lines.joined(separator: "\n")
    }

    private func formatGrepResult(_ result: GrepSearchTool.Result) -> String {
        result.formatted
    }

    private func parseToolArguments(_ arguments: String) -> [String: Any] {
        guard let data = arguments.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return dict
    }

    private func toolDisplayName(_ name: String) -> String {
        switch name {
        case ReadFileTool.name: return "Reading file"
        case ListDirectoryTool.name: return "Listing directory"
        case GlobSearchTool.name: return "Searching files"
        case GrepSearchTool.name: return "Searching content"
        case WriteJsonFileTool.name: return "Writing JSON & rendering"
        case ProposeChangesTool.name: return "Proposing changes"
        case AskUserTool.name: return "Asking question"
        case CompleteRevisionTool.name: return "Completing revision"
        default: return name
        }
    }

    // MARK: - Transcript Logging

    /// Log the outgoing request before the stream starts.
    private func logTurnRequest(turn: Int, messageCount: Int) {
        // Summarize the last message (most recent context sent to LLM)
        let lastMessageSummary: String
        if let last = conversationMessages.last {
            switch last.content {
            case .text(let text):
                lastMessageSummary = "[\(last.role)] \(String(text.prefix(500)))"
            case .blocks(let blocks):
                let blockSummaries = blocks.prefix(5).map { block -> String in
                    switch block {
                    case .text(let tb): return "text(\(String(tb.text.prefix(200))))"
                    case .toolResult(let tr): return "tool_result(\(tr.toolUseId): \(String(tr.content.prefix(150))))"
                    case .toolUse(let tu): return "tool_use(\(tu.name))"
                    case .image: return "image"
                    case .document: return "document"
                    }
                }
                let extra = blocks.count > 5 ? " + \(blocks.count - 5) more" : ""
                lastMessageSummary = "[\(last.role)] \(blockSummaries.joined(separator: ", "))\(extra)"
            }
        } else {
            lastMessageSummary = "(empty)"
        }

        LLMTranscriptLogger.logStreamingRequest(
            method: "ResumeRevisionAgent turn \(turn) REQUEST",
            modelId: modelId,
            backend: "Anthropic",
            prompt: "Messages: \(messageCount) | Last: \(lastMessageSummary)"
        )
    }

    /// Log the response after the stream completes (or is interrupted).
    private func logTurnResponse(
        turn: Int,
        messageCount: Int,
        toolNames: [String],
        result: RevisionAgentStreamResult,
        interrupted: Bool,
        durationMs: Int
    ) {
        let responseText = result.textBlocks.compactMap { block -> String? in
            if case .text(let tb) = block { return tb.text }
            return nil
        }.joined()

        let toolCallSummaries = result.toolCalls.map { call in
            "\(call.name)(\(String(call.arguments.prefix(200))))"
        }

        var statusSuffix = interrupted ? " [INTERRUPTED]" : ""
        if let stopReason = result.stopReason, stopReason != "end_turn", stopReason != "tool_use" {
            statusSuffix += " [stop_reason: \(stopReason)]"
        }
        LLMTranscriptLogger.logToolCall(
            method: "ResumeRevisionAgent turn \(turn) RESPONSE\(statusSuffix)",
            modelId: modelId,
            backend: "Anthropic",
            messageCount: messageCount,
            toolNames: toolNames,
            responseContent: responseText.isEmpty ? nil : responseText,
            responseToolCalls: toolCallSummaries,
            durationMs: durationMs
        )
    }
}
