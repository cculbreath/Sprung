import Foundation

@MainActor
final class OnboardingInterviewMessageManager {
    // Callbacks to update service's observable properties
    private let onMessagesChanged: ([OnboardingMessage]) -> Void
    private let onNextQuestionsChanged: ([OnboardingQuestion]) -> Void

    private var messages: [OnboardingMessage] = []
    private var nextQuestions: [OnboardingQuestion] = []

    init(
        onMessagesChanged: @escaping ([OnboardingMessage]) -> Void,
        onNextQuestionsChanged: @escaping ([OnboardingQuestion]) -> Void
    ) {
        self.onMessagesChanged = onMessagesChanged
        self.onNextQuestionsChanged = onNextQuestionsChanged
    }

    func reset() {
        messages.removeAll()
        nextQuestions.removeAll()
        onMessagesChanged(messages)
        onNextQuestionsChanged(nextQuestions)
    }

    func setNextQuestions(_ questions: [OnboardingQuestion]) {
        nextQuestions = questions
        onNextQuestionsChanged(nextQuestions)
    }

    func appendSystemMessage(_ text: String) {
        messages.append(
            OnboardingMessage(
                role: .system,
                text: normalized(text, for: .system)
            )
        )
        onMessagesChanged(messages)
    }

    func appendUserMessage(_ text: String) {
        messages.append(OnboardingMessage(role: .user, text: text))
        onMessagesChanged(messages)
    }

    @discardableResult
    func appendAssistantMessage(_ text: String) -> UUID {
        let message = OnboardingMessage(
            role: .assistant,
            text: normalized(text, for: .assistant)
        )
        messages.append(message)
        onMessagesChanged(messages)
        return message.id
    }

    @discardableResult
    func appendAssistantPlaceholder() -> UUID {
        let placeholder = OnboardingMessage(
            role: .assistant,
            text: normalized("", for: .assistant)
        )
        messages.append(placeholder)
        onMessagesChanged(messages)
        return placeholder.id
    }

    func updateMessage(id: UUID, text: String) {
        if let index = messages.firstIndex(where: { $0.id == id }) {
            let existing = messages[index]
            messages[index] = OnboardingMessage(
                id: existing.id,
                role: existing.role,
                text: normalized(text, for: existing.role),
                timestamp: existing.timestamp
            )
            onMessagesChanged(messages)
        }
    }

    func removeMessage(withId id: UUID) {
        if let index = messages.firstIndex(where: { $0.id == id }) {
            messages.remove(at: index)
            onMessagesChanged(messages)
        }
    }

    private func normalized(_ text: String, for role: OnboardingMessage.Role) -> String {
        guard role != .user else { return text }
        return text
            .replacingOccurrences(of: "\\r\\n", with: "\n")
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\t", with: "\t")
    }
}
