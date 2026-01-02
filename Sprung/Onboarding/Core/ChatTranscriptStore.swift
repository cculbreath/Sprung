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
    }
    // MARK: - Reasoning Summary (Sidebar Display)
    private(set) var currentReasoningSummary: String?
    private(set) var isReasoningActive = false
    // MARK: - Synchronous Caches (for SwiftUI)
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
        return message.id
    }
    /// Get all messages
    func getAllMessages() -> [OnboardingMessage] {
        messages
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
    /// Begin streaming a message with specific ID
    func beginStreamingMessage(id: UUID, initialText: String, reasoningExpected: Bool) -> UUID {
        streamingMessage = StreamingMessage(
            id: id,
            text: initialText
        )
        let message = OnboardingMessage(
            id: id,
            role: .assistant,
            text: initialText,
            timestamp: Date()
        )
        messages.append(message)
        return id
    }
    /// Update streaming message with delta
    func updateStreamingMessage(id: UUID, delta: String) {
        guard var streaming = streamingMessage, streaming.id == id else { return }
        streaming.text += delta
        streamingMessage = streaming
        if let index = messages.firstIndex(where: { $0.id == id }) {
            messages[index].text += delta
        }
    }
    /// Finalize streaming message
    func finalizeStreamingMessage(id: UUID, finalText: String, toolCalls: [OnboardingMessage.ToolCallInfo]? = nil) {
        streamingMessage = nil
        if let index = messages.firstIndex(where: { $0.id == id }) {
            messages[index].text = finalText
            messages[index].toolCalls = toolCalls
        }
    }

    // MARK: - Tool Result Pairing

    /// Update a tool call with its result (paired storage for Anthropic)
    /// Searches all messages for the tool call ID and fills in the result
    /// Emits `toolResultPairedWithMessage` event to trigger persistence update
    /// - Returns: true if the tool call was found and updated
    func setToolResult(callId: String, result: String) -> Bool {
        // Search through messages to find the one with this tool call
        for index in messages.indices.reversed() {
            if messages[index].setToolResult(callId: callId, result: result) {
                let message = messages[index]
                Logger.debug("📝 Paired tool result with call \(callId.prefix(12)) in message \(message.id)", category: .ai)

                // Emit event for persistence update with the updated toolCallsJSON
                if let toolCalls = message.toolCalls,
                   let data = try? JSONEncoder().encode(toolCalls),
                   let json = String(data: data, encoding: .utf8) {
                    Task {
                        await eventBus.publish(.toolResultPairedWithMessage(messageId: message.id, toolCallsJSON: json))
                    }
                }
                return true
            }
        }
        Logger.warning("⚠️ Could not find tool call \(callId.prefix(12)) to pair with result", category: .ai)
        return false
    }

    /// Get all messages with pending (incomplete) tool calls
    func messagesWithPendingToolCalls() -> [OnboardingMessage] {
        messages.filter { !$0.allToolCallsComplete }
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
    // MARK: - State Management
    /// Restore messages from checkpoint
    func restoreMessages(_ restoredMessages: [OnboardingMessage]) {
        messages = restoredMessages
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
        currentReasoningSummarySync = nil
        isReasoningActiveSync = false
        Logger.info("🔄 ChatTranscriptStore reset", category: .ai)
    }
}
