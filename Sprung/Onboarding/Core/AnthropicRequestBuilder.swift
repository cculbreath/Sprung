//
//  AnthropicRequestBuilder.swift
//  Sprung
//
//  Builds AnthropicMessageParameter requests for the Onboarding Interview's Anthropic Messages API calls.
//  Mirrors OnboardingRequestBuilder but for Anthropic's API format.
//

import Foundation
import SwiftOpenAI
import SwiftyJSON

/// Builds AnthropicMessageParameter requests for the Onboarding Interview's Anthropic Messages API calls.
/// Extracted to separate request construction from stream handling.
struct AnthropicRequestBuilder {
    private let baseDeveloperMessage: String
    private let toolRegistry: ToolRegistry
    private let contextAssembler: ConversationContextAssembler
    private let stateCoordinator: StateCoordinator

    init(
        baseDeveloperMessage: String,
        toolRegistry: ToolRegistry,
        contextAssembler: ConversationContextAssembler,
        stateCoordinator: StateCoordinator
    ) {
        self.baseDeveloperMessage = baseDeveloperMessage
        self.toolRegistry = toolRegistry
        self.contextAssembler = contextAssembler
        self.stateCoordinator = stateCoordinator
    }

    // MARK: - User Message Request

    func buildUserMessageRequest(
        text: String,
        isSystemGenerated: Bool,
        bundledDeveloperMessages: [JSON] = [],
        forcedToolChoice: String? = nil,
        imageBase64: String? = nil,
        imageContentType: String? = nil
    ) async -> AnthropicMessageParameter {
        var messages: [AnthropicMessage] = []

        // Build conversation history (Anthropic uses explicit messages, no PRI)
        // Always include full history for Anthropic
        let hasHistory = await contextAssembler.hasConversationHistory()
        if hasHistory {
            let history = await buildAnthropicHistory()
            messages.append(contentsOf: history)
            Logger.info("📋 Including \(history.count) messages from transcript", category: .ai)
        }

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
                    .text(AnthropicTextBlock(text: text)),
                    .document(AnthropicDocumentBlock(source: docSource))
                ]
                Logger.info("📄 Including PDF document in user message", category: .ai)
            } else {
                let imageSource = AnthropicImageSource(mediaType: mimeType, data: fileData)
                newUserBlocks = [
                    .text(AnthropicTextBlock(text: text)),
                    .image(AnthropicImageBlock(source: imageSource))
                ]
                Logger.info("🖼️ Including image attachment in user message (\(mimeType))", category: .ai)
            }
        } else {
            newUserBlocks = [.text(AnthropicTextBlock(text: text))]
        }

        // Check if we need to merge with trailing user message from history
        if let lastIndex = messages.indices.last,
           messages[lastIndex].role == "user" {
            // Merge new content with existing user message
            let existingBlocks = extractContentBlocks(messages[lastIndex])
            let mergedBlocks = existingBlocks + newUserBlocks
            messages[lastIndex] = AnthropicMessage(role: "user", content: .blocks(mergedBlocks))
            Logger.info("📝 Merged new user content with trailing user message (race condition handling)", category: .ai)
        } else {
            // Append as new user message
            messages.append(AnthropicMessage(role: "user", content: .blocks(newUserBlocks)))
        }

        // Determine tool choice
        let effectiveForcedToolChoice: String?
        if let forcedToolChoice {
            effectiveForcedToolChoice = forcedToolChoice
        } else {
            effectiveForcedToolChoice = await stateCoordinator.popPendingForcedToolChoice()
        }

        let toolChoice: AnthropicToolChoice
        if let forcedTool = effectiveForcedToolChoice {
            // Use 'any' instead of forcing specific tool - Anthropic has a bug where
            // forced tool_choice returns stop_reason=tool_use but no content blocks.
            // The system prompt guides the model to call the intended tool.
            toolChoice = .any
            Logger.info("🎯 Using toolChoice=any (intended: \(forcedTool)) - Anthropic workaround", category: .ai)
        } else if !isSystemGenerated {
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
        let tools = await getAnthropicTools()

        // Build system prompt (includes base developer message + working memory + bundled messages)
        let systemPrompt = await buildSystemPrompt(bundledDeveloperMessages: bundledDeveloperMessages)

        let modelId = await stateCoordinator.getAnthropicModelId()

        let parameters = AnthropicMessageParameter(
            model: modelId,
            messages: messages,
            system: systemPrompt.isEmpty ? nil : .text(systemPrompt),
            maxTokens: 4096,
            stream: true,
            tools: tools.isEmpty ? nil : tools,
            toolChoice: toolChoice == .none && tools.isEmpty ? nil : toolChoice,
            temperature: 1.0
        )

        Logger.info(
            "📝 Built Anthropic request: messages=\(messages.count), tools=\(tools.count)",
            category: .ai
        )

        return parameters
    }

    // MARK: - Developer Message Request

    func buildDeveloperMessageRequest(
        text: String,
        toolChoice toolChoiceName: String? = nil
    ) async -> AnthropicMessageParameter {
        var messages: [AnthropicMessage] = []

        // Include conversation history
        let hasHistory = await contextAssembler.hasConversationHistory()
        if hasHistory {
            let history = await buildAnthropicHistory()
            messages.append(contentsOf: history)
        }

        // For Anthropic, developer instructions go in the system prompt
        // We still need a user message to trigger a response
        // Use a minimal user prompt to represent the developer instruction
        // CRITICAL: Check if history ends with user message (e.g., synthetic tool_result) and merge if so
        let placeholderText = "[System instruction received - please continue the conversation]"
        if let lastIndex = messages.indices.last,
           messages[lastIndex].role == "user" {
            let existingBlocks = extractContentBlocks(messages[lastIndex])
            let mergedBlocks = existingBlocks + [.text(AnthropicTextBlock(text: placeholderText))]
            messages[lastIndex] = AnthropicMessage(role: "user", content: .blocks(mergedBlocks))
            Logger.info("📝 Merged developer placeholder with trailing user message (race condition handling)", category: .ai)
        } else {
            messages.append(.user(placeholderText))
        }

        let toolChoice: AnthropicToolChoice
        if let toolName = toolChoiceName {
            toolChoice = .tool(name: toolName)
        } else {
            toolChoice = .auto
        }

        let tools = await getAnthropicTools()
        let systemPrompt = await buildSystemPrompt(additionalInstruction: text)
        let modelId = await stateCoordinator.getAnthropicModelId()

        let parameters = AnthropicMessageParameter(
            model: modelId,
            messages: messages,
            system: systemPrompt.isEmpty ? nil : .text(systemPrompt),
            maxTokens: 4096,
            stream: true,
            tools: tools.isEmpty ? nil : tools,
            toolChoice: tools.isEmpty ? nil : toolChoice,
            temperature: 1.0
        )

        Logger.info(
            "📝 Built Anthropic developer message request: messages=\(messages.count)",
            category: .ai
        )

        return parameters
    }

    // MARK: - Tool Response Request

    func buildToolResponseRequest(
        output: JSON,
        callId: String,
        toolName: String,
        forcedToolChoice: String? = nil
    ) async -> AnthropicMessageParameter {
        var messages: [AnthropicMessage] = []

        // Include conversation history, excluding the current callId since we add it below
        let hasHistory = await contextAssembler.hasConversationHistory()
        if hasHistory {
            let history = await buildAnthropicHistory(excludeToolCallIds: [callId])
            messages.append(contentsOf: history)
        }

        // Add tool result as user message
        let resultContent = output.rawString() ?? "{}"
        messages.append(.toolResult(toolUseId: callId, content: resultContent))

        let toolChoice: AnthropicToolChoice
        if let forcedTool = forcedToolChoice {
            // Use 'any' instead of forcing specific tool - Anthropic has a bug where
            // forced tool_choice returns stop_reason=tool_use but no content blocks.
            // The system prompt guides the model to call the intended tool.
            toolChoice = .any
            Logger.info("🔗 Using toolChoice=any (intended: \(forcedTool)) - Anthropic workaround", category: .ai)
        } else {
            toolChoice = .auto
        }

        let tools = await getAnthropicTools()
        let systemPrompt = await buildSystemPrompt()
        let modelId = await stateCoordinator.getAnthropicModelId()

        let parameters = AnthropicMessageParameter(
            model: modelId,
            messages: messages,
            system: systemPrompt.isEmpty ? nil : .text(systemPrompt),
            maxTokens: 4096,
            stream: true,
            tools: tools.isEmpty ? nil : tools,
            toolChoice: tools.isEmpty ? nil : toolChoice,
            temperature: 1.0
        )

        // Log diagnostic info about tool blocks
        let (toolUseCount, toolResultCount) = countToolBlocks(in: messages)
        Logger.info(
            "📝 Built Anthropic tool response request: callId=\(callId), " +
            "tool_use=\(toolUseCount), tool_result=\(toolResultCount) (should match after this response)",
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

    func buildBatchedToolResponseRequest(payloads: [JSON]) async -> AnthropicMessageParameter {
        var messages: [AnthropicMessage] = []

        // Extract all callIds to exclude from history (we add them below)
        let excludeCallIds = Set(payloads.map { $0["callId"].stringValue })

        // Include conversation history, excluding the current callIds since we add them below
        let hasHistory = await contextAssembler.hasConversationHistory()
        if hasHistory {
            let history = await buildAnthropicHistory(excludeToolCallIds: excludeCallIds)
            messages.append(contentsOf: history)
        }

        // Add all tool results in a single user message with multiple tool_result blocks
        var toolResultBlocks: [AnthropicContentBlock] = []
        for payload in payloads {
            let callId = payload["callId"].stringValue
            let output = payload["output"]
            let resultContent = output.rawString() ?? "{}"
            toolResultBlocks.append(.toolResult(AnthropicToolResultBlock(
                toolUseId: callId,
                content: resultContent
            )))
        }
        messages.append(AnthropicMessage(role: "user", content: .blocks(toolResultBlocks)))

        let tools = await getAnthropicTools()
        let systemPrompt = await buildSystemPrompt()
        let modelId = await stateCoordinator.getAnthropicModelId()

        let parameters = AnthropicMessageParameter(
            model: modelId,
            messages: messages,
            system: systemPrompt.isEmpty ? nil : .text(systemPrompt),
            maxTokens: 4096,
            stream: true,
            tools: tools.isEmpty ? nil : tools,
            toolChoice: tools.isEmpty ? nil : .auto,
            temperature: 1.0
        )

        Logger.info(
            "📝 Built Anthropic batched tool response request: \(payloads.count) tool outputs",
            category: .ai
        )

        return parameters
    }

    // MARK: - System Prompt

    private func buildSystemPrompt(
        bundledDeveloperMessages: [JSON] = [],
        additionalInstruction: String? = nil
    ) async -> String {
        var parts: [String] = [baseDeveloperMessage]

        // Add bundled developer messages
        for devPayload in bundledDeveloperMessages {
            let devText = devPayload["text"].stringValue
            if !devText.isEmpty {
                parts.append(devText)
            }
        }

        // Add additional instruction if provided
        if let instruction = additionalInstruction {
            parts.append(instruction)
        }

        // Add working memory
        if let workingMemory = await buildWorkingMemory() {
            parts.append(workingMemory)
        }

        return parts.joined(separator: "\n\n")
    }

    // MARK: - History Building

    /// Build Anthropic message history from conversation transcript
    /// - Parameter excludeToolCallIds: Tool call IDs that will be added explicitly after history
    ///   (used when building tool response requests to avoid duplicate tool_results)
    private func buildAnthropicHistory(excludeToolCallIds: Set<String> = []) async -> [AnthropicMessage] {
        // Get messages from transcript store through context assembler
        let inputItems = await contextAssembler.buildConversationHistory()

        var messages: [AnthropicMessage] = []
        // Track pending assistant content blocks to merge text + tool_use into single message
        var pendingAssistantBlocks: [AnthropicContentBlock] = []

        /// Helper to flush pending assistant blocks as a single message
        func flushAssistantBlocks() {
            guard !pendingAssistantBlocks.isEmpty else { return }
            messages.append(AnthropicMessage(role: "assistant", content: .blocks(pendingAssistantBlocks)))
            pendingAssistantBlocks = []
        }

        for item in inputItems {
            switch item {
            case .message(let inputMessage):
                switch inputMessage.role {
                case "user":
                    // User message - flush any pending assistant blocks first
                    flushAssistantBlocks()
                    if case .text(let text) = inputMessage.content {
                        // Skip empty user messages - Anthropic requires non-empty content
                        guard !text.isEmpty else {
                            Logger.warning("⚠️ Skipping empty user message in Anthropic history", category: .ai)
                            continue
                        }
                        messages.append(.user(text))
                    }
                case "assistant":
                    if case .text(let text) = inputMessage.content {
                        // Skip empty assistant text - but don't flush yet, tool_use may follow
                        guard !text.isEmpty else {
                            Logger.debug("📝 Skipping empty assistant text block", category: .ai)
                            continue
                        }
                        // Add text as a content block (will be merged with tool_use if any)
                        pendingAssistantBlocks.append(.text(AnthropicTextBlock(text: text)))
                    }
                default:
                    // Skip developer messages - they go in system prompt
                    break
                }
            case .functionToolCall(let toolCall):
                // Tool calls are assistant content blocks - add to pending
                var inputDict: [String: Any] = [:]
                if let argsData = toolCall.arguments.data(using: .utf8),
                   let parsed = try? JSONSerialization.jsonObject(with: argsData) as? [String: Any] {
                    inputDict = parsed
                }
                pendingAssistantBlocks.append(.toolUse(AnthropicToolUseBlock(
                    id: toolCall.callId,
                    name: toolCall.name,
                    input: inputDict
                )))
                Logger.debug("📝 Added assistant tool_use block: \(toolCall.name)", category: .ai)
            case .functionToolCallOutput(let output):
                // Tool result is a user message - flush pending assistant blocks first
                flushAssistantBlocks()
                // Ensure tool result has content - Anthropic requires non-empty content
                let resultContent = output.output.isEmpty ? "{\"status\":\"completed\"}" : output.output
                if output.output.isEmpty {
                    Logger.warning("⚠️ Empty tool result for callId \(output.callId) - using placeholder", category: .ai)
                }
                messages.append(.toolResult(
                    toolUseId: output.callId,
                    content: resultContent
                ))
            default:
                break
            }
        }

        // Flush any remaining assistant blocks
        flushAssistantBlocks()

        // CRITICAL: Anthropic requires conversations to start with a user message.
        // If history starts with assistant (e.g., welcome message), prepend a placeholder.
        if let first = messages.first, first.role == "assistant" {
            Logger.debug("📝 Anthropic history starts with assistant - prepending user placeholder", category: .ai)
            messages.insert(.user("[Beginning of conversation]"), at: 0)
        }

        // CRITICAL: Merge consecutive messages of the same role.
        // Skipping empty messages can leave adjacent same-role messages which Anthropic rejects.
        messages = mergeConsecutiveMessages(messages)

        // CRITICAL: Ensure every tool_use has a corresponding tool_result.
        // Race conditions (e.g., user button clicks) can cause tool_results to be missing.
        // Anthropic requires tool_result immediately after tool_use.
        // Exclude IDs that will be added explicitly after history (to avoid duplicates).
        messages = ensureToolResultsPresent(messages, excludeToolCallIds: excludeToolCallIds)

        // Validate message structure before returning
        validateMessageStructure(messages)

        // Log full message dump at DEBUG level for troubleshooting
        logMessageDump(messages, label: "Anthropic History")

        return messages
    }

    /// Dump full message structure for debugging API errors
    private func logMessageDump(_ messages: [AnthropicMessage], label: String) {
        var dump = "📋 \(label) (\(messages.count) messages):\n"
        for (index, message) in messages.enumerated() {
            let contentDesc: String
            switch message.content {
            case .text(let text):
                let preview = String(text.prefix(80)).replacingOccurrences(of: "\n", with: "\\n")
                contentDesc = "text(\(text.count) chars): \"\(preview)...\""
            case .blocks(let blocks):
                let blockDescs = blocks.map { block -> String in
                    switch block {
                    case .text(let tb):
                        return "text(\(tb.text.count))"
                    case .toolUse(let tu):
                        return "tool_use(\(tu.name), id:\(tu.id.prefix(8)))"
                    case .toolResult(let tr):
                        return "tool_result(id:\(tr.toolUseId.prefix(8)), \(tr.content.count) chars)"
                    case .image:
                        return "image"
                    case .document:
                        return "document"
                    }
                }
                contentDesc = "[\(blockDescs.joined(separator: ", "))]"
            }
            dump += "  [\(index)] \(message.role): \(contentDesc)\n"
        }
        Logger.debug(dump, category: .ai)
    }

    /// Validates that messages follow Anthropic's requirements:
    /// 1. Must start with user message
    /// 2. Must alternate between user and assistant roles
    /// 3. No consecutive messages of the same role
    private func validateMessageStructure(_ messages: [AnthropicMessage]) {
        guard !messages.isEmpty else { return }

        var hasErrors = false

        // Check starts with user
        if messages.first?.role != "user" {
            Logger.error("❌ Anthropic validation: First message is not user role, got: \(messages.first?.role ?? "nil")", category: .ai)
            hasErrors = true
        }

        // Check alternation
        var lastRole: String?
        for (index, message) in messages.enumerated() {
            if let last = lastRole, last == message.role {
                Logger.error("❌ Anthropic validation: Consecutive \(message.role) messages at index \(index-1) and \(index)", category: .ai)
                // Log the content for debugging
                if let content = getContentSummary(message) {
                    Logger.warning("   Message \(index) content: \(content)", category: .ai)
                }
                hasErrors = true
            }
            lastRole = message.role
        }

        // Always log the final state at INFO level for debugging
        if let last = messages.last {
            let summary = getContentSummary(last) ?? "unknown"
            if hasErrors {
                Logger.error("📝 Anthropic history ends with \(last.role) message: \(summary)", category: .ai)
            } else {
                Logger.info("📝 Anthropic validation passed: \(messages.count) messages, ends with \(last.role)", category: .ai)
            }
        }
    }

    /// Get a summary of message content for debugging
    private func getContentSummary(_ message: AnthropicMessage) -> String? {
        switch message.content {
        case .text(let text):
            return "text: \(text.prefix(50))..."
        case .blocks(let blocks):
            let types = blocks.map { block -> String in
                switch block {
                case .text: return "text"
                case .toolUse(let tu): return "tool_use(\(tu.name))"
                case .toolResult(let tr): return "tool_result(\(tr.toolUseId.prefix(8)))"
                case .image: return "image"
                case .document: return "document"
                }
            }
            return "blocks: [\(types.joined(separator: ", "))]"
        }
    }

    /// Merges consecutive messages of the same role.
    /// Anthropic requires strict alternation (user → assistant → user → ...).
    /// When we skip empty messages, we can end up with adjacent same-role messages.
    /// This method combines them into single messages with merged content blocks.
    private func mergeConsecutiveMessages(_ messages: [AnthropicMessage]) -> [AnthropicMessage] {
        guard !messages.isEmpty else { return [] }

        var result: [AnthropicMessage] = []

        for message in messages {
            if let lastIndex = result.indices.last, result[lastIndex].role == message.role {
                // Same role as previous - merge content
                let merged = mergeMessageContent(result[lastIndex], with: message)
                result[lastIndex] = merged
                Logger.debug("📝 Merged consecutive \(message.role) messages", category: .ai)
            } else {
                // Different role - just append
                result.append(message)
            }
        }

        return result
    }

    /// Merge content from two messages of the same role into a single message
    /// Deduplicates tool_result blocks by tool_use_id (keeps first occurrence)
    private func mergeMessageContent(_ first: AnthropicMessage, with second: AnthropicMessage) -> AnthropicMessage {
        let firstBlocks = extractContentBlocks(first)
        let secondBlocks = extractContentBlocks(second)

        // Deduplicate tool_result blocks - keep first occurrence of each tool_use_id
        var seenToolResultIds = Set<String>()
        var mergedBlocks: [AnthropicContentBlock] = []

        for block in firstBlocks + secondBlocks {
            if case .toolResult(let result) = block {
                if seenToolResultIds.contains(result.toolUseId) {
                    Logger.debug("📝 Skipping duplicate tool_result for \(result.toolUseId.prefix(12))", category: .ai)
                    continue
                }
                seenToolResultIds.insert(result.toolUseId)
            }
            mergedBlocks.append(block)
        }

        return AnthropicMessage(role: first.role, content: .blocks(mergedBlocks))
    }

    /// Extract content blocks from a message (converts .text to a single text block)
    private func extractContentBlocks(_ message: AnthropicMessage) -> [AnthropicContentBlock] {
        switch message.content {
        case .text(let text):
            return [.text(AnthropicTextBlock(text: text))]
        case .blocks(let blocks):
            return blocks
        }
    }

    /// Ensures every tool_use block has a corresponding tool_result.
    /// Anthropic requires tool_result immediately after tool_use. Race conditions during
    /// user button clicks can cause tool_results to be missing from the transcript.
    /// This function inserts synthetic tool_results for any truly missing ones.
    /// - Parameter excludeToolCallIds: Tool call IDs that will be added explicitly after history
    ///   (used when building tool response requests to avoid duplicates)
    private func ensureToolResultsPresent(
        _ messages: [AnthropicMessage],
        excludeToolCallIds: Set<String> = []
    ) -> [AnthropicMessage] {
        // FIRST: Build a global set of ALL tool_result IDs that exist anywhere in the messages.
        // This prevents inserting synthetic results for tool_uses that have results later.
        // Also include excluded IDs - these will be added explicitly by the caller.
        var allExistingResultIds = excludeToolCallIds
        for message in messages {
            let resultIds = extractToolResultIds(from: message)
            allExistingResultIds.formUnion(resultIds)
        }

        var result: [AnthropicMessage] = []

        for message in messages {
            result.append(message)

            // Only check assistant messages for tool_use blocks
            guard message.role == "assistant" else { continue }

            // Extract tool_use IDs from this assistant message
            let toolUseIds = extractToolUseIds(from: message)
            guard !toolUseIds.isEmpty else { continue }

            // Check which tool_uses are TRULY missing (not anywhere in the conversation)
            let trulyMissingIds = toolUseIds.filter { !allExistingResultIds.contains($0) }

            if !trulyMissingIds.isEmpty {
                // Insert synthetic tool_results for truly missing IDs
                Logger.warning(
                    "⚠️ Missing tool_result for \(trulyMissingIds.count) tool(s): \(trulyMissingIds.joined(separator: ", ").prefix(80)). " +
                    "Inserting synthetic results.",
                    category: .ai
                )

                // Create synthetic tool_result blocks
                var syntheticBlocks: [AnthropicContentBlock] = []
                for missingId in trulyMissingIds {
                    syntheticBlocks.append(.toolResult(AnthropicToolResultBlock(
                        toolUseId: missingId,
                        content: "{\"status\":\"completed\",\"message\":\"Action completed by user\"}"
                    )))
                    // Track that we've now added this result
                    allExistingResultIds.insert(missingId)
                }

                // Insert synthetic user message with tool_results
                result.append(AnthropicMessage(role: "user", content: .blocks(syntheticBlocks)))
            }
        }

        // After adding synthetic results, we might have consecutive user messages - merge again
        return mergeConsecutiveMessages(result)
    }

    /// Extract tool_use IDs from an assistant message
    private func extractToolUseIds(from message: AnthropicMessage) -> [String] {
        guard case .blocks(let blocks) = message.content else { return [] }
        return blocks.compactMap { block in
            if case .toolUse(let toolUse) = block {
                return toolUse.id
            }
            return nil
        }
    }

    /// Extract tool_result IDs from a user message
    private func extractToolResultIds(from message: AnthropicMessage) -> Set<String> {
        guard case .blocks(let blocks) = message.content else { return [] }
        return Set(blocks.compactMap { block in
            if case .toolResult(let toolResult) = block {
                return toolResult.toolUseId
            }
            return nil
        })
    }

    // MARK: - Tool Conversion

    private func getAnthropicTools() async -> [AnthropicTool] {
        // Get current state for subphase inference
        let phase = await stateCoordinator.phase
        let toolPaneCard = await stateCoordinator.getCurrentToolPaneCard()
        let objectives = await stateCoordinator.getObjectiveStatusMap()

        // Infer current subphase from objectives + UI state
        let subphase = ToolBundlePolicy.inferSubphase(
            phase: phase,
            toolPaneCard: toolPaneCard,
            objectives: objectives
        )

        // Select tools based on subphase
        let bundledNames = ToolBundlePolicy.selectBundleForSubphase(subphase, toolChoice: nil)

        if bundledNames.isEmpty {
            Logger.debug("🔧 Anthropic tool bundling: subphase=\(subphase.rawValue), sending 0 tools", category: .ai)
            return []
        }

        // Get OpenAI Tool schemas and convert to Anthropic format
        let openAITools = await toolRegistry.toolSchemas(filteredBy: bundledNames)
        var anthropicTools: [AnthropicTool] = openAITools.compactMap { tool -> AnthropicTool? in
            guard case .function(let funcTool) = tool else { return nil }
            return convertToAnthropicTool(funcTool)
        }

        // Add web_search server-side tool
        anthropicTools.append(.serverTool(.webSearch()))

        Logger.debug(
            "🔧 Anthropic tool bundling: subphase=\(subphase.rawValue), sending \(anthropicTools.count) tools (incl. web_search)",
            category: .ai
        )

        return anthropicTools
    }

    private func convertToAnthropicTool(_ funcTool: Tool.FunctionTool) -> AnthropicTool {
        // Convert JSONSchema to dictionary for Anthropic's input_schema
        let inputSchema = convertJSONSchemaToDictionary(funcTool.parameters)

        return .function(AnthropicFunctionTool(
            name: funcTool.name,
            description: funcTool.description,
            inputSchema: inputSchema
        ))
    }

    private func convertJSONSchemaToDictionary(_ schema: JSONSchema) -> [String: Any] {
        var result: [String: Any] = [:]

        // Type - convert JSONSchemaType to string
        if let schemaType = schema.type {
            result["type"] = jsonSchemaTypeToString(schemaType)
        }

        // Properties
        if let properties = schema.properties {
            var propsDict: [String: Any] = [:]
            for (key, propSchema) in properties {
                propsDict[key] = convertJSONSchemaToDictionary(propSchema)
            }
            result["properties"] = propsDict
        }

        // Required
        if let required = schema.required {
            result["required"] = required
        }

        // Description
        if let description = schema.description {
            result["description"] = description
        }

        // Items (for arrays)
        if let items = schema.items {
            result["items"] = convertJSONSchemaToDictionary(items)
        }

        // Enum (JSONSchema uses backtick `enum`)
        if let enumValues = schema.`enum` {
            result["enum"] = enumValues
        }

        // Additional properties (simple Bool? in JSONSchema)
        if let additionalProps = schema.additionalProperties {
            result["additionalProperties"] = additionalProps
        }

        return result
    }

    /// Convert JSONSchemaType to its string representation
    private func jsonSchemaTypeToString(_ type: JSONSchemaType) -> String {
        switch type {
        case .string: return "string"
        case .number: return "number"
        case .integer: return "integer"
        case .boolean: return "boolean"
        case .object: return "object"
        case .array: return "array"
        case .null: return "null"
        case .union(let types):
            // For union types, return the first non-null type
            // (Anthropic doesn't support union types directly)
            if let firstType = types.first(where: { $0 != .null }) {
                return jsonSchemaTypeToString(firstType)
            }
            return "string"
        }
    }

    // MARK: - Working Memory

    private func buildWorkingMemory() async -> String? {
        let phase = await stateCoordinator.phase

        var parts: [String] = []
        parts.append("## Working Memory (Phase: \(phase.shortName))")

        let currentPanel = await stateCoordinator.getCurrentToolPaneCard()
        if currentPanel != .none {
            parts.append("Visible UI: \(currentPanel.rawValue)")
        } else {
            parts.append("Visible UI: none (call upload/prompt tools to show UI)")
        }

        let objectives = await stateCoordinator.getObjectivesForPhase(phase)
        if !objectives.isEmpty {
            let statusList = objectives.map { "\($0.id): \($0.status.rawValue)" }
            parts.append("Objectives: \(statusList.joined(separator: ", "))")
        }

        let artifacts = await stateCoordinator.artifacts
        if let entries = artifacts.skeletonTimeline?["experiences"].array, !entries.isEmpty {
            let timelineSummary = entries.prefix(6).compactMap { entry -> String? in
                guard let org = entry["organization"].string,
                      let title = entry["title"].string else { return nil }
                let dates = [entry["start"].string, entry["end"].string]
                    .compactMap { $0 }
                    .joined(separator: "-")
                return "\(title) @ \(org)" + (dates.isEmpty ? "" : " (\(dates))")
            }
            if !timelineSummary.isEmpty {
                parts.append("Timeline (\(entries.count) entries): \(timelineSummary.joined(separator: "; "))")
            }
        }

        let artifactSummaries = await stateCoordinator.listArtifactSummaries()
        if !artifactSummaries.isEmpty {
            let artifactSummary = artifactSummaries.prefix(6).compactMap { record -> String? in
                guard let filename = record["filename"].string else { return nil }
                let desc = record["brief_description"].string ?? record["summary"].string ?? ""
                let shortDesc = desc.isEmpty ? "" : " - \(String(desc.prefix(40)))"
                return filename + shortDesc
            }
            if !artifactSummary.isEmpty {
                parts.append("Artifacts (\(artifactSummaries.count)): \(artifactSummary.joined(separator: "; "))")
            }
        }

        let dossierNotes = await stateCoordinator.getDossierNotes()
        if !dossierNotes.isEmpty {
            let truncatedNotes = String(dossierNotes.prefix(800))
            parts.append("Dossier Notes:\n\(truncatedNotes)")
        }

        guard parts.count > 1 else { return nil }

        let memory = parts.joined(separator: "\n")
        let maxChars = 2500
        if memory.count > maxChars {
            Logger.warning("⚠️ WorkingMemory exceeds target (\(memory.count) chars)", category: .ai)
            return String(memory.prefix(maxChars))
        }

        Logger.debug("📋 WorkingMemory: \(memory.count) chars", category: .ai)
        return memory
    }
}

// MARK: - OnboardingProvider Enum

/// Available LLM providers for the onboarding interview
enum OnboardingProvider: String, CaseIterable {
    case openai = "openai"
    case anthropic = "anthropic"

    var displayName: String {
        switch self {
        case .openai: return "OpenAI"
        case .anthropic: return "Anthropic"
        }
    }
}

// MARK: - StateCoordinator Extension

extension StateCoordinator {
    /// Get the Anthropic model ID from settings
    func getAnthropicModelId() async -> String {
        return UserDefaults.standard.string(forKey: "onboardingAnthropicModelId") ?? DefaultModels.anthropic
    }

    /// Get the currently selected onboarding provider
    func getOnboardingProvider() async -> OnboardingProvider {
        let rawValue = UserDefaults.standard.string(forKey: "onboardingProvider") ?? "openai"
        return OnboardingProvider(rawValue: rawValue) ?? .openai
    }

    /// Set the onboarding provider
    func setOnboardingProvider(_ provider: OnboardingProvider) async {
        UserDefaults.standard.set(provider.rawValue, forKey: "onboardingProvider")
    }
}
