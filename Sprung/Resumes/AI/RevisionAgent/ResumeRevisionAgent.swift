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
            if let jobApp = resume.jobApp {
                try workspaceService.exportJobMetadata(for: jobApp)
                try workspaceService.exportJobRequirements(jobApp.extractedRequirements)
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
                avoidPhrases: avoidPhrases
            )
            let systemContent: AnthropicSystemContent = .blocks([
                AnthropicSystemBlock(text: systemPrompt, cacheControl: Self.oneHourCacheControl)
            ])

            // 3. Build initial user message with PDF attachment
            let pdfPath = workspacePath.appendingPathComponent("resume.pdf")
            let pdfData = try Data(contentsOf: pdfPath)
            let pdfBase64 = pdfData.base64EncodedString()

            let userText = ResumeRevisionAgentPrompts.initialUserMessage(
                jobDescription: jobDescription,
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

            // 5. Agent loop
            timeoutDeadline = Date().addingTimeInterval(timeoutSeconds)

            while turnCount < maxTurns {
                if shouldExitLoop() {
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
                    messages: applyCacheBreakpoints(to: conversationMessages),
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

                if shouldExitLoop() {
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
                        isFatal: Self.isFatalStreamErrorEvent(streamErrorMessage)
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

                    let accepted = await handleCompleteRevision(arguments: completionCall.arguments)
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
                    // conversation stays well-formed.
                    if shouldExitLoop() {
                        toolResultBlocks.append(.toolResult(AnthropicToolResultBlock(
                            toolUseId: toolCall.id,
                            content: "{\"error\": \"Session ended before this tool ran\"}",
                            isError: true
                        )))
                        continue
                    }

                    // A tool call whose input JSON was truncated at the output
                    // limit cannot be executed — tell the model to split it.
                    if streamResult.stopReason == "max_tokens", !Self.isCompleteJSONObject(toolCall.arguments) {
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
            content: accepted ? "Revision accepted" : "Revision rejected"
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
    func cancelActiveStream() {
        activeStreamTask?.cancel()
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
        let classification = Self.classifyStreamFailure(error)
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

    /// Fatal = configuration/auth/request problems that retrying cannot heal.
    /// Transient = rate limits, overload, server errors, network drops.
    private static func classifyStreamFailure(_ error: Error) -> (isFatal: Bool, message: String) {
        if let apiError = error as? APIError {
            if case .responseUnsuccessful(_, let statusCode, _) = apiError {
                let transientCodes: Set<Int> = [408, 429, 500, 502, 503, 504, 529]
                return (isFatal: !transientCodes.contains(statusCode), message: apiError.displayDescription)
            }
            return (isFatal: false, message: apiError.displayDescription)
        }
        if let llmError = error as? LLMError {
            switch llmError {
            case .clientError, .unauthorized, .invalidModelId:
                return (isFatal: true, message: llmError.localizedDescription)
            case .decodingFailed, .unexpectedResponseFormat, .rateLimited, .timeout, .insufficientCredits:
                return (isFatal: false, message: llmError.localizedDescription)
            }
        }
        return (isFatal: false, message: error.localizedDescription)
    }

    /// Classify an in-stream `error` event by its Anthropic error type.
    private static func isFatalStreamErrorEvent(_ message: String) -> Bool {
        let fatalTypes = [
            "authentication_error",
            "permission_error",
            "invalid_request_error",
            "not_found_error",
            "request_too_large"
        ]
        return fatalTypes.contains { message.contains($0) }
    }

    /// True when `raw` parses as a complete JSON value — used to detect tool
    /// inputs truncated by a max_tokens stop.
    private static func isCompleteJSONObject(_ raw: String) -> Bool {
        guard let data = raw.data(using: .utf8), !data.isEmpty else { return false }
        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }

    // MARK: - Tool Building

    /// Fixed, deterministic tool order (prompt-cache invariant: tools render
    /// at position 0; any reorder invalidates the entire cache). The cache
    /// breakpoint on the LAST tool caches the whole tool block.
    private func buildAnthropicTools() -> [AnthropicTool] {
        [
            AnthropicSchemaConverter.anthropicTool(from: ReadFileTool.self),
            AnthropicSchemaConverter.anthropicTool(from: ListDirectoryTool.self),
            AnthropicSchemaConverter.anthropicTool(from: GlobSearchTool.self),
            AnthropicSchemaConverter.anthropicTool(from: GrepSearchTool.self),
            AnthropicSchemaConverter.anthropicTool(from: WriteJsonFileTool.self),
            AnthropicSchemaConverter.anthropicTool(from: ProposeChangesTool.self),
            AnthropicSchemaConverter.anthropicTool(from: AskUserTool.self),
            AnthropicSchemaConverter.anthropicTool(from: CompleteRevisionTool.self, cacheControl: Self.oneHourCacheControl)
        ]
    }

    // MARK: - Prompt-Cache Breakpoints

    /// Position of a content block in the assembled message array.
    private struct BlockPosition: Equatable {
        let messageIndex: Int
        let blockIndex: Int
    }

    /// Apply the message-tier cache breakpoints to a per-request copy of the
    /// conversation. Applied at request-build time ONLY — the stored history
    /// is never mutated (byte-stability invariant), so the breakpoints move
    /// naturally each turn and turn N+1 reads the prefix turn N wrote.
    ///
    /// Breakpoint budget (HARD LIMIT 4 per request, all 1h TTL):
    /// 1. Last tool (buildAnthropicTools) — caches the whole tool block.
    /// 2. System block — caches tools + system.
    /// 3. Moving tail: last markable block of the final message — incremental
    ///    conversation caching. The initial PDF document block sits at the
    ///    front of the conversation, inside this cached prefix from turn 1.
    /// 4. Lookback anchor (conditional): Anthropic matches cache prefixes by
    ///    walking at most ~20 content blocks back from a breakpoint, and a
    ///    write_json_file turn appends several tool_result + page-image
    ///    blocks at once. When the array exceeds 20 blocks, plant a boundary
    ///    on the last markable block of the latest message that ends at
    ///    least 20 blocks before the end, so the next turn's tail breakpoint
    ///    always finds a prior cache entry inside the lookback window.
    private func applyCacheBreakpoints(to messages: [AnthropicMessage]) -> [AnthropicMessage] {
        guard !messages.isEmpty else { return messages }

        // Flatten block geometry (string content counts as one text block).
        let blocksByMessage: [[AnthropicContentBlock]] = messages.map { Self.contentBlocks(of: $0) }
        var flatStartIndex: [Int] = []
        var totalBlocks = 0
        for blocks in blocksByMessage {
            flatStartIndex.append(totalBlocks)
            totalBlocks += blocks.count
        }

        func isMarkable(_ block: AnthropicContentBlock) -> Bool {
            if case .toolUse = block { return false }
            return true
        }

        func lastMarkableBlock(inMessage messageIndex: Int) -> BlockPosition? {
            for blockIndex in blocksByMessage[messageIndex].indices.reversed()
            where isMarkable(blocksByMessage[messageIndex][blockIndex]) {
                return BlockPosition(messageIndex: messageIndex, blockIndex: blockIndex)
            }
            return nil
        }

        // Moving tail breakpoint — last markable block of the final message
        // (walking back if the final message has none: tool_use blocks cannot
        // carry cache_control).
        var tail: BlockPosition?
        for messageIndex in blocksByMessage.indices.reversed() {
            if let position = lastMarkableBlock(inMessage: messageIndex) {
                tail = position
                break
            }
        }

        // Lookback anchor — only when a breakpoint could fall out of range of
        // the previous turn's prefix.
        var lookback: BlockPosition?
        if totalBlocks > 20 {
            for messageIndex in blocksByMessage.indices.reversed() {
                let lastFlatIndex = flatStartIndex[messageIndex] + blocksByMessage[messageIndex].count - 1
                guard totalBlocks - 1 - lastFlatIndex >= 20 else { continue }
                if let position = lastMarkableBlock(inMessage: messageIndex) {
                    lookback = position
                    break
                }
            }
        }

        // Tools (1) + system (1) leave a budget of exactly 2 message-tier
        // breakpoints — tail and lookback. Collapse duplicates.
        var kept: [BlockPosition] = []
        for candidate in [tail, lookback] {
            guard let candidate, !kept.contains(candidate) else { continue }
            kept.append(candidate)
        }
        guard !kept.isEmpty else { return messages }

        // Apply marks, grouping by message so multiple marks in one message stack.
        var marksByMessage: [Int: [Int]] = [:]
        for position in kept {
            marksByMessage[position.messageIndex, default: []].append(position.blockIndex)
        }

        var result = messages
        for (messageIndex, blockIndexes) in marksByMessage {
            var blocks = blocksByMessage[messageIndex]
            for blockIndex in blockIndexes {
                guard let marked = Self.addingCacheControl(to: blocks[blockIndex]) else { continue }
                blocks[blockIndex] = marked
            }
            result[messageIndex] = AnthropicMessage(role: messages[messageIndex].role, content: .blocks(blocks))
        }

        return result
    }

    private static func contentBlocks(of message: AnthropicMessage) -> [AnthropicContentBlock] {
        switch message.content {
        case .text(let text):
            return [.text(AnthropicTextBlock(text: text))]
        case .blocks(let blocks):
            return blocks
        }
    }

    /// tool_use blocks cannot carry cache_control; everything else can.
    private static func addingCacheControl(to block: AnthropicContentBlock) -> AnthropicContentBlock? {
        switch block {
        case .text(let textBlock):
            return .text(AnthropicTextBlock(text: textBlock.text, cacheControl: oneHourCacheControl))
        case .toolResult(let resultBlock):
            return .toolResult(AnthropicToolResultBlock(
                toolUseId: resultBlock.toolUseId,
                content: resultBlock.content,
                isError: resultBlock.isError ?? false,
                cacheControl: oneHourCacheControl
            ))
        case .image(let imageBlock):
            return .image(AnthropicImageBlock(source: imageBlock.source, cacheControl: oneHourCacheControl))
        case .document(let documentBlock):
            return .document(AnthropicDocumentBlock(source: documentBlock.source, cacheControl: oneHourCacheControl))
        case .toolUse:
            return nil
        }
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
                    content: "{\"error\": \"Session ended before this tool ran\"}",
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
        let proposal = ChangeProposal(
            summary: params.summary,
            changes: params.changes
        )

        currentProposal = proposal
        messages.append(RevisionMessage(
            role: .assistant,
            content: "Proposed changes: \(params.summary)"
        ))

        let response = await awaitProposalDecision()
        currentProposal = nil
        return response.toolResultJSON
    }

    private func executeAskUser(_ params: AskUserTool.Parameters) async -> String {
        currentQuestion = params.question
        messages.append(RevisionMessage(
            role: .assistant,
            content: params.question
        ))

        let answer = await awaitQuestionAnswer()
        currentQuestion = nil

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

        return await presentCompletionCard(summary: summary)
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

    private func presentCompletionCard(summary: String) async -> Bool {
        if shouldExitLoop() { return false }
        currentCompletionSummary = summary
        let accepted = await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                if self.shouldExitLoop() {
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
        let slug = resume.template?.slug ?? "default"
        do {
            let pdfData = try await pdfGenerator.generatePDF(for: newResume, template: slug)
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
