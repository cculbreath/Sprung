//
//  AnthropicMessageValidator.swift
//  Sprung
//
//  Validates Anthropic message structure and provides debugging utilities.
//  Extracted from AnthropicRequestBuilder for single responsibility.
//

import Foundation
import SwiftOpenAI

/// Validates Anthropic message structure and provides debugging utilities
enum AnthropicMessageValidator {

    // MARK: - Validation

    /// Validates that messages follow Anthropic's requirements:
    /// 1. Must start with user message
    /// 2. Must alternate between user and assistant roles
    /// 3. No consecutive messages of the same role
    static func validateMessageStructure(_ messages: [AnthropicMessage]) {
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

    // MARK: - Debugging

    /// Dump full message structure for debugging API errors
    static func logMessageDump(_ messages: [AnthropicMessage], label: String) {
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

    /// Get a summary of message content for debugging
    static func getContentSummary(_ message: AnthropicMessage) -> String? {
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
}
