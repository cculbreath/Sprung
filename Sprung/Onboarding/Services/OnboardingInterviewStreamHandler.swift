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
        }
        var toolStates: [String: ToolStreamState] = [:]

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
                var dictionary = json.dictionaryValue
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

        func updateToolMessage(for event: LLMToolStreamEvent) {
            var state = toolStates[event.callId]
            if state == nil {
                let initialStatusRaw = event.status ?? "Tool call started."
                let initialStatus = sanitizeStreamText(initialStatusRaw)
                let statusText = initialStatus.isEmpty ? initialStatusRaw : initialStatus
                let messageId = messageManager.appendAssistantMessage("🔧 Tool \(event.callId)\n\(statusText)")
                state = ToolStreamState(
                    messageId: messageId,
                    inputBuffer: "",
                    status: statusText,
                    isComplete: false
                )
            }

            if let payload = event.payload {
                let cleanedPayload = sanitizeStreamText(payload)
                if !cleanedPayload.isEmpty {
                    if event.appendsPayload {
                        if let buffer = state?.inputBuffer, !buffer.isEmpty {
                            state?.inputBuffer += "\n"
                        }
                        state?.inputBuffer += cleanedPayload
                    } else {
                        state?.inputBuffer = cleanedPayload
                    }
                }
            }

            if let status = event.status {
                let cleanedStatus = sanitizeStreamText(status)
                state?.status = cleanedStatus.isEmpty ? status : cleanedStatus
            }

            if event.isComplete {
                state?.isComplete = true
            }

            if let state {
                var display = "🔧 Tool \(event.callId)"
                display += "\n\(state.status)"
                if !state.inputBuffer.isEmpty {
                    let preview = formatToolPayload(state.inputBuffer)
                    if !preview.isEmpty {
                        display += "\n" + preview
                    }
                }
                if state.isComplete {
                    display += "\n✅ Tool complete."
                }
                messageManager.updateMessage(id: state.messageId, text: display)
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
                var display = "🔧 Tool \(id)"
                display += "\n\(state.status)"
                if !state.inputBuffer.isEmpty {
                    let preview = formatToolPayload(state.inputBuffer)
                    if !preview.isEmpty {
                        display += "\n" + preview
                    }
                }
                display += "\n✅ Tool complete."
                messageManager.updateMessage(id: state.messageId, text: display)
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
                    accumulatedText += content
                    messageManager.updateMessage(id: mainMessageId, text: accumulatedText)
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
            for state in toolStates.values {
                messageManager.removeMessage(withId: state.messageId)
            }
            throw error
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
}
