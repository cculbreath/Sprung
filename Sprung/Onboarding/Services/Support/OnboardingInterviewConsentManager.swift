import Foundation
import SwiftyJSON

@MainActor
final class OnboardingInterviewConsentManager {
    private let appendSystemMessage: (String) -> Void
    private let sendControlMessage: (String, UUID) async -> Void

    init(
        appendSystemMessage: @escaping (String) -> Void,
        sendControlMessage: @escaping (String, UUID) async -> Void
    ) {
        self.appendSystemMessage = appendSystemMessage
        self.sendControlMessage = sendControlMessage
    }

    func handleWebSearchConsent(isAllowed: Bool, conversationId: UUID) async {
        let payload = JSON([
            "type": "web_search_consent",
            "allowed": isAllowed
        ])
        let note = isAllowed ? "✅ Web search enabled for this interview." : "🚫 Web search disabled for this interview."
        appendSystemMessage(note)

        let messageText = payload.rawString(options: [.sortedKeys]) ?? payload.description
        await sendControlMessage(messageText, conversationId)
    }

    func handleWritingAnalysisConsent(isAllowed: Bool, conversationId: UUID) async {
        let payload = JSON([
            "type": "writing_analysis_consent",
            "allowed": isAllowed
        ])
        let messageText = payload.rawString(options: [.sortedKeys]) ?? payload.description
        await sendControlMessage(messageText, conversationId)
    }
}
