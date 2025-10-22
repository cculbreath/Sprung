import Foundation
import SwiftyJSON

@MainActor
final class OnboardingInterviewStreamHandler {
    private let messageManager: OnboardingInterviewMessageManager

    init(messageManager: OnboardingInterviewMessageManager) {
        self.messageManager = messageManager
    }

    func streamAssistantResponse(from handle: LLMStreamingHandle) async throws -> (String, UUID) {
        let mainMessageId = messageManager.appendAssistantPlaceholder()
        var accumulatedText = ""

        var reasoningState: (id: UUID, text: String)?
    struct ToolStreamState {
        var messageId: UUID
        var inputBuffer: String
        var status: String
        var isComplete: Bool
        var toolName: String?
    }
    var toolStates: [String: ToolStreamState] = [:]
    var completedToolCalls: [[String: Any]] = []

        func sanitizeStreamText(_ raw: String) -> String {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return "" }

            let json = JSON(parseJSON: trimmed)
            guard json.type != .unknown else { return trimmed }

            let flattened = flattenStreamJSON(json)
            let joined = flattened.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            return joined.isEmpty ? trimmed : joined
        }

        func flattenStreamJSON(_ json: JSON) -> [String] {
            switch json.type {
            case .string:
                let value = json.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? [] : [value]
            case .number:
                return [json.numberValue.stringValue]
            case .bool:
                return [json.boolValue ? "true" : "false"]
            case .array:
                return json.arrayValue.flatMap { flattenStreamJSON($0) }
            case .dictionary:
                let dictionary = json.dictionaryValue
                if dictionary.keys.count == 1, let nested = dictionary["json_keys"] {
                    return flattenStreamJSON(nested)
                }
                return dictionary
                    .sorted(by: { $0.key < $1.key })
                    .flatMap { key, value -> [String] in
                        let flattened = flattenStreamJSON(value)
                        guard !flattened.isEmpty else { return [] }
                        if flattened.count == 1, !flattened[0].contains("\n") {
                            return ["\(key.capitalized): \(flattened[0])"]
                        } else {
                            var result: [String] = ["\(key.capitalized):"]
                            result.append(contentsOf: flattened.map { "• \($0)" })
                            return result
                        }
                    }
            default:
                return []
            }
        }

        func updateReasoningMessage(with delta: String) {
            let trimmed = sanitizeStreamText(delta)
            guard !trimmed.isEmpty else { return }

            var text = reasoningState?.text ?? ""
            text += text.isEmpty ? trimmed : "\n\(trimmed)"
            let messageId = reasoningState?.id ?? messageManager.appendAssistantMessage("🧠 \(text)")

            messageManager.updateMessage(id: messageId, text: "🧠 \(text)")
            reasoningState = (messageId, text)
        }

        func finalizeReasoningIfNeeded() {
            guard let state = reasoningState else { return }
            if !state.text.isEmpty {
                let display = "🧠 \(state.text)\n✅ Reasoning complete."
                messageManager.updateMessage(id: state.id, text: display)
            }
        }

