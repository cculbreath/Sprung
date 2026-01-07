//
//  AnthropicHistoryBuilder.swift
//  Sprung
//
//  Builds Anthropic message history from conversation transcript.
//  Handles role alternation, message merging, and tool result validation.
//  Extracted from AnthropicRequestBuilder for single responsibility.
//

import Foundation
import SwiftOpenAI
import SwiftyJSON

/// Builds Anthropic message history from conversation transcript
struct AnthropicHistoryBuilder {
    private let contextAssembler: ConversationContextAssembler

    init(contextAssembler: ConversationContextAssembler) {
        self.contextAssembler = contextAssembler
    }

    // MARK: - History Building

    /// Build Anthropic message history from conversation transcript
    /// - Parameter excludeToolCallIds: Tool call IDs that will be added explicitly after history
    ///   (used when building tool response requests to avoid duplicate tool_results)
    func buildAnthropicHistory(excludeToolCallIds: Set<String> = []) async -> [AnthropicMessage] {
        // Get messages from transcript store through context assembler
        // Pass through excludeToolCallIds to suppress warnings for call IDs we're about to add
        let inputItems = await contextAssembler.buildConversationHistory(excludeToolCallIds: excludeToolCallIds)

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
                    // Skip non-user/assistant roles - system instructions go in system prompt
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

                // Check if this tool result has a PDF attachment that needs to be re-included
                var contentBlocks: [AnthropicContentBlock] = [
                    .toolResult(AnthropicToolResultBlock(toolUseId: output.callId, content: resultContent))
                ]

                // Parse output to check for PDF attachment metadata
                if let outputData = output.output.data(using: .utf8) {
                    let json = JSON(outputData)
                    if json["pdf_attachment"].exists() {
                        Logger.info("📄 Found pdf_attachment in tool result for callId \(output.callId.prefix(12))", category: .ai)
                        if let storagePath = json["pdf_attachment"]["storage_url"].string {
                            Logger.info("📄 PDF storage path: \(storagePath)", category: .ai)
                            if let pdfData = try? Data(contentsOf: URL(fileURLWithPath: storagePath)) {
                                let pdfBase64 = pdfData.base64EncodedString()
                                let docSource = AnthropicDocumentSource(mediaType: "application/pdf", data: pdfBase64)
                                contentBlocks.append(.document(AnthropicDocumentBlock(source: docSource)))
                                let filename = json["pdf_attachment"]["filename"].string ?? "resume.pdf"
                                Logger.info("📄 Re-including PDF in history: \(filename) (\(pdfData.count / 1024) KB)", category: .ai)
                            } else {
                                Logger.warning("⚠️ Failed to read PDF file at: \(storagePath)", category: .ai)
                            }
                        } else {
                            Logger.warning("⚠️ pdf_attachment exists but storage_url is nil", category: .ai)
                        }
                    }
                }

                messages.append(AnthropicMessage(role: "user", content: .blocks(contentBlocks)))
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

        // CRITICAL: Strip orphaned tool_use blocks from the end of conversation.
        // If the app crashed/closed while a tool was executing, the history will have
        // tool_use without tool_result. Remove these rather than adding fake results.
        messages = stripTrailingOrphanedToolUse(messages)

        // CRITICAL: Ensure every tool_use has a corresponding tool_result.
        // Race conditions (e.g., user button clicks) can cause tool_results to be missing.
        // Anthropic requires tool_result immediately after tool_use.
        // Exclude IDs that will be added explicitly after history (to avoid duplicates).
        messages = ensureToolResultsPresent(messages, excludeToolCallIds: excludeToolCallIds)

        // Validate message structure before returning
        AnthropicMessageValidator.validateMessageStructure(messages)

        // Log full message dump at DEBUG level for troubleshooting
        AnthropicMessageValidator.logMessageDump(messages, label: "Anthropic History")

        return messages
    }

    // MARK: - Message Merging

