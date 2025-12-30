//
//  ConversationContextAssembler.swift
//  Sprung
//
//  Phase 3: Rolling conversation context with state cues
//  Assembles conversation history + current state for LLM requests
//
import Foundation
import SwiftyJSON
import SwiftOpenAI
/// Assembles conversation context for LLM requests
/// Includes full conversation history + state cues (allowed tools, objectives, phase)
actor ConversationContextAssembler {
    // MARK: - Properties
    private let state: StateCoordinator
    // MARK: - Initialization
    init(state: StateCoordinator) {
        self.state = state
        Logger.info("📝 ConversationContextAssembler initialized (full conversation history mode)", category: .ai)
    }
    // MARK: - Context Assembly
    /// Build input items for a tool response
    func buildForToolResponse(
        output: JSON,
        callId: String
    ) async -> [InputItem] {
        // OpenAI Responses API with previous_response_id handles reasoning continuity automatically
        // Tool response requests should contain ONLY the function call output
        let outputString = output.rawString() ?? "{}"
        let status = sanitizeToolStatus(output["status"].string)
        let toolOutput = InputItem.functionToolCallOutput(FunctionToolCallOutput(
            callId: callId,
            output: outputString,
            status: status
        ))
        Logger.debug("📦 Assembled tool response: 1 item (status: \(status ?? "nil"))", category: .ai)
        return [toolOutput]
    }
    /// Build input items for batched tool responses (parallel tool calls)
    /// OpenAI API requires all tool outputs from parallel calls to be sent together
    func buildForBatchedToolResponses(payloads: [JSON]) async -> [InputItem] {
        var items: [InputItem] = []
        for payload in payloads {
            let callId = payload["callId"].stringValue
            let output = payload["output"]
            let outputString = output.rawString() ?? "{}"
            let status = sanitizeToolStatus(output["status"].string)
            let toolOutput = InputItem.functionToolCallOutput(FunctionToolCallOutput(
                callId: callId,
                output: outputString,
                status: status
            ))
            items.append(toolOutput)
        }
        Logger.debug("📦 Assembled batched tool responses: \(items.count) items", category: .ai)
        return items
    }
    // MARK: - Private Helpers
    private func sanitizeToolStatus(_ status: String?) -> String? {
        guard let status else { return nil }
        let allowed = ["in_progress", "completed", "incomplete"]
        guard allowed.contains(status) else {
            Logger.warning("⚠️ Tool status '\(status)' not allowed by API; coercing to 'incomplete'", category: .ai)
            return "incomplete"
        }
        return status
    }
    /// Build full conversation history (all messages from the interview)
    /// Used when restoring from checkpoint or starting fresh without previous_response_id
    func buildConversationHistory() async -> [InputItem] {
        let messages = await state.messages
        return messages.compactMap { message -> InputItem? in
            let role: String
            switch message.role {
            case .user:
                role = "user"
            case .assistant:
                role = "assistant"
            case .system:
                // Skip system messages - they're included via system prompt
                return nil
            }
            return .message(InputMessage(
                role: role,
                content: .text(message.text)
            ))
        }
    }

    /// Check if we have conversation history (for determining if this is a fresh start after restore)
    func hasConversationHistory() async -> Bool {
        let messages = await state.messages
        return !messages.isEmpty
    }

    /// Get previous response ID for Responses API threading
    func getPreviousResponseId() async -> String? {
        await state.getPreviousResponseId()
    }
    /// Store previous response ID for Responses API threading
    func storePreviousResponseId(_ responseId: String) async {
        await state.setPreviousResponseId(responseId)
    }
}
