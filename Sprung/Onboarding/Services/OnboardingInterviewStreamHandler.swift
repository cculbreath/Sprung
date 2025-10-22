import Foundation

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

        func updateReasoningMessage(with delta: String) {
            let trimmed = delta.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }

            var text = reasoningState?.text ?? ""
            text += (text.isEmpty ? "" : " ") + trimmed
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
                let initialStatus = event.status ?? "Tool call started."
                let messageId = messageManager.appendAssistantMessage("🔧 \(initialStatus)")
                state = ToolStreamState(
                    messageId: messageId,
                    inputBuffer: "",
                    status: initialStatus,
                    isComplete: false
                )
            }

            if let payload = event.payload {
                if event.appendsPayload {
                    state?.inputBuffer += payload
                } else {
                    state?.inputBuffer = payload
                }
            }

            if let status = event.status {
                state?.status = status
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
                        let statusId = messageManager.appendAssistantMessage("ℹ️ \(message)")
                        if isComplete {
                            messageManager.updateMessage(id: statusId, text: "ℹ️ \(message)\n✅ Complete.")
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