    /// Merges consecutive messages of the same role.
    /// Anthropic requires strict alternation (user → assistant → user → ...).
    /// When we skip empty messages, we can end up with adjacent same-role messages.
    /// This method combines them into single messages with merged content blocks.
    func mergeConsecutiveMessages(_ messages: [AnthropicMessage]) -> [AnthropicMessage] {
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
    func mergeMessageContent(_ first: AnthropicMessage, with second: AnthropicMessage) -> AnthropicMessage {
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
    func extractContentBlocks(_ message: AnthropicMessage) -> [AnthropicContentBlock] {
        switch message.content {
        case .text(let text):
            return [.text(AnthropicTextBlock(text: text))]
        case .blocks(let blocks):
            return blocks
        }
    }

    // MARK: - Tool Result Validation

    /// Strips orphaned tool_use blocks from the end of conversation history.
    /// When resuming an interview after a crash/close during tool execution,
    /// the last assistant message may have tool_use blocks without corresponding
    /// tool_results. Rather than adding synthetic results, we remove these
    /// orphaned tool calls entirely.
    func stripTrailingOrphanedToolUse(_ messages: [AnthropicMessage]) -> [AnthropicMessage] {
        guard !messages.isEmpty else { return [] }

        var result = messages

        // Build set of all tool_result IDs in the conversation
        var allToolResultIds = Set<String>()
        for message in messages {
            allToolResultIds.formUnion(extractToolResultIds(from: message))
        }

        // Check if last message is assistant with orphaned tool_use blocks
        while let lastMessage = result.last, lastMessage.role == "assistant" {
            let toolUseIds = extractToolUseIds(from: lastMessage)

            // Find which tool_use IDs have no corresponding tool_result
            let orphanedIds = Set(toolUseIds).subtracting(allToolResultIds)

            guard !orphanedIds.isEmpty else { break }

            Logger.warning(
                "⚠️ Stripping \(orphanedIds.count) orphaned tool_use from end of history: " +
                "\(orphanedIds.joined(separator: ", ").prefix(80))",
                category: .ai
            )

            // Remove orphaned tool_use blocks from the message
            if case .blocks(let blocks) = lastMessage.content {
                let filteredBlocks = blocks.filter { block in
                    if case .toolUse(let toolUse) = block {
                        return !orphanedIds.contains(toolUse.id)
                    }
                    return true
                }

                if filteredBlocks.isEmpty {
                    // Entire message was orphaned tool_use - remove the message
                    result.removeLast()
                    Logger.info("📝 Removed empty assistant message after stripping orphaned tool_use", category: .ai)
                } else {
                    // Replace with filtered message
                    result[result.count - 1] = AnthropicMessage(
                        role: "assistant",
                        content: .blocks(filteredBlocks)
                    )
                    break // Message still has content, we're done
                }
            } else {
                break // Not a blocks message, nothing to strip
            }
        }

        return result
    }

    /// Ensures every tool_use block has a corresponding tool_result.
    /// Anthropic requires tool_result immediately after tool_use. Race conditions during
    /// user button clicks can cause tool_results to be missing from the transcript.
    /// This function inserts synthetic tool_results for any truly missing ones.
    /// - Parameter excludeToolCallIds: Tool call IDs that will be added explicitly after history
    ///   (used when building tool response requests to avoid duplicates)
    func ensureToolResultsPresent(
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
    func extractToolUseIds(from message: AnthropicMessage) -> [String] {
        guard case .blocks(let blocks) = message.content else { return [] }
        return blocks.compactMap { block in
            if case .toolUse(let toolUse) = block {
                return toolUse.id
            }
            return nil
        }
    }

    /// Extract tool_result IDs from a user message
    func extractToolResultIds(from message: AnthropicMessage) -> Set<String> {
        guard case .blocks(let blocks) = message.content else { return [] }
        return Set(blocks.compactMap { block in
            if case .toolResult(let toolResult) = block {
                return toolResult.toolUseId
            }
            return nil
        })
    }
}
