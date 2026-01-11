//
//  AnthropicHistoryBuilder.swift
//  Sprung
//
//  Builds Anthropic message history from conversation transcript.
//  Handles role alternation, message merging, and PDF re-inclusion for resume uploads.
//
//  Anthropic API Invariant: Every tool_use block MUST have a corresponding
//  tool_result block with matching tool_use_id in the immediately following
//  user message. Orphaned tool calls are cleaned up at ConversationLog.restore() time.
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
    func buildAnthropicHistory() async -> [AnthropicMessage] {
        let inputItems = await contextAssembler.buildConversationHistory()

        var messages: [AnthropicMessage] = []
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
                    flushAssistantBlocks()
                    if case .text(let text) = inputMessage.content {
                        guard !text.isEmpty else {
                            Logger.warning("⚠️ Skipping empty user message in Anthropic history", category: .ai)
                            continue
                        }

                        // Check for PDF attachment that needs to be re-included (resume uploads)
                        // The user message text contains <ui-action-result> with pdfAttachment.storageUrl
                        if let pdfBlocks = extractPDFFromUserMessage(text) {
                            var contentBlocks: [AnthropicContentBlock] = [.text(AnthropicTextBlock(text: text))]
                            contentBlocks.append(contentsOf: pdfBlocks)
                            messages.append(AnthropicMessage(role: "user", content: .blocks(contentBlocks)))
                        } else {
                            messages.append(.user(text))
                        }
                    }
                case "assistant":
                    if case .text(let text) = inputMessage.content {
                        guard !text.isEmpty else {
                            Logger.debug("📝 Skipping empty assistant text block", category: .ai)
                            continue
                        }
                        pendingAssistantBlocks.append(.text(AnthropicTextBlock(text: text)))
                    }
                default:
                    break
                }

            case .functionToolCall(let toolCall):
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

            case .functionToolCallOutput(let output):
                flushAssistantBlocks()
                let resultContent = output.output.isEmpty ? "{\"status\":\"completed\"}" : output.output

                var contentBlocks: [AnthropicContentBlock] = [
                    .toolResult(AnthropicToolResultBlock(toolUseId: output.callId, content: resultContent))
                ]

                // Check for PDF attachment that needs to be re-included
                if let outputData = output.output.data(using: .utf8) {
                    let json = JSON(outputData)
                    if json["pdfAttachment"].exists(),
                       let storagePath = json["pdfAttachment"]["storageUrl"].string,
                       let pdfData = try? Data(contentsOf: URL(fileURLWithPath: storagePath)) {
                        let pdfBase64 = pdfData.base64EncodedString()
                        let docSource = AnthropicDocumentSource(mediaType: "application/pdf", data: pdfBase64)
                        contentBlocks.append(.document(AnthropicDocumentBlock(source: docSource)))
                        let filename = json["pdfAttachment"]["filename"].string ?? "resume.pdf"
                        Logger.info("📄 Re-including PDF in history: \(filename) (\(pdfData.count / 1024) KB)", category: .ai)
                    }
                }

                messages.append(AnthropicMessage(role: "user", content: .blocks(contentBlocks)))

            default:
                break
            }
        }

        flushAssistantBlocks()

        // Anthropic requires conversations to start with a user message
        if let first = messages.first, first.role == "assistant" {
            Logger.debug("📝 Anthropic history starts with assistant - prepending user placeholder", category: .ai)
            messages.insert(.user("[Beginning of conversation]"), at: 0)
        }

        // Merge consecutive messages of same role (can happen after skipping empty messages)
        messages = mergeConsecutiveMessages(messages)

        // Note: Orphaned tool calls are now removed at ConversationLog.restore() time,
        // so we no longer need to repair them here.

        // Validate and log
        AnthropicMessageValidator.validateMessageStructure(messages)
        AnthropicMessageValidator.logMessageDump(messages, label: "Anthropic History")

        return messages
    }

    // MARK: - Message Merging

    /// Merges consecutive messages of the same role
    func mergeConsecutiveMessages(_ messages: [AnthropicMessage]) -> [AnthropicMessage] {
        guard !messages.isEmpty else { return [] }

        var result: [AnthropicMessage] = []

        for message in messages {
            if let lastIndex = result.indices.last, result[lastIndex].role == message.role {
                let merged = mergeMessageContent(result[lastIndex], with: message)
                result[lastIndex] = merged
                Logger.debug("📝 Merged consecutive \(message.role) messages", category: .ai)
            } else {
                result.append(message)
            }
        }

        return result
    }

    /// Merge content from two messages of the same role
    func mergeMessageContent(_ first: AnthropicMessage, with second: AnthropicMessage) -> AnthropicMessage {
        let firstBlocks = extractContentBlocks(first)
        let secondBlocks = extractContentBlocks(second)

        // Deduplicate tool_result blocks by tool_use_id
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

    /// Extract content blocks from a message
    func extractContentBlocks(_ message: AnthropicMessage) -> [AnthropicContentBlock] {
        switch message.content {
        case .text(let text):
            return [.text(AnthropicTextBlock(text: text))]
        case .blocks(let blocks):
            return blocks
        }
    }

    // MARK: - PDF Re-inclusion

    /// Extract PDF attachment from user message text if present.
    /// User messages containing resume uploads have <ui-action-result> tags with pdfAttachment info.
    /// Returns document blocks to append if PDF found, nil otherwise.
    private func extractPDFFromUserMessage(_ text: String) -> [AnthropicContentBlock]? {
        // Look for <ui-action-result> tag containing pdfAttachment
        guard text.contains("pdfAttachment") else { return nil }

        // Extract JSON content from the ui-action-result tag
        guard let startRange = text.range(of: "<ui-action-result"),
              let endRange = text.range(of: "</ui-action-result>"),
              startRange.upperBound < endRange.lowerBound else {
            return nil
        }

        // Find the closing > of the opening tag
        let afterStartTag = text[startRange.upperBound...]
        guard let closingBracket = afterStartTag.firstIndex(of: ">") else { return nil }

        let jsonStart = afterStartTag.index(after: closingBracket)
        let jsonContent = String(text[jsonStart..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)

        guard let jsonData = jsonContent.data(using: .utf8) else { return nil }
        let json = JSON(jsonData)

        // Check for pdfAttachment with storageUrl
        guard json["pdfAttachment"].exists(),
              let storagePath = json["pdfAttachment"]["storageUrl"].string,
              let pdfData = try? Data(contentsOf: URL(fileURLWithPath: storagePath)) else {
            return nil
        }

        let pdfBase64 = pdfData.base64EncodedString()
        let docSource = AnthropicDocumentSource(mediaType: "application/pdf", data: pdfBase64)
        let filename = json["pdfAttachment"]["filename"].string ?? "resume.pdf"
        Logger.info("📄 Re-including PDF in user message history: \(filename) (\(pdfData.count / 1024) KB)", category: .ai)

        return [.document(AnthropicDocumentBlock(source: docSource))]
    }
}
