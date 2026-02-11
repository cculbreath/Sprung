import AppKit
import CoreGraphics
import Foundation
import Observation
import SwiftOpenAI
import SwiftData

// MARK: - Agent Status

enum RevisionAgentStatus: Equatable {
    case idle
    case running
    case completed
    case failed(String)
    case cancelled
}

// MARK: - Agent Error

enum RevisionAgentError: LocalizedError {
    case noLLMFacade
    case modelNotConfigured
    case maxTurnsExceeded
    case agentDidNotComplete
    case invalidToolCall(String)
    case toolExecutionFailed(String)
    case timeout
    case workspaceError(String)
    case pdfRenderFailed(String)

    var errorDescription: String? {
        switch self {
        case .noLLMFacade:
            return "LLM service is not available"
        case .modelNotConfigured:
            return "Resume revision model is not configured in Settings"
        case .maxTurnsExceeded:
            return "Agent exceeded maximum number of turns without completing"
        case .agentDidNotComplete:
            return "Agent stopped without calling complete_revision"
        case .invalidToolCall(let msg):
            return "Invalid tool call: \(msg)"
        case .toolExecutionFailed(let msg):
            return "Tool execution failed: \(msg)"
        case .timeout:
            return "Agent timed out"
        case .workspaceError(let msg):
            return "Workspace error: \(msg)"
        case .pdfRenderFailed(let msg):
            return "PDF render failed: \(msg)"
        }
    }
}

// MARK: - Revision Message (for UI)

struct RevisionMessage: Identifiable {
    let id = UUID()
    let role: RevisionMessageRole
    let content: String
    let timestamp = Date()
}

