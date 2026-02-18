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
    private var isCancelled = false
    /// When true, the main loop's cancellation path builds a new resume from
    /// the workspace before deleting it — avoiding the race where a separate
    /// Task tried to read from an already-deleted workspace.
    private var shouldBuildResumeOnExit = false
    private var consecutiveNoToolTurns = 0
    private var activeStreamTask: Task<RevisionAgentStreamResult, Error>?
    /// Wall-clock deadline for the session. Reset whenever the user responds to
    /// a human-in-the-loop prompt (proposal, question, completion) so idle time
    /// waiting for user input doesn't count toward the timeout.
    private var timeoutDeadline: Date = .distantFuture

    // Continuations for human-in-the-loop tools
    private var proposalContinuation: CheckedContinuation<ProposalResponse, Never>?
    private var questionContinuation: CheckedContinuation<String, Never>?
    private var completionContinuation: CheckedContinuation<Bool, Never>?

    // Conversation state (Anthropic messages)
    private var conversationMessages: [AnthropicMessage] = []

    // Queued user messages (injected between turns)
    private var pendingUserMessages: [String] = []

    // Limits
    private let maxTurns = 50
    private let timeoutSeconds: TimeInterval = 1800 // 30 min

    // MARK: - Init

    private let titleSets: [TitleSetRecord]

    init(
        resume: Resume,
        llmFacade: LLMFacade,
        modelId: String,
        pdfGenerator: NativePDFGenerator,
        modelContext: ModelContext,
        titleSets: [TitleSetRecord] = []
    ) {
        self.resume = resume
        self.llmFacade = llmFacade
        self.modelId = modelId
        self.pdfGenerator = pdfGenerator
        self.modelContext = modelContext
        self.workspaceService = ResumeRevisionWorkspaceService()
        self.titleSets = titleSets
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
            throw RevisionAgentError.noLLMFacade
        }

        status = .running
        turnCount = 0
        messages = []
        conversationMessages = []
        isCancelled = false
        shouldBuildResumeOnExit = false

        do {
            // 1. Create workspace and export materials
            currentAction = "Setting up workspace..."
            let workspacePath = try workspaceService.createWorkspace()

            try await workspaceService.exportResumePDF(resume: resume, pdfGenerator: pdfGenerator)
            let manifest = try workspaceService.exportModifiableTreeNodes(from: resume)
            try workspaceService.exportJobDescription(jobDescription)
            try workspaceService.exportKnowledgeCards(knowledgeCards)
            try workspaceService.exportSkillBank(skills)
            try workspaceService.exportWritingSamples(coverRefs)
            try workspaceService.exportFontSizeNodes(resume.fontSizeNodes)
            try workspaceService.exportTitleSets(titleSets)

            let writingSamplesAvailable = coverRefs.contains { $0.type == .writingSample }

            // 2. Build system prompt
            let systemPrompt = ResumeRevisionAgentPrompts.systemPrompt(
                targetPageCount: manifest.targetPageCount,
                hasTitleSets: !titleSets.isEmpty
            )

            // 3. Build initial user message with PDF attachment
            let pdfPath = workspacePath.appendingPathComponent("resume.pdf")
            let pdfData = try Data(contentsOf: pdfPath)
            let pdfBase64 = pdfData.base64EncodedString()

            let userText = ResumeRevisionAgentPrompts.initialUserMessage(
                jobDescription: jobDescription,
                writingSamplesAvailable: writingSamplesAvailable
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
                guard !isCancelled else {
                    await handleExitCleanup()
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

                // Repair any orphaned tool_use blocks before calling the API.
                // When the user sends a chat message mid-stream, the stream is
                // cancelled and tool results may never be generated, leaving
                // tool_use IDs without matching tool_result blocks.
                AnthropicConversationRepairer.repairOrphanedToolUse(in: &conversationMessages)

                // Call Anthropic
                let parameters = AnthropicMessageParameter(
                    model: modelId,
                    messages: conversationMessages,
                    system: .text(systemPrompt),
                    maxTokens: 8192,
                    stream: true,
                    tools: tools,
                    toolChoice: .auto
                )

                let turnStart = ContinuousClock.now
                logTurnRequest(turn: turnCount, messageCount: conversationMessages.count)
                let stream = try await facade.anthropicMessagesStream(parameters: parameters)

                // Process stream in a child task so it can be cancelled by
                // sendUserMessage() or the per-turn timeout.
                let streamTask = Task { @MainActor [weak self] () -> RevisionAgentStreamResult in
                    guard let self else { return RevisionAgentStreamResult() }
                    var processor = RevisionStreamProcessor()
                    var result = RevisionAgentStreamResult()

                    for try await event in stream {
                        try Task.checkCancellation()

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

                            }
                        }
                    }

                    return result
                }
                activeStreamTask = streamTask

                // Per-turn timeout: cancel stream if stalled for 3 minutes
                let turnTimeoutTask = Task { @MainActor in
                    try await Task.sleep(for: .seconds(180))
                    streamTask.cancel()
                    Logger.warning("RevisionAgent: Turn \(turnCount) stream timed out", category: .ai)
                }

                var streamResult: RevisionAgentStreamResult
                var streamWasInterrupted = false

                do {
                    streamResult = try await streamTask.value
                } catch is CancellationError {
                    // Stream was interrupted by user message, timeout, or cancel
                    streamResult = RevisionAgentStreamResult()
                    streamWasInterrupted = !isCancelled
                    if streamWasInterrupted {
                        Logger.info("RevisionAgent: Stream interrupted on turn \(turnCount)", category: .ai)
                    }
                } catch {
                    // Stream threw a real error — treat as interrupted
                    streamResult = RevisionAgentStreamResult()
                    streamWasInterrupted = true
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

                guard !isCancelled else {
                    await handleExitCleanup()
                    return
                }

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

                // If no tool calls and we weren't interrupted,
                // nudge once then treat as done
                if pendingToolCalls.isEmpty {
                    consecutiveNoToolTurns += 1
                    if consecutiveNoToolTurns >= 2 {
                        Logger.info("RevisionAgent: LLM produced no tool calls for \(consecutiveNoToolTurns) turns, treating as complete", category: .ai)
                        messages.append(RevisionMessage(
                            role: .assistant,
                            content: "Revision session complete."
                        ))
                        status = .completed
                        try? workspaceService.deleteWorkspace()
                        return
                    }
                    conversationMessages.append(AnthropicMessage.user(
                        "If you have finished all changes, please call `complete_revision` with a summary. Otherwise, continue with your next action."
                    ))
                    continue
                }
                consecutiveNoToolTurns = 0

                // Check for completion tool
                if let completionCall = pendingToolCalls.first(where: { $0.name == CompleteRevisionTool.name }) {
                    let result = try await handleCompleteRevision(arguments: completionCall.arguments)

                    let toolResult = AnthropicMessage.toolResult(
                        toolUseId: completionCall.id,
                        content: result ? "{\"accepted\": true}" : "{\"accepted\": false}"
                    )
                    conversationMessages.append(toolResult)

                    if result {
                        status = .completed
                        try? workspaceService.deleteWorkspace()
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

                    if toolCall.name == WriteJsonFileTool.name {
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
            let built = await handleExitCleanup()
            if !built { throw error }
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
    /// we resume it. Otherwise we flag the main loop to build the resume from the
    /// workspace during its cancellation exit — this avoids the race where a
    /// separate Task tried to read from an already-deleted workspace.
    func acceptCurrentState() {
        // If waiting on completion tool, approve it
        if completionContinuation != nil {
            respondToCompletion(true)
            return
        }
        // Signal the main loop to build the resume from workspace before cleanup
        shouldBuildResumeOnExit = true
        isCancelled = true
        activeStreamTask?.cancel()
    }

    func cancel() {
        isCancelled = true
        activeStreamTask?.cancel()
        // Resume any waiting continuations
        proposalContinuation?.resume(returning: .rejected)
        proposalContinuation = nil
        currentProposal = nil
        questionContinuation?.resume(returning: "")
        questionContinuation = nil
        currentQuestion = nil
        completionContinuation?.resume(returning: false)
        completionContinuation = nil
        currentCompletionSummary = nil
    }

    // MARK: - Tool Building

    private func buildAnthropicTools() -> [AnthropicTool] {
        [
            AnthropicSchemaConverter.anthropicTool(from: ReadFileTool.self),
            AnthropicSchemaConverter.anthropicTool(from: ListDirectoryTool.self),
            AnthropicSchemaConverter.anthropicTool(from: GlobSearchTool.self),
            AnthropicSchemaConverter.anthropicTool(from: GrepSearchTool.self),
            AnthropicSchemaConverter.anthropicTool(from: WriteJsonFileTool.self),
            AnthropicSchemaConverter.anthropicTool(from: ProposeChangesTool.self),
            AnthropicSchemaConverter.anthropicTool(from: AskUserTool.self),
            AnthropicSchemaConverter.anthropicTool(from: CompleteRevisionTool.self)
        ]
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
            return ToolExecutionResult(text: "Error: Workspace not initialized")
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

        let response: ProposalResponse = await withCheckedContinuation { continuation in
            proposalContinuation = continuation
        }

        return response.toolResultJSON
    }

    private func executeAskUser(_ params: AskUserTool.Parameters) async -> String {
        currentQuestion = params.question
        messages.append(RevisionMessage(
            role: .assistant,
            content: params.question
        ))

        let answer: String = await withCheckedContinuation { continuation in
            questionContinuation = continuation
        }

        let payload = ["answer": answer]
        if let data = try? JSONSerialization.data(withJSONObject: payload),
           let json = String(data: data, encoding: .utf8) {
            return json
        }
        return "{\"answer\": \"\"}"
    }

    private func handleCompleteRevision(arguments: String) async throws -> Bool {
        guard let data = arguments.data(using: .utf8) else {
            throw RevisionAgentError.invalidToolCall("Could not parse arguments as UTF-8")
        }

        let params = try JSONDecoder().decode(CompleteRevisionTool.Parameters.self, from: data)

        currentCompletionSummary = params.summary
        messages.append(RevisionMessage(
            role: .assistant,
            content: "Revision complete: \(params.summary)"
        ))

        // Wait for user to accept or reject
        let accepted: Bool = await withCheckedContinuation { continuation in
            completionContinuation = continuation
        }
        currentCompletionSummary = nil

        if accepted {
            try await buildAndActivateResumeFromWorkspace()
        }

        return accepted
    }

    /// Handle cleanup when the agent loop exits early (cancellation or error).
    /// Builds the resume if `shouldBuildResumeOnExit` is set, then deletes workspace.
    /// Returns `true` if the resume was successfully built and activated.
    @discardableResult
    private func handleExitCleanup() async -> Bool {
        var built = false
        if shouldBuildResumeOnExit {
            do {
                try await buildAndActivateResumeFromWorkspace()
                status = .completed
                built = true
            } catch {
                Logger.error("RevisionAgent: Failed to build resume on exit: \(error)", category: .ai)
                status = .failed(error.localizedDescription)
            }
        } else if !isCancelled {
            status = .cancelled
        }
        try? workspaceService.deleteWorkspace()
        return built
    }

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
        let newResume = workspaceService.buildNewResume(
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

        let status = interrupted ? " [INTERRUPTED]" : ""
        LLMTranscriptLogger.logToolCall(
            method: "ResumeRevisionAgent turn \(turn) RESPONSE\(status)",
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
