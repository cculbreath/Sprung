import Foundation
import Observation

@MainActor
@Observable
final class ChatTranscriptStore {
    private(set) var messages: [OnboardingMessage] = []

    private var streamingMessageStart: [UUID: Date] = [:]

    func appendUserMessage(_ text: String) {
        messages.append(OnboardingMessage(role: .user, text: text))
    }

    @discardableResult
    func appendAssistantMessage(_ text: String) -> UUID {
        let message = OnboardingMessage(role: .assistant, text: text)
        messages.append(message)
        return message.id
    }

    @discardableResult
    func beginAssistantStream(initialText: String = "") -> UUID {
        let message = OnboardingMessage(role: .assistant, text: initialText)
        messages.append(message)
        streamingMessageStart[message.id] = Date()
        return message.id
    }

    func updateAssistantStream(id: UUID, text: String) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].text = text
    }

    func finalizeAssistantStream(id: UUID, text: String) -> TimeInterval {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return 0 }
        messages[index].text = text
        let elapsed: TimeInterval
        if let start = streamingMessageStart.removeValue(forKey: id) {
            elapsed = Date().timeIntervalSince(start)
        } else {
            elapsed = 0
        }
        return elapsed
    }

    func updateReasoningSummary(_ summary: String, for messageId: UUID, isFinal: Bool) {
        let value = isFinal ? summary.trimmingCharacters(in: .whitespacesAndNewlines) : summary
        guard let index = messages.firstIndex(where: { $0.id == messageId }) else { return }
        messages[index].reasoningSummary = value
    }

    func appendSystemMessage(_ text: String) {
        messages.append(OnboardingMessage(role: .system, text: text))
    }

    func reset() {
        messages.removeAll()
        streamingMessageStart.removeAll()
    }
}
