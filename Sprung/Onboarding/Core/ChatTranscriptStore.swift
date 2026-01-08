//
//  ChatTranscriptStore.swift
//  Sprung
//
//  Streaming buffer for live UI updates during LLM response streaming.
//  ConversationLog is the source of truth for message history.
//  This store only manages the currently streaming message for display.
//

import Foundation

/// Streaming buffer for live UI updates during LLM response streaming.
/// ConversationLog is the single source of truth for finalized messages.
/// This store only holds the CURRENT streaming message (not history).
actor ChatTranscriptStore {

    // MARK: - Streaming Message State

    /// The current streaming message (nil when not streaming)
    private(set) var currentStreamingMessage: OnboardingMessage?

    // MARK: - Initialization

    init() {
        Logger.info("💬 ChatTranscriptStore initialized (streaming buffer)", category: .ai)
    }

    // MARK: - Streaming Message Management

    /// Begin streaming a message with specific ID
    func beginStreamingMessage(id: UUID, initialText: String) -> UUID {
        currentStreamingMessage = OnboardingMessage(
            id: id,
            role: .assistant,
            text: initialText,
            timestamp: Date()
        )
        return id
    }

    /// Update streaming message with delta
    func updateStreamingMessage(id: UUID, delta: String) {
        guard var streaming = currentStreamingMessage, streaming.id == id else { return }
        streaming.text += delta
        currentStreamingMessage = streaming
    }

    /// Finalize streaming message (clears the buffer - message is now in ConversationLog)
    func finalizeStreamingMessage(id: UUID, finalText: String, toolCalls: [OnboardingMessage.ToolCallInfo]? = nil) {
        // Clear the streaming message - it's now finalized in ConversationLog
        currentStreamingMessage = nil
    }

    /// Check if currently streaming
    var isStreaming: Bool {
        currentStreamingMessage != nil
    }

    /// Get current streaming message ID
    var streamingMessageId: UUID? {
        currentStreamingMessage?.id
    }

    // MARK: - State Management

    /// Reset all state
    func reset() {
        currentStreamingMessage = nil
        Logger.info("🔄 ChatTranscriptStore reset", category: .ai)
    }
}
