import Foundation
import Observation

/// Sync cache for chat transcript display in UI
/// NOTE: This is NOT the single source of truth. StateCoordinator.messages is authoritative.
/// TODO: Replace with direct StateCoordinator access in UI (requires SwiftUI actor support)
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
            showReasoningPlaceholder: reasoningExpected
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
            showReasoningPlaceholder: reasoningExpected
        )
        messages.append(message)
        streamingMessageStart[message.id] = Date()
        return message.id
    }

    func updateAssistantStream(id: UUID, text: String) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        var message = messages[index]
        message.text = text
        messages[index] = message
    }

    func finalizeAssistantStream(id: UUID, text: String) -> TimeInterval {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return 0 }
        var message = messages[index]
        message.text = text
        messages[index] = message
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
        var message = messages[index]
        message.reasoningSummary = value
        message.showReasoningPlaceholder = false
        message.isAwaitingReasoningSummary = !isFinal
        messages[index] = message
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
            var message = messages[index]
            if message.isAwaitingReasoningSummary {
                message.isAwaitingReasoningSummary = false
                message.showReasoningPlaceholder = false
                messages[index] = message
                Logger.info("ℹ️ Reasoning summary unavailable for message \(id.uuidString)", category: .ai)
            }
        }
    }

    func formattedTranscript() -> String {
        ChatTranscriptFormatter.format(messages: messages)
    }

    // MARK: - Sync from StateCoordinator

    /// Sync messages from StateCoordinator (single source of truth)
    /// This maintains the sync cache for UI display
    func syncFromState(messages stateMessages: [OnboardingMessage]) {
        self.messages = stateMessages
        Logger.debug("💬 ChatTranscriptStore synced \(stateMessages.count) messages from StateCoordinator", category: .ai)
    }
}
