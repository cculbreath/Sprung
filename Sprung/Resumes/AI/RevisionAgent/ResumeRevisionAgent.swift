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
    private var isCancelled = false

    // Continuations for human-in-the-loop tools
    private var proposalContinuation: CheckedContinuation<ProposalResponse, Never>?
    private var questionContinuation: CheckedContinuation<String, Never>?
    private var completionContinuation: CheckedContinuation<Bool, Never>?

    // Conversation state (Anthropic messages)
    private var conversationMessages: [AnthropicMessage] = []

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

                let stream = try await facade.anthropicMessagesStream(parameters: parameters)

                // Process stream
                var processor = RevisionStreamProcessor()
                var assistantTextBlocks: [AnthropicContentBlock] = []
                var toolCallBlocks: [AnthropicContentBlock] = []
                var pendingToolCalls: [RevisionStreamProcessor.ToolCallInfo] = []

                for try await event in stream {
                    guard !isCancelled else { break }

                    let domainEvents = processor.process(event)
                    for domainEvent in domainEvents {
                        switch domainEvent {
                        case .textDelta(let text):
                            appendOrUpdateAssistantMessage(text)

                        case .textFinalized(let fullText):
                            assistantTextBlocks.append(.text(AnthropicTextBlock(text: fullText)))

                        case .toolCallReady(let id, let name, let arguments):
                            pendingToolCalls.append(RevisionStreamProcessor.ToolCallInfo(
                                id: id, name: name, arguments: arguments
                            ))
                            // Parse arguments to [String: Any] for the message
                            let inputDict = parseToolArguments(arguments)
                            toolCallBlocks.append(.toolUse(AnthropicToolUseBlock(
                                id: id, name: name, input: inputDict
                            )))

                        case .messageComplete:
                            break
                        }
                    }
                }

                guard !isCancelled else {
                    status = .cancelled
                    try? workspaceService.deleteWorkspace()
                    return
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

                // If no tool calls, prompt to continue
                if pendingToolCalls.isEmpty {
                    conversationMessages.append(AnthropicMessage.user(
                        "Please continue with your analysis or call complete_revision if you're done."
                    ))
                    continue
                }

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
                var toolResults: [AnthropicContentBlock] = []

                for toolCall in pendingToolCalls {
                    currentAction = "Turn \(turnCount): \(toolDisplayName(toolCall.name))"
                    messages.append(RevisionMessage(
                        role: .toolActivity(toolCall.name),
                        content: toolDisplayName(toolCall.name)
                    ))

                    let resultString = await executeTool(
                        name: toolCall.name,
                        arguments: toolCall.arguments
                    )

                    toolResults.append(.toolResult(AnthropicToolResultBlock(
                        toolUseId: toolCall.id,
                        content: resultString
                    )))
                }

                // Append tool results as a single user message
                let toolResultMessage = AnthropicMessage(
                    role: "user",
                    content: .blocks(toolResults)
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

    func cancel() {
        isCancelled = true
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
            AnthropicSchemaConverter.anthropicTool(from: RenderResumeTool.self),
            AnthropicSchemaConverter.anthropicTool(from: ProposeChangesTool.self),
            AnthropicSchemaConverter.anthropicTool(from: AskUserTool.self),
            AnthropicSchemaConverter.anthropicTool(from: CompleteRevisionTool.self)
        ]
    }

    // MARK: - Tool Execution

    private func executeTool(name: String, arguments: String) async -> String {
        guard let workspacePath = workspaceService.workspacePath else {
            return "Error: Workspace not initialized"
        }

        do {
            let argsData = arguments.data(using: .utf8) ?? Data()

            switch name {
            case ReadFileTool.name:
                let params = try JSONDecoder().decode(ReadFileTool.Parameters.self, from: argsData)
                let result = try ReadFileTool.execute(parameters: params, repoRoot: workspacePath)
                return formatReadResult(result)

            case ListDirectoryTool.name:
                let params = try JSONDecoder().decode(ListDirectoryTool.Parameters.self, from: argsData)
                let result = try ListDirectoryTool.execute(parameters: params, repoRoot: workspacePath)
                return result.formattedTree

            case GlobSearchTool.name:
                let params = try JSONDecoder().decode(GlobSearchTool.Parameters.self, from: argsData)
                let result = try GlobSearchTool.execute(parameters: params, repoRoot: workspacePath)
                return formatGlobResult(result)

            case GrepSearchTool.name:
                let params = try JSONDecoder().decode(GrepSearchTool.Parameters.self, from: argsData)
                let result = try GrepSearchTool.execute(parameters: params, repoRoot: workspacePath)
                return formatGrepResult(result)

            case WriteJsonFileTool.name:
                let params = try JSONDecoder().decode(WriteJsonFileTool.Parameters.self, from: argsData)
                let result = try WriteJsonFileTool.execute(parameters: params, repoRoot: workspacePath)
                return "{\"success\": true, \"path\": \"\(result.path)\", \"itemCount\": \(result.itemCount)}"

            case RenderResumeTool.name:
                return await executeRenderResume()

            case ProposeChangesTool.name:
                let params = try JSONDecoder().decode(ProposeChangesTool.Parameters.self, from: argsData)
                return await executeProposal(params)

            case AskUserTool.name:
                let params = try JSONDecoder().decode(AskUserTool.Parameters.self, from: argsData)
                return await executeAskUser(params)

            default:
                return "Unknown tool: \(name)"
            }
        } catch {
            Logger.error("RevisionAgent tool error (\(name)): \(error.localizedDescription)", category: .ai)
            return "Error: \(error.localizedDescription)"
        }
    }

    // MARK: - Render Resume

    private func executeRenderResume() async -> String {
        guard let workspacePath = workspaceService.workspacePath else {
            return "Error: Workspace not initialized"
        }

        do {
            // Read revised treenodes and font sizes from workspace
            let revisedNodes = try workspaceService.importRevisedTreeNodes()
            let revisedFontSizes = try workspaceService.importRevisedFontSizes()

            // Build a temporary resume with revised nodes to render
            let tempResume = workspaceService.buildNewResume(
                from: resume,
                revisedNodes: revisedNodes,
                revisedFontSizes: revisedFontSizes,
                context: modelContext
            )

            // Render PDF
            let slug = resume.template?.slug ?? "default"
            let pdfData = try await pdfGenerator.generatePDF(for: tempResume, template: slug)

            // Write to workspace
            let pdfPath = workspacePath.appendingPathComponent("resume.pdf")
            try pdfData.write(to: pdfPath)

            // Count pages (rough estimate: PDF pages via CGPDFDocument)
            let pageCount = countPDFPages(pdfData)

            // Clean up temp resume from context
            modelContext.delete(tempResume)

            Logger.info("RevisionAgent: Rendered PDF (\(pdfData.count) bytes, \(pageCount) pages)", category: .ai)

            return "{\"success\": true, \"pageCount\": \(pageCount), \"pdfPath\": \"resume.pdf\"}"
        } catch {
            Logger.error("RevisionAgent: PDF render failed: \(error.localizedDescription)", category: .ai)
            return "{\"success\": false, \"error\": \"\(error.localizedDescription)\"}"
        }
    }

    private func countPDFPages(_ data: Data) -> Int {
        guard let provider = CGDataProvider(data: data as CFData),
              let document = CGPDFDocument(provider) else {
            return 0
        }
        return document.numberOfPages
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
            Logger.info("RevisionAgent: Built new resume from revised state", category: .ai)
            _ = newResume // Inserted into modelContext by buildNewResume
        }

        return accepted
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
        case WriteJsonFileTool.name: return "Writing JSON file"
        case RenderResumeTool.name: return "Rendering resume"
        case ProposeChangesTool.name: return "Proposing changes"
        case AskUserTool.name: return "Asking question"
        case CompleteRevisionTool.name: return "Completing revision"
        default: return name
        }
    }
}
