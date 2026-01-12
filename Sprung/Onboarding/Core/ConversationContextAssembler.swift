//
//  ConversationContextAssembler.swift
//  Sprung
//
//  Assembles conversation history for LLM requests.
//  Converts ConversationLog entries to InputItem format for Anthropic API.
//

import Foundation
import SwiftyJSON
import SwiftOpenAI

/// Assembles conversation context for LLM requests
/// Includes full conversation history from ConversationLog
actor ConversationContextAssembler {
    // MARK: - Properties
    private let state: StateCoordinator

    // MARK: - Initialization
    init(state: StateCoordinator) {
        self.state = state
        Logger.info("📝 ConversationContextAssembler initialized", category: .ai)
    }

    // MARK: - Context Assembly

    /// Build full conversation history from ConversationLog
    /// ConversationLog guarantees tool results are always present (gated appending)
    func buildConversationHistory() async -> [InputItem] {
        let messages = await state.messages

        return messages.flatMap { message -> [InputItem] in
            let role: String
            switch message.role {
            case .user:
                role = "user"
            case .assistant:
                role = "assistant"
            case .system, .systemNote:
                // Skip system messages and notes - they're for UI display only
                return []
            }

            var items: [InputItem] = []

            // Add the text message
            items.append(.message(InputMessage(
                role: role,
                content: .text(message.text)
            )))

            // For assistant messages, include tool calls and their results
            // ConversationLog guarantees all results are present for historical entries.
            // CRITICAL: For the current turn, pending results MUST have a placeholder
            // to maintain Anthropic API invariant (every tool_use needs a tool_result).
            if role == "assistant", let toolCalls = message.toolCalls {
                for toolCall in toolCalls {
                    items.append(.functionToolCall(FunctionToolCall(
                        arguments: toolCall.arguments,
                        callId: toolCall.id,
                        name: toolCall.name
                    )))

                    // Always add a tool_result - use actual result or placeholder
                    let output = toolCall.result ?? #"{"status":"pending","reason":"Tool execution in progress"}"#
                    items.append(.functionToolCallOutput(FunctionToolCallOutput(
                        callId: toolCall.id,
                        output: output,
                        status: nil
                    )))

                    if toolCall.result == nil {
                        Logger.debug("📝 Tool call pending result (using placeholder): \(toolCall.name) (id: \(toolCall.id))", category: .ai)
                    }
                }
            }

            return items
        }
    }

    /// Check if we have conversation history
    func hasConversationHistory() async -> Bool {
        let messages = await state.messages
        return !messages.isEmpty
    }
}
