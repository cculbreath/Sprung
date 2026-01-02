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
    /// For Anthropic: includes tool calls AND their results (tool_use + tool_result pairs)
    /// Implements ephemeral pruning: tool results with `expiry_turn` are replaced with
    /// placeholders after that turn is reached.
    func buildConversationHistory() async -> [InputItem] {
        let messages = await state.messages

        // Fallback: Get completed tool results from legacy storage (for backwards compatibility)
        let completedResults = await state.getCompletedToolResults()
        let legacyResultsByCallId = Dictionary(uniqueKeysWithValues: completedResults.map { ($0.callId, $0.output) })

        // Calculate current turn number for ephemeral pruning
        // Turn = count of assistant messages that have tool calls
        let currentTurn = messages.filter { $0.role == .assistant && !($0.toolCalls?.isEmpty ?? true) }.count

        return messages.flatMap { message -> [InputItem] in
            let role: String
            switch message.role {
            case .user:
                role = "user"
            case .assistant:
                role = "assistant"
            case .system:
                // Skip system messages - they're included via system prompt
                return []
            }

            var items: [InputItem] = []

            // Add the text message
            items.append(.message(InputMessage(
                role: role,
                content: .text(message.text)
            )))

            // For assistant messages, also include any tool calls AND their results
            // This is critical for Anthropic which requires tool_use before tool_result
            if role == "assistant", let toolCalls = message.toolCalls {
                for toolCall in toolCalls {
                    items.append(.functionToolCall(FunctionToolCall(
                        arguments: toolCall.arguments,
                        callId: toolCall.id,
                        name: toolCall.name
                    )))
                    Logger.debug("📝 Including tool call in history: \(toolCall.name) (id: \(toolCall.id))", category: .ai)

                    // Get the output (prefer paired storage, fall back to legacy)
                    let output = toolCall.result ?? legacyResultsByCallId[toolCall.id]

                    if let output = output {
                        // Check for ephemeral pruning using expiry_turn
                        let expiryTurn = getExpiryTurn(from: output)
                        if let expiryTurn = expiryTurn, currentTurn > expiryTurn {
                            // Create a pruned placeholder instead of the full content
                            let prunedOutput = createPrunedPlaceholder(toolName: toolCall.name, originalOutput: output)
                            items.append(.functionToolCallOutput(FunctionToolCallOutput(
                                callId: toolCall.id,
                                output: prunedOutput,
                                status: nil
                            )))
                            Logger.debug("🧹 Pruned ephemeral result: \(toolCall.name) (expiry=\(expiryTurn), current=\(currentTurn))", category: .ai)
                            continue
                        }

                        // Include the result (strip ephemeral metadata)
                        let cleanedOutput = stripEphemeralMetadata(from: output)
                        items.append(.functionToolCallOutput(FunctionToolCallOutput(
                            callId: toolCall.id,
                            output: cleanedOutput,
                            status: nil
                        )))
                        Logger.debug("📝 Including tool result: \(toolCall.name) (id: \(toolCall.id))", category: .ai)
                    } else {
                        Logger.warning("⚠️ No result found for tool call: \(toolCall.name) (id: \(toolCall.id))", category: .ai)
                    }
                }
            }

            return items
        }
    }

    // MARK: - Ephemeral Pruning Helpers

    /// Get expiry_turn from tool result if it's an ephemeral result
    /// Returns nil if not ephemeral or no expiry_turn set
    private func getExpiryTurn(from output: String) -> Int? {
        guard let data = output.data(using: .utf8) else { return nil }
        let json = JSON(data)
        guard json["ephemeral"].boolValue else { return nil }
        let expiryTurn = json["expiry_turn"].int
        return expiryTurn
    }

    /// Strip ephemeral metadata fields from output before including in history
    private func stripEphemeralMetadata(from output: String) -> String {
        guard let data = output.data(using: .utf8) else { return output }
        var json = JSON(data)
        // Remove internal control fields
        json["ephemeral"] = JSON.null
        json["expiry_turn"] = JSON.null
        return json.rawString() ?? output
    }

    /// Create a compact placeholder for pruned ephemeral content
    private func createPrunedPlaceholder(toolName: String, originalOutput: String) -> String {
        guard let data = originalOutput.data(using: .utf8) else {
            return "{\"status\":\"pruned\",\"reason\":\"ephemeral content expired\"}"
        }
        let json = JSON(data)

        // Build a minimal placeholder preserving key metadata
        var placeholder = JSON()
        placeholder["status"].string = "pruned"
        placeholder["reason"].string = "ephemeral content expired - file contents removed from context"

        // Preserve useful metadata without the large content
        if let path = json["path"].string {
            placeholder["path"].string = path
        }
        if let totalLines = json["total_lines"].int {
            placeholder["total_lines"].int = totalLines
        }
        if let matchCount = json["match_count"].int {
            placeholder["match_count"].int = matchCount
        }
        if let fileCount = json["file_count"].int {
            placeholder["file_count"].int = fileCount
        }

        return placeholder.rawString() ?? "{\"status\":\"pruned\"}"
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