        func recordCompletedToolCall(callId: String, state: ToolStreamState) {
            let argsString = state.inputBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !argsString.isEmpty else { return }

            if let data = argsString.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) {
                let entry: [String: Any] = [
                    "id": callId,
                    "tool": state.toolName ?? "unknown",
                    "arguments": object,
                    "args": object
                ]
                completedToolCalls.append(entry)
            } else {
                completedToolCalls.append([
                    "id": callId,
                    "tool": state.toolName ?? "unknown",
                    "arguments": argsString,
                    "args": argsString
                ])
            }
        }

        func updateToolMessage(for event: LLMToolStreamEvent) {
            var state = toolStates[event.callId]
            if state == nil {
                let displayMsg = event.toolName.flatMap { OnboardingToolCatalog.displayMessage(for: $0) }
                var messageId: UUID? = nil
                if let displayMsg {
                    messageId = messageManager.appendAssistantMessage(displayMsg)
                }
                state = ToolStreamState(
                    messageId: messageId ?? UUID(),
                    inputBuffer: "",
                    status: "",
                    isComplete: false,
                    toolName: event.toolName
                )
            }

            if let toolName = event.toolName {
                state?.toolName = toolName
            }

            if let payload = event.payload {
                if event.appendsPayload {
                    if !payload.isEmpty {
                        if let buffer = state?.inputBuffer, !buffer.isEmpty {
                            state?.inputBuffer += payload
                        } else {
                            state?.inputBuffer = payload
                        }
                    }
                } else {
                    state?.inputBuffer = payload
                }
            }

            if event.isComplete {
                state?.isComplete = true
                if let finalState = state {
                    recordCompletedToolCall(callId: event.callId, state: finalState)
                }
            }

            if let state {
                toolStates[event.callId] = state
            }
        }

        func finalizeToolMessages() {
            for (id, state) in toolStates {
                if state.isComplete {
                    continue
                }
                var updated = state
                updated.isComplete = true
                toolStates[id] = updated
            }
        }

        do {
            for try await chunk in handle.stream {
                if let event = chunk.event {
                    switch event {
                    case .tool(let toolEvent):
                        updateToolMessage(for: toolEvent)
                    case .status(let message, let isComplete):
                        let cleanedMessage = sanitizeStreamText(message)
                        let statusText = cleanedMessage.isEmpty ? message : cleanedMessage
                        let statusId = messageManager.appendAssistantMessage("ℹ️ \(statusText)")
                        if isComplete {
                            messageManager.updateMessage(id: statusId, text: "ℹ️ \(statusText)\n✅ Complete.")
                        }
                    }
                }

                if let reasoning = chunk.reasoning {
                    updateReasoningMessage(with: reasoning)
                }

                if let content = chunk.content, !content.isEmpty {
                    let cleanedContent = stripJSONFormatting(from: content)
                    if !cleanedContent.isEmpty {
                        accumulatedText += cleanedContent
                        messageManager.updateMessage(id: mainMessageId, text: accumulatedText)
                    }
                }

                if chunk.isFinished {
                    finalizeReasoningIfNeeded()
                    finalizeToolMessages()
                }
            }
        } catch {
            messageManager.removeMessage(withId: mainMessageId)
            if let state = reasoningState {
                messageManager.removeMessage(withId: state.id)
            }
            throw error
        }

        if accumulatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !completedToolCalls.isEmpty {
            let responseDict: [String: Any] = [
                "assistant_reply": "",
                "tool_calls": completedToolCalls
            ]
            if let data = try? JSONSerialization.data(withJSONObject: responseDict),
               let jsonString = String(data: data, encoding: .utf8) {
                accumulatedText = jsonString
            }
        }

        return (accumulatedText, mainMessageId)
    }

    private func formatToolPayload(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let maxLength = 600
        if trimmed.count <= maxLength {
            return trimmed
        }
        let index = trimmed.index(trimmed.startIndex, offsetBy: maxLength)
        return String(trimmed[..<index]) + "…"
    }

    private func stripJSONFormatting(from text: String) -> String {
        var cleaned = text

        if cleaned.hasPrefix("\"") && cleaned.hasSuffix("\"") && cleaned.count > 1 {
            cleaned = String(cleaned.dropFirst().dropLast())
        }

        if cleaned.hasPrefix("{\"assistant_reply\":\"") {
            cleaned = cleaned
                .replacingOccurrences(of: "{\"assistant_reply\":\"", with: "")
                .replacingOccurrences(of: "\"}", with: "")
        }

        if cleaned.hasPrefix("{\"text\":\"") {
            cleaned = cleaned
                .replacingOccurrences(of: "{\"text\":\"", with: "")
                .replacingOccurrences(of: "\"}", with: "")
        }

        cleaned = cleaned
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\t", with: "\t")
            .replacingOccurrences(of: "\\\"", with: "\"")

        return cleaned
    }
}
