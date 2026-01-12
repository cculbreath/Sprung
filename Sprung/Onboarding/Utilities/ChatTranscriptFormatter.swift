import Foundation
enum ChatTranscriptFormatter {
    static func format(messages: [OnboardingMessage]) -> String {
        guard messages.isEmpty == false else { return "" }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return messages.map { message in
            let timestamp = formatter.string(from: message.timestamp)
            let roleLabel = label(for: message.role)
            // Reasoning summaries now display in dedicated sidebar (not in transcript)
            return "[\(timestamp)] \(roleLabel):\n\(message.text)"
        }
        .joined(separator: "\n\n")
    }
    private static func label(for role: OnboardingMessageRole) -> String {
        switch role {
        case .user:
            return "User"
        case .assistant:
            return "Assistant"
        case .system:
            return "System"
        case .systemNote:
            return "Note"
        }
    }
}
