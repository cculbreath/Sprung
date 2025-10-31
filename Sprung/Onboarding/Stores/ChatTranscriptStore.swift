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
    func appendAssistantMessage(_ text: String, reasoningExpected: Bool = false) -> UUID {
        let message = OnboardingMessage(
            role: .assistant,
            text: text,
            reasoningSummary: nil,
            isAwaitingReasoningSummary: reasoningExpected,
            showReasoningPlaceholder: false
        )
        messages.append(message)
        return message.id
    }

    @discardableResult
    func beginAssistantStream(initialText: String = "", reasoningExpected: Bool = false) -> UUID {
        let message = OnboardingMessage(
            role: .assistant,
            text: initialText,
            reasoningSummary: nil,
            isAwaitingReasoningSummary: reasoningExpected,
            showReasoningPlaceholder: false
        )
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
        messages[index].showReasoningPlaceholder = false
        messages[index].isAwaitingReasoningSummary = !isFinal
        if isFinal {
            Logger.info("🧠 Reasoning summary attached (len: \(value.count)) for message \(messageId.uuidString)", category: .ai)
        }
    }

    func appendSystemMessage(_ text: String) {
        messages.append(OnboardingMessage(role: .system, text: text))
    }

    func reset() {
        messages.removeAll()
        streamingMessageStart.removeAll()
    }

    func finalizeReasoningSummariesIfNeeded(for messageIds: [UUID]) {
        guard !messageIds.isEmpty else { return }
        for id in messageIds {
            guard let index = messages.firstIndex(where: { $0.id == id }) else { continue }
            if messages[index].isAwaitingReasoningSummary {
                messages[index].isAwaitingReasoningSummary = false
                messages[index].showReasoningPlaceholder = true
                Logger.info("ℹ️ Reasoning summary unavailable for message \(id.uuidString)", category: .ai)
            }
        }
    }

    func formattedTranscript() -> String {
        ChatTranscriptFormatter.format(messages: messages)
    }
}
