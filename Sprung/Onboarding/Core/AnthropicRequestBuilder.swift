//
//  AnthropicRequestBuilder.swift
//  Sprung
//
//  Builds AnthropicMessageParameter requests for the Onboarding Interview's Anthropic Messages API calls.
//  Delegates to specialized components for history building, tool conversion, and working memory.
//

import Foundation
import SwiftOpenAI
import SwiftyJSON

/// Builds AnthropicMessageParameter requests for the Onboarding Interview's Anthropic Messages API calls.
/// Extracted to separate request construction from stream handling.
struct AnthropicRequestBuilder {
    private let baseSystemPrompt: String
    private let stateCoordinator: StateCoordinator
    private let historyBuilder: AnthropicHistoryBuilder
    private let toolConverter: AnthropicToolConverter
    private let workingMemoryBuilder: WorkingMemoryBuilder
    private let todoStore: InterviewTodoStore

    init(
        baseSystemPrompt: String,
        toolRegistry: ToolRegistry,
        contextAssembler: ConversationContextAssembler,
        stateCoordinator: StateCoordinator,
        todoStore: InterviewTodoStore
    ) {
        self.baseSystemPrompt = baseSystemPrompt
        self.stateCoordinator = stateCoordinator
        self.historyBuilder = AnthropicHistoryBuilder(contextAssembler: contextAssembler)
        self.toolConverter = AnthropicToolConverter(toolRegistry: toolRegistry, stateCoordinator: stateCoordinator)
        self.workingMemoryBuilder = WorkingMemoryBuilder(stateCoordinator: stateCoordinator)
        self.todoStore = todoStore
    }

    // MARK: - User Message Request

    func buildUserMessageRequest(
        text: String,
        isSystemGenerated: Bool,
        bundledCoordinatorMessages: [JSON] = [],
        imageBase64: String? = nil,
        imageContentType: String? = nil
    ) async throws -> AnthropicMessageParameter {
        var messages: [AnthropicMessage] = []

        // Build conversation history (Anthropic uses explicit messages, no PRI)
        let history = await historyBuilder.buildAnthropicHistory()
        if !history.isEmpty {
            messages.append(contentsOf: history)
            Logger.info("📋 Including \(history.count) messages from transcript", category: .ai)
        }

        // Build full message text with XML tags (Anthropic-native pattern)
        // Order: <interview_context> + <coordinator> + <chatbox> or raw text
        var fullMessageParts: [String] = []

        // 1. Interview context (replaces working memory in system prompt)
        if let interviewContext = await workingMemoryBuilder.buildInterviewContext() {
            fullMessageParts.append(interviewContext)
        }

        // 2. Coordinator instructions (app-generated guidance for the model)
        for devPayload in bundledCoordinatorMessages {
            let devText = devPayload["text"].stringValue
            if !devText.isEmpty {
                fullMessageParts.append("<coordinator>\(devText)</coordinator>")
            }
        }

        // 3. The actual message text (already tagged with <chatbox> if from user)
        fullMessageParts.append(text)

        let fullMessageText = fullMessageParts.joined(separator: "\n\n")

        // Build user message - with image if provided
        // CRITICAL: If history ends with a user message (e.g., synthetic tool_result from race condition),
        // we must merge the new content with it to maintain Anthropic's role alternation requirement.
        let newUserBlocks: [AnthropicContentBlock]
        if let fileData = imageBase64 {
            let mimeType = imageContentType ?? "image/jpeg"

            // Use document block for PDFs, image block for images
            if mimeType == "application/pdf" {
                let docSource = AnthropicDocumentSource(mediaType: mimeType, data: fileData)
                newUserBlocks = [
                    .text(AnthropicTextBlock(text: fullMessageText)),
                    .document(AnthropicDocumentBlock(source: docSource))
                ]
                Logger.info("📄 Including PDF document in user message", category: .ai)
            } else {
                let imageSource = AnthropicImageSource(mediaType: mimeType, data: fileData)
                newUserBlocks = [
                    .text(AnthropicTextBlock(text: fullMessageText)),
                    .image(AnthropicImageBlock(source: imageSource))
                ]
                Logger.info("🖼️ Including image attachment in user message (\(mimeType))", category: .ai)
            }
        } else {
            newUserBlocks = [.text(AnthropicTextBlock(text: fullMessageText))]
        }

        // Check if we need to merge with trailing user message from history
        if let lastIndex = messages.indices.last,
           messages[lastIndex].role == "user" {
            // Merge new content with existing user message
            let existingBlocks = historyBuilder.extractContentBlocks(messages[lastIndex])
            let mergedBlocks = existingBlocks + newUserBlocks
            messages[lastIndex] = AnthropicMessage(role: "user", content: .blocks(mergedBlocks))
            Logger.info("📝 Merged new user content with trailing user message (race condition handling)", category: .ai)
        } else {
            // Append as new user message
            messages.append(AnthropicMessage(role: "user", content: .blocks(newUserBlocks)))
        }

        // Determine tool choice - prefer auto, only use .any as last resort
        let toolChoice: AnthropicToolChoice
        if !isSystemGenerated {
            let hasStreamed = await stateCoordinator.getHasStreamedFirstResponse()
            if !hasStreamed {
                Logger.info("🚫 Disabling tools for first user request to ensure greeting", category: .ai)
                toolChoice = .none
            } else {
                toolChoice = .auto
            }
        } else {
            toolChoice = .auto
        }

        // Get tools and convert to Anthropic format
        let tools = await toolConverter.getAnthropicTools()

        // Build system prompt (base personality only - interview context now in user messages)
        let systemPrompt = await buildSystemPrompt()

        let modelId = try await stateCoordinator.getAnthropicModelId()

        let parameters = AnthropicMessageParameter(
            model: modelId,
            messages: messages,
            system: systemPrompt.isEmpty ? nil : .text(systemPrompt),
            maxTokens: 4096,
            stream: true,
            tools: tools.isEmpty ? nil : tools,
            toolChoice: toolChoice == .none && tools.isEmpty ? nil : toolChoice
        )

        Logger.info(
            "📝 Built Anthropic request: messages=\(messages.count), tools=\(tools.count)",
            category: .ai
        )

        return parameters
    }

