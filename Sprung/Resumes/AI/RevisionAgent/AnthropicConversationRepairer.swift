import Foundation
import SwiftOpenAI

// MARK: - Anthropic Conversation Repairer

/// Repairs an Anthropic message history that contains tool_use blocks with
/// no matching tool_result responses. Injects synthetic "cancelled" results
/// so the API accepts the conversation.
struct AnthropicConversationRepairer {
    /// Mutates `messages` in-place, returning true if any repairs were made.
    @discardableResult
    static func repairOrphanedToolUse(in messages: inout [AnthropicMessage]) -> Bool {
        var repaired = false
        var i = 0
        while i < messages.count {
            let msg = messages[i]
            guard msg.role == "assistant" else { i += 1; continue }

            // Collect tool_use IDs from this assistant message
            let toolUseIds: [String]
            switch msg.content {
            case .text:
                i += 1; continue
            case .blocks(let blocks):
                toolUseIds = blocks.compactMap { block in
                    if case .toolUse(let tu) = block { return tu.id }
                    return nil
                }
            }
            guard !toolUseIds.isEmpty else { i += 1; continue }

            // Gather tool_result IDs from the next user message (if it exists)
            let answeredIds: Set<String>
            if i + 1 < messages.count,
               messages[i + 1].role == "user" {
                switch messages[i + 1].content {
                case .text:
                    answeredIds = []
                case .blocks(let blocks):
                    answeredIds = Set(blocks.compactMap { block in
                        if case .toolResult(let tr) = block { return tr.toolUseId }
                        return nil
                    })
                }
            } else {
                answeredIds = []
            }

            let orphaned = toolUseIds.filter { !answeredIds.contains($0) }
            guard !orphaned.isEmpty else { i += 1; continue }

            // Build synthetic tool_result blocks for orphaned IDs
            let syntheticBlocks: [AnthropicContentBlock] = orphaned.map { id in
                .toolResult(AnthropicToolResultBlock(
                    toolUseId: id,
                    content: "{\"cancelled\": true, \"reason\": \"Request interrupted by user\"}",
                    isError: true
                ))
            }

            if i + 1 < messages.count,
               messages[i + 1].role == "user" {
                // Prepend synthetic results into the existing user message
                switch messages[i + 1].content {
                case .text(let text):
                    var blocks = syntheticBlocks
                    blocks.append(.text(AnthropicTextBlock(text: text)))
                    messages[i + 1] = AnthropicMessage(
                        role: "user", content: .blocks(blocks)
                    )
                case .blocks(var blocks):
                    blocks.insert(contentsOf: syntheticBlocks, at: 0)
                    messages[i + 1] = AnthropicMessage(
                        role: "user", content: .blocks(blocks)
                    )
                }
            } else {
                // No user message follows — insert one with the synthetic results
                messages.insert(
                    AnthropicMessage(role: "user", content: .blocks(syntheticBlocks)),
                    at: i + 1
                )
            }

            Logger.warning(
                "RevisionAgent: Repaired \(orphaned.count) orphaned tool_use ID(s) at message \(i)",
                category: .ai
            )
            repaired = true
            i += 2 // skip both the assistant and the (now-repaired) user message
        }

        if repaired {
            Logger.info("RevisionAgent: Conversation repaired before API call", category: .ai)
        }

        return repaired
    }
}
