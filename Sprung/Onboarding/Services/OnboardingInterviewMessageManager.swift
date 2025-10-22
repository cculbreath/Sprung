import Foundation
import Observation

@MainActor
@Observable
final class OnboardingInterviewMessageManager {
    private(set) var messages: [OnboardingMessage] = []
    private(set) var nextQuestions: [OnboardingQuestion] = []

    func reset() {
        messages.removeAll()
        nextQuestions.removeAll()
    }

    func setNextQuestions(_ questions: [OnboardingQuestion]) {
        nextQuestions = questions
    }

    func appendSystemMessage(_ text: String) {
        messages.append(OnboardingMessage(role: .system, text: text))
    }

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
    func appendAssistantPlaceholder() -> UUID {
        let placeholder = OnboardingMessage(role: .assistant, text: "")
        messages.append(placeholder)
        return placeholder.id
    }

    func updateMessage(id: UUID, text: String) {
        if let index = messages.firstIndex(where: { $0.id == id }) {
            let existing = messages[index]
            messages[index] = OnboardingMessage(
                id: existing.id,
                role: existing.role,
                text: text,
                timestamp: existing.timestamp
            )
        }
    }

    func removeMessage(withId id: UUID) {
        if let index = messages.firstIndex(where: { $0.id == id }) {
            messages.remove(at: index)
        }
    }
}