    // MARK: - Coordinator Message Request

    /// Build a request with coordinator instructions.
    /// Per Anthropic best practices, coordinator instructions are sent as user messages
    /// with <coordinator> XML tags, not stuffed into system prompt.
    func buildCoordinatorMessageRequest(
        text: String
    ) async throws -> AnthropicMessageParameter {
        var messages: [AnthropicMessage] = []

        // Include conversation history
        let history = await historyBuilder.buildAnthropicHistory()
        messages.append(contentsOf: history)

        // Build message with interview context + coordinator instruction
        var messageParts: [String] = []

        // 1. Interview context
        if let interviewContext = await workingMemoryBuilder.buildInterviewContext() {
            messageParts.append(interviewContext)
        }

        // 2. Coordinator instruction (app-generated guidance)
        messageParts.append("<coordinator>\(text)</coordinator>")

        let fullMessageText = messageParts.joined(separator: "\n\n")

        // Add as user message (or merge with existing trailing user message)
        if let lastIndex = messages.indices.last,
           messages[lastIndex].role == "user" {
            let existingBlocks = historyBuilder.extractContentBlocks(messages[lastIndex])
            let mergedBlocks = existingBlocks + [.text(AnthropicTextBlock(text: fullMessageText))]
            messages[lastIndex] = AnthropicMessage(role: "user", content: .blocks(mergedBlocks))
            Logger.info("📝 Merged coordinator message with trailing user message", category: .ai)
        } else {
            messages.append(.user(fullMessageText))
        }

        let tools = await toolConverter.getAnthropicTools()
        let systemPrompt = await buildSystemPrompt()
        let modelId = try await stateCoordinator.getAnthropicModelId()

        let parameters = AnthropicMessageParameter(
            model: modelId,
            messages: messages,
            system: systemPrompt.isEmpty ? nil : .text(systemPrompt),
            maxTokens: 4096,
            stream: true,
            tools: tools.isEmpty ? nil : tools,
            toolChoice: tools.isEmpty ? nil : .auto
        )

        Logger.info(
            "📝 Built Anthropic coordinator message request: messages=\(messages.count)",
            category: .ai
        )

        return parameters
    }

    // MARK: - Tool Response Request