enum RevisionMessageRole {
    case assistant
    case user
    case toolActivity(String) // tool name
}

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

    // State
    private(set) var status: RevisionAgentStatus = .idle
    private(set) var messages: [RevisionMessage] = []
    private(set) var currentProposal: ChangeProposal?
    private(set) var currentQuestion: String?
    private(set) var turnCount: Int = 0
    private(set) var currentAction: String = ""
    private(set) var latestPDFData: Data?
    private var isCancelled = false
    private var consecutiveNoToolTurns = 0
    private var activeStreamTask: Task<StreamResult, Error>?

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

    init(
        resume: Resume,
        llmFacade: LLMFacade,
        modelId: String,
        pdfGenerator: NativePDFGenerator,
        modelContext: ModelContext
    ) {
        self.resume = resume
        self.llmFacade = llmFacade
        self.modelId = modelId
        self.pdfGenerator = pdfGenerator
        self.modelContext = modelContext
        self.workspaceService = ResumeRevisionWorkspaceService()
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

            let writingSamplesAvailable = coverRefs.contains { $0.type == .writingSample }

            // 2. Build system prompt
            let systemPrompt = ResumeRevisionAgentPrompts.systemPrompt(
                targetPageCount: manifest.targetPageCount
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
            let startTime = Date()

            while turnCount < maxTurns {
                guard !isCancelled else {
                    status = .cancelled
                    try? workspaceService.deleteWorkspace()
                    return
                }

                if Date().timeIntervalSince(startTime) > timeoutSeconds {
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
                        // Merge into the last user message
                        let lastIndex = conversationMessages.count - 1
                        conversationMessages[lastIndex] = AnthropicMessage.user(combined)
                    } else {
                        conversationMessages.append(AnthropicMessage.user(combined))
                    }
                }

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
                let streamTask = Task { @MainActor [weak self] () -> StreamResult in
                    guard let self else { return StreamResult() }
                    var processor = RevisionStreamProcessor()
                    var result = StreamResult()

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

                            case .messageComplete:
                                break
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

                var streamResult: StreamResult
                var streamWasInterrupted = false

                do {
                    streamResult = try await streamTask.value
                } catch is CancellationError {
                    // Stream was interrupted by user message, timeout, or cancel
                    streamResult = StreamResult()
                    streamWasInterrupted = !isCancelled
                    if streamWasInterrupted {
                        Logger.info("RevisionAgent: Stream interrupted on turn \(turnCount)", category: .ai)
                    }
                } catch {
                    // Stream threw a real error — treat as interrupted
                    streamResult = StreamResult()
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
                    status = .cancelled
                    try? workspaceService.deleteWorkspace()
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

                // Execute tool calls and collect results
                var toolResultBlocks: [AnthropicContentBlock] = []

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
                        content: result.text
                    )))
                    // Append any rendered page images after the tool result
                    toolResultBlocks.append(contentsOf: result.imageBlocks)
                }

                // Append tool results (and any attached images) as a single user message
                let toolResultMessage = AnthropicMessage(
                    role: "user",
                    content: .blocks(toolResultBlocks)
                )
                conversationMessages.append(toolResultMessage)
            }

            // Max turns exceeded
            throw RevisionAgentError.maxTurnsExceeded

        } catch {
            if !isCancelled {
                status = .failed(error.localizedDescription)
            }
            try? workspaceService.deleteWorkspace()
            throw error
        }
    }

    // MARK: - User Response Methods

    func respondToProposal(_ response: ProposalResponse) {
        currentProposal = nil
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
        proposalContinuation?.resume(returning: response)
        proposalContinuation = nil
    }

    func respondToQuestion(_ answer: String) {
        currentQuestion = nil
        messages.append(RevisionMessage(role: .user, content: answer))
        questionContinuation?.resume(returning: answer)
        questionContinuation = nil
    }

    func respondToCompletion(_ accepted: Bool) {
        messages.append(RevisionMessage(
            role: .user,
            content: accepted ? "Revision accepted" : "Revision rejected"
        ))
        completionContinuation?.resume(returning: accepted)
        completionContinuation = nil
    }

    /// Queue a free-form user message to be injected into the conversation between turns.
    /// Also cancels the active stream so the message gets delivered promptly.
    func sendUserMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        pendingUserMessages.append(trimmed)
        messages.append(RevisionMessage(role: .user, content: trimmed))
        // Reset the no-tool counter since the user is actively engaging
        consecutiveNoToolTurns = 0
        // Cancel the active stream so the agent loop advances to the next turn
        activeStreamTask?.cancel()
    }

    /// Accept the current workspace state and create a new resume from it.
    func acceptCurrentState() {
        // If waiting on completion tool, approve it
        if completionContinuation != nil {
            respondToCompletion(true)
            return
        }
        // Otherwise, directly build the resume from current workspace state
        Task {
            do {
                let revisedNodes = try workspaceService.importRevisedTreeNodes()
                let revisedFontSizes = try workspaceService.importRevisedFontSizes()
                let newResume = workspaceService.buildNewResume(
                    from: resume,
                    revisedNodes: revisedNodes,
                    revisedFontSizes: revisedFontSizes,
                    context: modelContext
                )
                await activateNewResume(newResume)
                status = .completed
                try? workspaceService.deleteWorkspace()
            } catch {
                Logger.error("RevisionAgent: Failed to build resume from current state: \(error)", category: .ai)
                status = .failed(error.localizedDescription)
            }
        }
        isCancelled = true
    }

    func cancel() {
        isCancelled = true
        activeStreamTask?.cancel()
        // Resume any waiting continuations
        proposalContinuation?.resume(returning: .rejected)
        proposalContinuation = nil
        questionContinuation?.resume(returning: "")
        questionContinuation = nil
        completionContinuation?.resume(returning: false)
        completionContinuation = nil
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

    // MARK: - Stream Result

    /// Result from executing a tool, with optional image attachments.
    private struct ToolExecutionResult {
        let text: String
        var imageBlocks: [AnthropicContentBlock] = []
    }

    /// Accumulated output from a single stream processing turn.
    private struct StreamResult {
        var textBlocks: [AnthropicContentBlock] = []
        var toolCallBlocks: [AnthropicContentBlock] = []
        var toolCalls: [RevisionStreamProcessor.ToolCallInfo] = []
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
                // Auto-render after every JSON write so the PDF preview stays current
                let renderInfo = await autoRenderResume()
                let text = "{\"success\": true, \"path\": \"\(result.path)\", \"itemCount\": \(result.itemCount), \"pageCount\": \(renderInfo.pageCount), \"renderSuccess\": \(renderInfo.success)}"
                // Attach rendered PDF page images so the agent can visually inspect the result
                let imageBlocks = renderInfo.pdfData.map { renderPDFPageImages($0) } ?? []
                return ToolExecutionResult(text: text, imageBlocks: imageBlocks)

            case ProposeChangesTool.name:
                let params = try JSONDecoder().decode(ProposeChangesTool.Parameters.self, from: argsData)
                return ToolExecutionResult(text: await executeProposal(params))

            case AskUserTool.name:
                let params = try JSONDecoder().decode(AskUserTool.Parameters.self, from: argsData)
                return ToolExecutionResult(text: await executeAskUser(params))

            default:
                return ToolExecutionResult(text: "Unknown tool: \(name)")
            }
        } catch {
            Logger.error("RevisionAgent tool error (\(name)): \(error.localizedDescription)", category: .ai)
            return ToolExecutionResult(text: "Error: \(error.localizedDescription)")
        }
    }

    // MARK: - Auto-Render

    private struct RenderInfo {
        let success: Bool
        let pageCount: Int
        let pdfData: Data?
    }

    /// Re-render the resume PDF from current workspace state and publish to the preview pane.
    /// Called automatically after every `write_json_file`.
    private func autoRenderResume() async -> RenderInfo {
        guard let workspacePath = workspaceService.workspacePath else {
            return RenderInfo(success: false, pageCount: 0, pdfData: nil)
        }

        do {
            let revisedNodes = try workspaceService.importRevisedTreeNodes()
            let revisedFontSizes = try workspaceService.importRevisedFontSizes()

            let tempResume = workspaceService.buildNewResume(
                from: resume,
                revisedNodes: revisedNodes,
                revisedFontSizes: revisedFontSizes,
                context: modelContext
            )

            let slug = resume.template?.slug ?? "default"
            let pdfData = try await pdfGenerator.generatePDF(for: tempResume, template: slug)

            // Write to workspace (so read_file can access it too)
            let pdfPath = workspacePath.appendingPathComponent("resume.pdf")
            try pdfData.write(to: pdfPath)

            let pageCount = countPDFPages(pdfData)

            // Publish to preview pane
            latestPDFData = pdfData

            // Clean up temp resume
            modelContext.delete(tempResume)

            Logger.info("RevisionAgent: Auto-rendered PDF (\(pdfData.count) bytes, \(pageCount) pages)", category: .ai)
            return RenderInfo(success: true, pageCount: pageCount, pdfData: pdfData)
        } catch {
            Logger.error("RevisionAgent: Auto-render failed: \(error.localizedDescription)", category: .ai)
            return RenderInfo(success: false, pageCount: 0, pdfData: nil)
        }
    }

    private func countPDFPages(_ data: Data) -> Int {
        guard let provider = CGDataProvider(data: data as CFData),
              let document = CGPDFDocument(provider) else {
            return 0
        }
        return document.numberOfPages
    }

    /// Render each page of a PDF to a JPEG image and return as Anthropic image content blocks.
    private func renderPDFPageImages(_ pdfData: Data) -> [AnthropicContentBlock] {
        guard let provider = CGDataProvider(data: pdfData as CFData),
              let document = CGPDFDocument(provider) else {
            return []
        }

        var blocks: [AnthropicContentBlock] = []
        let scale: CGFloat = 2.0 // 2x for readable text

        for pageIndex in 1...document.numberOfPages {
            guard let page = document.page(at: pageIndex) else { continue }
            let mediaBox = page.getBoxRect(.mediaBox)
            let width = Int(mediaBox.width * scale)
            let height = Int(mediaBox.height * scale)

            guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(
                      data: nil,
                      width: width,
                      height: height,
                      bitsPerComponent: 8,
                      bytesPerRow: 0,
                      space: colorSpace,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else { continue }

            // White background
            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))

            // Scale and draw
            context.scaleBy(x: scale, y: scale)
            context.drawPDFPage(page)

            guard let cgImage = context.makeImage() else { continue }

            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
            guard let tiffData = nsImage.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiffData),
                  let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else {
                continue
            }

            let base64 = jpegData.base64EncodedString()
            let imageSource = AnthropicImageSource(mediaType: "image/jpeg", data: base64)
            let imageBlock = AnthropicImageBlock(source: imageSource)
            blocks.append(.image(imageBlock))
        }

        Logger.info("RevisionAgent: Rendered \(blocks.count) PDF page image(s) for agent preview", category: .ai)
        return blocks
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

        return "{\"answer\": \"\(answer.replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n"))\"}"
    }

    private func handleCompleteRevision(arguments: String) async throws -> Bool {
        guard let data = arguments.data(using: .utf8) else {
            throw RevisionAgentError.invalidToolCall("Could not parse arguments as UTF-8")
        }

        let params = try JSONDecoder().decode(CompleteRevisionTool.Parameters.self, from: data)

        messages.append(RevisionMessage(
            role: .assistant,
            content: "Revision complete: \(params.summary)"
        ))

        // Wait for user to accept or reject
        let accepted: Bool = await withCheckedContinuation { continuation in
            completionContinuation = continuation
        }

        if accepted {
            // Build final resume from workspace state
            let revisedNodes = try workspaceService.importRevisedTreeNodes()
            let revisedFontSizes = try workspaceService.importRevisedFontSizes()
            let newResume = workspaceService.buildNewResume(
                from: resume,
                revisedNodes: revisedNodes,
                revisedFontSizes: revisedFontSizes,
                context: modelContext
            )
            await activateNewResume(newResume)
        }

        return accepted
    }

    /// Generate PDF for the new resume and switch the editor to it.
    private func activateNewResume(_ newResume: Resume) async {
        let slug = resume.template?.slug ?? "default"
        do {
            let pdfData = try await pdfGenerator.generatePDF(for: newResume, template: slug)
            newResume.pdfData = pdfData
        } catch {
            Logger.error("RevisionAgent: Failed to generate PDF for new resume: \(error)", category: .ai)
        }
        resume.jobApp?.selectedRes = newResume
        Logger.info("RevisionAgent: Activated new resume in editor", category: .ai)
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
        result: StreamResult,
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
