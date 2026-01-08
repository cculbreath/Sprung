//
//  StreamingMessageBuffer.swift
//  Sprung
//
//  Minimal buffer for live UI updates during LLM response streaming.
//  Holds only the current streaming message until finalized to ConversationLog.
//

import Foundation

/// Buffer for the current streaming message during LLM response.
/// ConversationLog is the source of truth for finalized messages.
actor StreamingMessageBuffer {

    /// The current streaming message (nil when not streaming)
    private(set) var currentMessage: OnboardingMessage?

    // MARK: - Streaming Lifecycle

    /// Begin streaming a new message
    func begin(id: UUID, initialText: String) {
        currentMessage = OnboardingMessage(
            id: id,
            role: .assistant,
            text: initialText,
            timestamp: Date()
        )
    }

    /// Append delta text to the current streaming message
    func appendDelta(id: UUID, delta: String) {
        guard var msg = currentMessage, msg.id == id else { return }
        msg.text += delta
        currentMessage = msg
    }

    /// Clear the buffer (message is now finalized in ConversationLog)
    func finalize() {
        currentMessage = nil
    }

    /// Reset the buffer
    func reset() {
        currentMessage = nil
    }
}