    /// Build a request after a tool has completed.
    ///
    /// The tool result is already stored in ConversationLog (via setToolResult).
    /// This method builds history from ConversationLog (which includes the tool_result),
    /// then appends computed context (interview state, coordinator instructions).
    ///
    /// - Parameters:
    ///   - callId: The tool call ID (for logging)
    ///   - instruction: Optional instruction text to include after the tool_result.
    ///     This provides immediate guidance to Claude for the next action.
    ///   - pdfBase64: Optional base64-encoded PDF to include as a document block
    ///   - pdfFilename: Optional filename for the PDF attachment
    func buildToolResponseRequest(
        callId: String,
        instruction: String? = nil,
        pdfBase64: String? = nil,
        pdfFilename: String? = nil
    ) async throws -> AnthropicMessageParameter {
        // Build conversation history - tool_result is already in ConversationLog
        var messages = await historyBuilder.buildAnthropicHistory()

        // Build computed context to append: interview_context + optional coordinator instruction
        var textParts: [String] = []

        // Include interview context so Claude always has current state
        if let interviewContext = await workingMemoryBuilder.buildInterviewContext() {
            textParts.append(interviewContext)
        }

        // Add coordinator instruction if provided
        if let instruction = instruction {
            textParts.append("<coordinator>\(instruction)</coordinator>")
            Logger.info("📋 Including coordinator instruction with tool result", category: .ai)
        }

        // Build additional content blocks (PDF, computed context)
        var additionalBlocks: [AnthropicContentBlock] = []

        // If PDF data is provided, include it as a document block
        if let pdfData = pdfBase64 {
            let docSource = AnthropicDocumentSource(mediaType: "application/pdf", data: pdfData)
            additionalBlocks.append(.document(AnthropicDocumentBlock(source: docSource)))
            Logger.info("📄 Including PDF document block with tool result: \(pdfFilename ?? "unknown")", category: .ai)
        }

        // Append computed context text if we have any
        if !textParts.isEmpty {
            additionalBlocks.append(.text(AnthropicTextBlock(text: textParts.joined(separator: "\n\n"))))
        }

        // Append additional content to the last user message (which contains the tool_result from history)
        if !additionalBlocks.isEmpty {
            if let lastIndex = messages.indices.last, messages[lastIndex].role == "user" {
                let existingBlocks = historyBuilder.extractContentBlocks(messages[lastIndex])
                let mergedBlocks = existingBlocks + additionalBlocks
                messages[lastIndex] = AnthropicMessage(role: "user", content: .blocks(mergedBlocks))
                Logger.info("📝 Appended computed context to tool result message", category: .ai)
            } else {
                // Shouldn't happen - history should end with user message containing tool_result
                Logger.warning("⚠️ History doesn't end with user message - appending context as new message", category: .ai)
                messages.append(AnthropicMessage(role: "user", content: .blocks(additionalBlocks)))
            }
        }

        let tools = await toolConverter.getAnthropicTools()
        let systemPrompt = await buildSystemPrompt()
        let modelId = try await stateCoordinator.getAnthropicModelId()

        let parameters = AnthropicMessageParameter(
            model: modelId,
            messages: messages,
            system: systemPrompt.isEmpty ? nil : .text(systemPrompt),
            maxTokens: 4096,
            stream: true,
            tools: tools.isEmpty ? nil : tools,
            toolChoice: tools.isEmpty ? nil : .auto
        )

        // Log diagnostic info about tool blocks
        let (toolUseCount, toolResultCount) = countToolBlocks(in: messages)
        Logger.info(
            "📝 Built Anthropic tool response request: callId=\(callId), " +
            "tool_use=\(toolUseCount), tool_result=\(toolResultCount)",
            category: .ai
        )

        // Log any mismatches
        if toolUseCount != toolResultCount {
            Logger.warning(
                "⚠️ Tool block mismatch: \(toolUseCount) tool_use vs \(toolResultCount) tool_result. " +
                "Anthropic requires each tool_use to have a corresponding tool_result.",
                category: .ai
            )
        }

        return parameters
    }

    /// Count tool_use and tool_result blocks in messages
    private func countToolBlocks(in messages: [AnthropicMessage]) -> (toolUse: Int, toolResult: Int) {
        var toolUseCount = 0
        var toolResultCount = 0

        for message in messages {
            switch message.content {
            case .text:
                break
            case .blocks(let blocks):
                for block in blocks {
                    switch block {
                    case .toolUse:
                        toolUseCount += 1
                    case .toolResult:
                        toolResultCount += 1
                    default:
                        break
                    }
                }
            }
        }

        return (toolUseCount, toolResultCount)
    }

