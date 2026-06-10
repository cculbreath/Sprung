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
//  PROMPT-CACHE INVARIANT: history must replay byte-identically across requests
//  or prompt caching breaks. The input items come from ConversationLog's WIRE
//  snapshot (exact merged text as sent). Nothing here may inject content that
//  varies between requests for the same logged turn: PDF re-inclusion is
//  deterministic (same file -> same base64), chatbox attachments replay from the
//  recorded base64 in their original position (text block first, then
//  attachment), tool_use input parsing is deterministic, and message merging is
//  order-stable.
//
//  ACCEPTANCE INVARIANT: building the same request twice with no new
//  ConversationLog entries must produce byte-identical messages JSON; building
//  turn N+1 must reproduce turn N's messages as an exact prefix (modulo
//  cache_control placement, which the API ignores for prefix matching).
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
        let historyItems = await contextAssembler.buildConversationHistory()

        var messages: [AnthropicMessage] = []
        var pendingAssistantBlocks: [AnthropicContentBlock] = []

        /// Helper to flush pending assistant blocks as a single message
        func flushAssistantBlocks() {
            guard !pendingAssistantBlocks.isEmpty else { return }
            messages.append(AnthropicMessage(role: "assistant", content: .blocks(pendingAssistantBlocks)))
            pendingAssistantBlocks = []
        }

        for item in historyItems {
            switch item {
            case .userMessage(let text, let attachment):
                flushAssistantBlocks()
                guard !text.isEmpty || attachment != nil else {
                    Logger.warning("⚠️ Skipping empty user message in Anthropic history", category: .ai)
                    continue
                }

                // Block order is fixed and matches the original send: text block
                // first, then ui-action-result PDF re-inclusion, then the chatbox
                // attachment recorded at send time. A turn must never carry both a
                // ui-action PDF marker AND a recorded chatbox attachment — producers
                // of pdfAttachment.storageUrl markers (DocumentArtifactHandler.
                // sendPDFDirectlyToLLM) must not also set payload["pdfData"], or the
                // document would be sent twice on every request.
                var contentBlocks: [AnthropicContentBlock] = []
                if !text.isEmpty {
                    contentBlocks.append(.text(AnthropicTextBlock(text: text)))
                }
                if let pdfBlocks = extractPDFFromUserMessage(text) {
                    contentBlocks.append(contentsOf: pdfBlocks)
                }
                if let attachment {
                    contentBlocks.append(attachmentBlock(for: attachment))
                }

                if contentBlocks.count == 1, case .text = contentBlocks[0] {
                    messages.append(.user(text))
                } else {
                    messages.append(AnthropicMessage(role: "user", content: .blocks(contentBlocks)))
                }

            case .assistantMessage(let text):
                guard !text.isEmpty else {
                    Logger.debug("📝 Skipping empty assistant text block", category: .ai)
                    continue
                }
                pendingAssistantBlocks.append(.text(AnthropicTextBlock(text: text)))

            case .toolCall(let callId, let name, let argumentsJSON):
                pendingAssistantBlocks.append(.toolUse(AnthropicToolUseBlock(
                    id: callId,
                    name: name,
                    input: Self.deterministicToolInput(fromArgumentsJSON: argumentsJSON)
                )))

            case .toolResult(let callId, let output):
                flushAssistantBlocks()
                // `output` is the exact recorded wire string (ConversationLog
                // substitutes placeholders/empty outputs at recording time) —
                // serialize it verbatim.
                var contentBlocks: [AnthropicContentBlock] = [
                    .toolResult(AnthropicToolResultBlock(toolUseId: callId, content: output))
                ]

                // Check for PDF attachment that needs to be re-included
                if let outputData = output.data(using: .utf8) {
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

    // MARK: - Chatbox Attachment Replay

    /// Build the content block for a recorded chatbox attachment.
    /// Shared by the replay path (above) and the request builder's defensive
    /// fallback path so send and replay always produce identical block shapes.
    func attachmentBlock(for attachment: ConversationLog.WireAttachment) -> AnthropicContentBlock {
        if attachment.mediaType == "application/pdf" {
            let source = AnthropicDocumentSource(mediaType: attachment.mediaType, data: attachment.base64Data)
            return .document(AnthropicDocumentBlock(source: source))
        }
        let source = AnthropicImageSource(mediaType: attachment.mediaType, data: attachment.base64Data)
        return .image(AnthropicImageBlock(source: source))
    }

    // MARK: - Deterministic Tool Input

    /// Parse a recorded tool_use arguments string into the input dictionary,
    /// deterministically.
    ///
    /// PROMPT-CACHE INVARIANT: identical recorded arguments must yield identical
    /// wire bytes on every rebuild. The recorded string never changes for a turn;
    /// we additionally round-trip through JSONSerialization with .sortedKeys so
    /// the dictionary is always constructed from the same canonical bytes in the
    /// same insertion order, making the encoded key order stable across rebuilds
    /// within a process. (Cross-process order may differ with Swift's per-process
    /// hash seed, but the wire side tables — and the 5-minute prompt cache — never
    /// survive a restart, so only within-process stability matters.)
    static func deterministicToolInput(fromArgumentsJSON argumentsJSON: String) -> [String: Any] {
        guard let argsData = argumentsJSON.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: argsData) as? [String: Any] else {
            return [:]
        }
        guard let canonicalData = try? JSONSerialization.data(withJSONObject: parsed, options: [.sortedKeys]),
              let canonical = try? JSONSerialization.jsonObject(with: canonicalData) as? [String: Any] else {
            return parsed
        }
        return canonical
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
