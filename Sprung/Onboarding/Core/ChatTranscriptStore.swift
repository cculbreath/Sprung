import Foundation
import SwiftyJSON
/// Domain service for chat message history and streaming state.
/// Owns all message state including streaming messages and reasoning summaries.
actor ChatTranscriptStore: OnboardingEventEmitter {
    // MARK: - Event System
    let eventBus: EventCoordinator
    // MARK: - Message Storage
    private(set) var messages: [OnboardingMessage] = []
    private(set) var streamingMessage: StreamingMessage?
    private(set) var latestReasoningSummary: String?
    private(set) var previousResponseId: String?  // For Responses API threading
    struct StreamingMessage {
        let id: UUID
        var text: String
        var reasoningExpected: Bool
    }
    // MARK: - Reasoning Summary (Sidebar Display)
    private(set) var currentReasoningSummary: String?
    private(set) var isReasoningActive = false
    // MARK: - Synchronous Caches (for SwiftUI)
    nonisolated(unsafe) private(set) var messagesSync: [OnboardingMessage] = []
    nonisolated(unsafe) private(set) var streamingMessageSync: StreamingMessage?
    nonisolated(unsafe) private(set) var currentReasoningSummarySync: String?
    nonisolated(unsafe) private(set) var isReasoningActiveSync = false
    // MARK: - Initialization
    init(eventBus: EventCoordinator) {
        self.eventBus = eventBus
        Logger.info("💬 ChatTranscriptStore initialized", category: .ai)
    }
    // MARK: - Message Management
    /// Append user message
    func appendUserMessage(_ text: String, isSystemGenerated: Bool = false) -> UUID {
        let message = OnboardingMessage(
            id: UUID(),
            role: .user,
            text: text,
            timestamp: Date(),
            isSystemGenerated: isSystemGenerated
        )
        messages.append(message)
        messagesSync = messages
        return message.id
    }
    /// Append assistant message
    func appendAssistantMessage(_ text: String) -> UUID {
        let message = OnboardingMessage(
            id: UUID(),
            role: .assistant,
            text: text,
            timestamp: Date()
        )
        messages.append(message)
        messagesSync = messages
        return message.id
    }
    /// Get all messages
    func getAllMessages() -> [OnboardingMessage] {
        messages
    }
    /// Get message count
    func getMessageCount() -> Int {
        messages.count
    }

    /// Remove a message by ID (used when message send fails)
    func removeMessage(id: UUID) -> OnboardingMessage? {
        guard let index = messages.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        let removed = messages.remove(at: index)
        messagesSync = messages
        Logger.info("🗑️ Removed message \(id) from transcript", category: .ai)
        return removed
    }
    // MARK: - Responses API Threading
    /// Set previous response ID for Responses API threading
    func setPreviousResponseId(_ responseId: String?) {
        previousResponseId = responseId
        // Emit event for persistence
        Task {
            await eventBus.publish(.llmResponseIdUpdated(responseId: responseId))
        }
    }
    /// Get previous response ID
    func getPreviousResponseId() -> String? {
        previousResponseId
    }
    // MARK: - Streaming Message Management
    /// Begin streaming a new message
    func beginStreamingMessage(initialText: String, reasoningExpected: Bool) -> UUID {
        let id = UUID()
        return beginStreamingMessage(id: id, initialText: initialText, reasoningExpected: reasoningExpected)
    }
    /// Begin streaming a message with specific ID
    func beginStreamingMessage(id: UUID, initialText: String, reasoningExpected: Bool) -> UUID {
        streamingMessage = StreamingMessage(
            id: id,
            text: initialText,
            reasoningExpected: reasoningExpected
        )
        streamingMessageSync = streamingMessage
        let message = OnboardingMessage(
            id: id,
            role: .assistant,
            text: initialText,
            timestamp: Date()
        )
        messages.append(message)
        messagesSync = messages
        return id
    }
    /// Update streaming message with delta
    func updateStreamingMessage(id: UUID, delta: String) {
        guard var streaming = streamingMessage, streaming.id == id else { return }
        streaming.text += delta
        streamingMessage = streaming
        streamingMessageSync = streaming
        if let index = messages.firstIndex(where: { $0.id == id }) {
            messages[index].text += delta
            messagesSync = messages
        }
    }
    /// Finalize streaming message
    func finalizeStreamingMessage(id: UUID, finalText: String, toolCalls: [OnboardingMessage.ToolCallInfo]? = nil) {
        streamingMessage = nil
        streamingMessageSync = nil
        if let index = messages.firstIndex(where: { $0.id == id }) {
            messages[index].text = finalText
            messages[index].toolCalls = toolCalls
            messagesSync = messages
        }
    }
    /// Get current streaming message
    func getStreamingMessage() -> StreamingMessage? {
        streamingMessage
    }
    // MARK: - Reasoning Summary (Sidebar Display)
    /// Update the current reasoning summary for sidebar display (ChatGPT-style)
    func updateReasoningSummary(delta: String) {
        if currentReasoningSummary == nil {
            currentReasoningSummary = delta
            isReasoningActive = true
        } else {
            currentReasoningSummary! += delta
        }
        // Update sync caches
        currentReasoningSummarySync = currentReasoningSummary
        isReasoningActiveSync = isReasoningActive
    }
    /// Complete the reasoning summary and store as final
    func completeReasoningSummary(finalText: String) {
        currentReasoningSummary = finalText
        isReasoningActive = false
        latestReasoningSummary = finalText
        // Update sync caches
        currentReasoningSummarySync = currentReasoningSummary
        isReasoningActiveSync = false
    }
    /// Clear the current reasoning summary (called when new message starts)
    func clearReasoningSummary() {
        currentReasoningSummary = nil
        isReasoningActive = false
        // Update sync caches
        currentReasoningSummarySync = nil
        isReasoningActiveSync = false
    }
    /// Get latest reasoning summary
    func getLatestReasoningSummary() -> String? {
        latestReasoningSummary
    }
    /// Get current reasoning summary (for sidebar)
    func getCurrentReasoningSummary() -> String? {
        currentReasoningSummary
    }
    /// Check if reasoning is active
    func getIsReasoningActive() -> Bool {
        isReasoningActive
    }
    // MARK: - State Management
    /// Restore messages from checkpoint
    func restoreMessages(_ restoredMessages: [OnboardingMessage]) {
        messages = restoredMessages
        messagesSync = messages
        Logger.info("📥 Restored \(messages.count) messages to ChatTranscriptStore", category: .ai)
    }
    /// Reset all messages and state
    func reset() {
        messages.removeAll()
        streamingMessage = nil
        latestReasoningSummary = nil
        previousResponseId = nil
        currentReasoningSummary = nil
        isReasoningActive = false
        // Reset sync caches
        messagesSync = []
        streamingMessageSync = nil
        currentReasoningSummarySync = nil
        isReasoningActiveSync = false
        Logger.info("🔄 ChatTranscriptStore reset", category: .ai)
    }
}