    // MARK: - Batched Tool Response Request

    /// Build a request after multiple tools have completed.
    ///
    /// Tool results are already stored in ConversationLog (via setToolResult).
    /// This method builds history from ConversationLog (which includes all tool_results),
    /// then appends computed context (interview state, coordinator instructions).
    ///
    /// - Parameter payloads: Payloads containing callIds and optional instructions (output not needed)
    func buildBatchedToolResponseRequest(payloads: [JSON]) async throws -> AnthropicMessageParameter {
        // Build conversation history - all tool_results are already in ConversationLog
        var messages = await historyBuilder.buildAnthropicHistory()

        // Build computed context to append: interview_context + optional coordinator instruction
        var textParts: [String] = []

        // Include interview context so Claude always has current state
        if let interviewContext = await workingMemoryBuilder.buildInterviewContext() {
            textParts.append(interviewContext)
        }

        // Check for instruction in any payload (typically the last one for UI tool completions)
        if let instruction = payloads.last?["instruction"].string, !instruction.isEmpty {
            textParts.append("<coordinator>\(instruction)</coordinator>")
            Logger.info("📋 Including coordinator instruction with batched tool results", category: .ai)
        }

        // Append computed context to the last user message (which contains tool_results from history)
        if !textParts.isEmpty {
            let textBlock = AnthropicContentBlock.text(AnthropicTextBlock(text: textParts.joined(separator: "\n\n")))
            if let lastIndex = messages.indices.last, messages[lastIndex].role == "user" {
                let existingBlocks = historyBuilder.extractContentBlocks(messages[lastIndex])
                let mergedBlocks = existingBlocks + [textBlock]
                messages[lastIndex] = AnthropicMessage(role: "user", content: .blocks(mergedBlocks))
                Logger.info("📝 Appended computed context to batched tool results message", category: .ai)
            } else {
                // Shouldn't happen - history should end with user message containing tool_results
                Logger.warning("⚠️ History doesn't end with user message - appending context as new message", category: .ai)
                messages.append(AnthropicMessage(role: "user", content: .blocks([textBlock])))
            }
        }

        let tools = await toolConverter.getAnthropicTools()
        let systemPrompt = await buildSystemPrompt()
        let modelId = try await stateCoordinator.getAnthropicModelId()

        let parameters = AnthropicMessageParameter(
            model: modelId,
            messages: messages,
            system: systemPrompt.isEmpty ? nil : .text(systemPrompt),
            maxTokens: 4096,
            stream: true,
            tools: tools.isEmpty ? nil : tools,
            toolChoice: tools.isEmpty ? nil : .auto
        )

        Logger.info(
            "📝 Built Anthropic batched tool response request: \(payloads.count) tools",
            category: .ai
        )

        return parameters
    }

    // MARK: - System Prompt

    /// Build system prompt - base personality plus todo list.
    /// Per Anthropic best practices, working memory and coordinator instructions
    /// are now included in user messages with XML tags (<interview_context>, <coordinator>).
    /// The todo list is included in system prompt since it's rebuilt each request and
    /// provides persistent visibility without polluting conversation history.
    private func buildSystemPrompt() async -> String {
        var parts: [String] = [baseSystemPrompt]

        // Include todo list if present
        if let todoList = await todoStore.renderForSystemPrompt() {
            parts.append("")
            parts.append(todoList)
            parts.append("")
            parts.append("Use the update_todo_list tool to manage your task list. Mark items in_progress before starting work, and completed when done.")
        }

        return parts.joined(separator: "\n")
    }
}

// MARK: - StateCoordinator Extension

extension StateCoordinator {
    /// Get the Anthropic model ID from settings
    /// Throws ModelConfigurationError if no model is configured
    func getAnthropicModelId() async throws -> String {
        guard let modelId = UserDefaults.standard.string(forKey: "onboardingAnthropicModelId"), !modelId.isEmpty else {
            throw ModelConfigurationError.modelNotConfigured(
                settingKey: "onboardingAnthropicModelId",
                operationName: "Anthropic Request Building"
            )
        }
        return modelId
    }
}
