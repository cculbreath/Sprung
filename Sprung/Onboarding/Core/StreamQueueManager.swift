import Foundation
import SwiftyJSON
/// Manages serial streaming queue for LLM requests.
/// Simplified version: handles request queue only, no tool tracking.
/// Tool batching is coordinated by StateCoordinator using ConversationLog's hasPendingToolCalls.
actor StreamQueueManager {
    // MARK: - Types
    enum StreamRequestType {
        case userMessage(payload: JSON, isSystemGenerated: Bool, chatboxMessageId: String?, originalText: String?, bundledCoordinatorMessages: [JSON])
        case toolResponse(payload: JSON)
        case batchedToolResponses(payloads: [JSON])
        case coordinatorMessage(payload: JSON)
    }
    // MARK: - Dependencies
    private let eventBus: EventCoordinator
    // MARK: - Stream Queue State
    private var isStreaming = false
    private var streamQueue: [StreamRequestType] = []
    private(set) var hasStreamedFirstResponse = false

    // MARK: - Instance Identity (for debugging)
    private let instanceId = UUID()

    // MARK: - Initialization
    init(eventBus: EventCoordinator) {
        self.eventBus = eventBus
        Logger.info("📦 StreamQueueManager created: \(instanceId.uuidString.prefix(8))", category: .ai)
    }
    // MARK: - Public API
    /// Enqueue a stream request to be processed serially
    func enqueue(_ requestType: StreamRequestType) {
        streamQueue.append(requestType)
        Logger.debug("📥 Stream request enqueued (queue size: \(streamQueue.count))", category: .ai)
        if !isStreaming {
            Task {
                await processQueue()
            }
        }
    }

    /// Mark stream as completed
    func markStreamCompleted() async {
        await eventBus.publish(.llm(.streamCompleted))
    }
    /// Handle stream completion (called via event)
    func handleStreamCompleted() {
        guard isStreaming else {
            Logger.warning("handleStreamCompleted called but isStreaming=false", category: .ai)
            return
        }
        isStreaming = false
        hasStreamedFirstResponse = true

        Logger.debug("✅ Stream completed (queue size: \(streamQueue.count))", category: .ai)

        // Process next item in queue if any
        if !streamQueue.isEmpty {
            Task {
                await processQueue()
            }
        }
    }
    /// Check if this is the first response (tools disabled until greeting)
    func getHasStreamedFirstResponse() -> Bool {
        hasStreamedFirstResponse
    }
    /// Reset the queue state
    func reset() {
        isStreaming = false
        streamQueue.removeAll()
        hasStreamedFirstResponse = false
    }
    /// Restore streaming state from snapshot
    func restoreState(hasStreamedFirstResponse: Bool) {
        self.hasStreamedFirstResponse = hasStreamedFirstResponse
        if hasStreamedFirstResponse {
            Logger.info("✅ Restored hasStreamedFirstResponse=true (conversation in progress)", category: .ai)
        }
    }
    // MARK: - Private Methods
    /// Process the stream queue serially
    /// Priority: tool responses must complete before system-generated messages
    /// Exception: Chatbox (non-system-generated) user messages are HIGH PRIORITY
    private func processQueue() async {
        while !streamQueue.isEmpty {
            guard !isStreaming else {
                Logger.debug("⏸️ Queue processing paused (stream in progress)", category: .ai)
                return
            }

            // Check for high-priority chatbox message first
            // Chatbox messages (isSystemGenerated=false) should never be blocked
            if let chatboxIndex = streamQueue.firstIndex(where: { request in
                if case .userMessage(_, let isSystemGenerated, _, _, _) = request {
                    return !isSystemGenerated  // Chatbox messages are NOT system-generated
                }
                return false
            }) {
                isStreaming = true
                let request = streamQueue.remove(at: chatboxIndex)
                Logger.info("▶️ Processing HIGH PRIORITY chatbox message", category: .ai)
                await emitStreamRequest(request)
                continue
            }

            // Find the next request to process
            // Priority: tool responses should be processed before system-generated messages
            let nextIndex: Int
            if let toolIndex = streamQueue.firstIndex(where: { request in
                if case .toolResponse = request { return true }
                if case .batchedToolResponses = request { return true }
                return false
            }) {
                nextIndex = toolIndex
            } else {
                // No tool response in queue - process in FIFO order
                nextIndex = 0
            }
            isStreaming = true
            let request = streamQueue.remove(at: nextIndex)

            Logger.debug("▶️ Processing stream request from queue (\(streamQueue.count) remaining)", category: .ai)
            await emitStreamRequest(request)
        }
    }
    /// Emit the appropriate stream request event for LLMMessenger to handle
    private func emitStreamRequest(_ requestType: StreamRequestType) async {
        switch requestType {
        case .userMessage(let payload, let isSystemGenerated, let chatboxMessageId, let originalText, let bundledCoordinatorMessages):
            await eventBus.publish(.llm(.executeUserMessage(
                payload: payload,
                isSystemGenerated: isSystemGenerated,
                chatboxMessageId: chatboxMessageId,
                originalText: originalText,
                bundledCoordinatorMessages: bundledCoordinatorMessages
            )))
        case .toolResponse(let payload):
            await eventBus.publish(.llm(.executeToolResponse(payload: payload)))
        case .batchedToolResponses(let payloads):
            await eventBus.publish(.llm(.executeBatchedToolResponses(payloads: payloads)))
        case .coordinatorMessage(let payload):
            await eventBus.publish(.llm(.executeCoordinatorMessage(payload: payload)))
        }
    }
}
