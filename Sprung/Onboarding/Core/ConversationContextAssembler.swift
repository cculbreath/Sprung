//
//  ConversationContextAssembler.swift
//  Sprung
//
//  Assembles conversation history for LLM requests.
//  Flattens ConversationLog wire entries into ConversationHistoryItem order
//  for AnthropicHistoryBuilder.
//
//  PROMPT-CACHE INVARIANT: history must replay byte-identically across requests
//  or prompt caching breaks. This assembler therefore reads the WIRE snapshot
//  from ConversationLog (exact text as sent, including merged <interview_context>
//  / <coordinator> / todo content, chatbox attachments, and the exact tool_result
//  strings as first serialized) rather than the UI-facing display messages.
//

import Foundation

/// One conversation-history item in exact wire order.
/// App-owned intermediate between ConversationLog wire entries and the
/// Anthropic message array built by AnthropicHistoryBuilder.
enum ConversationHistoryItem: Sendable {
    /// User turn text plus optional chatbox attachment (image or PDF).
    case userMessage(text: String, attachment: ConversationLog.WireAttachment?)
    /// Assistant turn text.
    case assistantMessage(text: String)
    /// Assistant tool_use block (arguments are the exact recorded JSON string).
    case toolCall(callId: String, name: String, argumentsJSON: String)
    /// tool_result block content — the exact wire string resolved by
    /// ConversationLog (never a per-build placeholder substitution).
    case toolResult(callId: String, output: String)
}

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

    /// Build full conversation history from ConversationLog wire entries.
    /// ConversationLog guarantees tool results are always present at the wire
    /// level (pending calls carry the recorded placeholder string), maintaining
    /// the Anthropic API invariant that every tool_use needs a tool_result.
    func buildConversationHistory() async -> [ConversationHistoryItem] {
        let wireEntries = await state.getWireConversation()

        var items: [ConversationHistoryItem] = []

        for entry in wireEntries {
            switch entry {
            case .user(let text, let attachment):
                items.append(.userMessage(text: text, attachment: attachment))

            case .assistant(let text, let toolCalls, let toolContextText):
                items.append(.assistantMessage(text: text))

                if let toolCalls {
                    for toolCall in toolCalls {
                        items.append(.toolCall(
                            callId: toolCall.callId,
                            name: toolCall.name,
                            argumentsJSON: toolCall.arguments
                        ))
                        items.append(.toolResult(
                            callId: toolCall.callId,
                            output: toolCall.result
                        ))
                    }
                }

                // Context text appended after this turn's tool_results at send time.
                // Emitted as a user item so it merges into the same tool_result user
                // message downstream — reproducing the wire bytes exactly.
                if let toolContextText {
                    items.append(.userMessage(text: toolContextText, attachment: nil))
                }
            }
        }

        return items
    }
}
