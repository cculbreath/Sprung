import Foundation
import SwiftyJSON
/// Manages serial streaming queue for LLM requests.
/// Ensures tool responses are processed before developer messages when tool calls are pending.
/// Extracted from StateCoordinator to improve testability and separation of concerns.
actor StreamQueueManager {
    // MARK: - Types
    enum StreamRequestType {
        case userMessage(payload: JSON, isSystemGenerated: Bool, chatboxMessageId: String?, originalText: String?, bundledDeveloperMessages: [JSON], toolChoice: String?)
        case toolResponse(payload: JSON)
        case batchedToolResponses(payloads: [JSON])
        case developerMessage(payload: JSON)
    }
    // MARK: - Dependencies
    private let eventBus: EventCoordinator
    // MARK: - Stream Queue State
    private var isStreaming = false
    private var streamQueue: [StreamRequestType] = []
    private(set) var hasStreamedFirstResponse = false
    // MARK: - Parallel Tool Call Batching
    private var expectedToolResponseCount: Int = 0
    private var expectedToolCallIds: Set<String> = []
    private var collectedToolResponses: [JSON] = []
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
    /// Start collecting tool responses for a batch (parallel tool calls)
    /// Called when responseCompleted fires and we know the final count
    func startToolCallBatch(expectedCount: Int, callIds: [String]) {
        Logger.info("📦 [\(instanceId.uuidString.prefix(8))] Tool call batch started: expecting \(expectedCount) responses, already collected \(collectedToolResponses.count)", category: .ai)

        // Process any responses that arrived before we knew the batch count
        if !collectedToolResponses.isEmpty {
            if expectedCount == 1 && collectedToolResponses.count >= 1 {
                // Single tool call - send immediately
                if let payload = collectedToolResponses.first {
                    collectedToolResponses.removeFirst()
                    enqueue(.toolResponse(payload: payload))
                    Logger.info("📦 Single tool response (collected early) - sent", category: .ai)
                }
                expectedToolResponseCount = 0
                expectedToolCallIds = []
                // Process any extras (shouldn't happen but be safe)
                for extra in collectedToolResponses {
                    enqueue(.toolResponse(payload: extra))
                }
                collectedToolResponses = []
            } else if collectedToolResponses.count >= expectedCount {
                // All responses already collected - send as batch
                let batch = collectedToolResponses
                collectedToolResponses = []
                expectedToolResponseCount = 0
                expectedToolCallIds = []
                enqueueBatchedToolResponses(batch)
                Logger.info("📦 All \(batch.count) tool responses (collected early) - sent as batch", category: .ai)
            } else {
                // Still waiting for more responses
                expectedToolResponseCount = expectedCount
                expectedToolCallIds = Set(callIds)
                Logger.info("📦 Waiting for \(expectedCount - collectedToolResponses.count) more tool responses", category: .ai)
            }
        } else {
            expectedToolResponseCount = expectedCount
            expectedToolCallIds = Set(callIds)
        }
    }
    /// Enqueue a tool response, batching if needed for parallel tool calls
    func enqueueToolResponse(_ payload: JSON) {
        let callId = payload["callId"].stringValue.prefix(12)
        Logger.info("📦 [\(instanceId.uuidString.prefix(8))] enqueueToolResponse called: callId=\(callId), expectedCount=\(expectedToolResponseCount), collected=\(collectedToolResponses.count)", category: .ai)

        // If we don't know the batch count yet, hold the response
        // startToolCallBatch will process collected responses when it's called
        if expectedToolResponseCount == 0 {
            collectedToolResponses.append(payload)
            Logger.info("📦 Holding tool response (batch count unknown) - collected \(collectedToolResponses.count)", category: .ai)
            return
        }

        // For batching (multiple parallel tool calls), collect responses
        if expectedToolResponseCount > 1 {
            collectedToolResponses.append(payload)
            Logger.debug("📦 Collected tool response \(collectedToolResponses.count)/\(expectedToolResponseCount)", category: .ai)
            // Check if we have all responses
            if collectedToolResponses.count >= expectedToolResponseCount {
                // All responses collected - emit batch for execution
                let batch = collectedToolResponses
                // Reset batching state
                expectedToolResponseCount = 0
                expectedToolCallIds = []
                collectedToolResponses = []
                // Enqueue batch as a single request
                enqueueBatchedToolResponses(batch)
                Logger.info("📦 All \(batch.count) tool responses collected - sending batch", category: .ai)
            }
        } else {
            // Single tool call - send immediately
            enqueue(.toolResponse(payload: payload))
            expectedToolResponseCount = 0
            expectedToolCallIds = []
            Logger.debug("📦 Single tool response - sent immediately", category: .ai)
        }
    }
    /// Mark stream as completed
    func markStreamCompleted() async {
        // Emit event instead of directly processing - this ensures the stream completion
        // is processed in order with other events like llmToolCallBatchStarted
        await eventBus.publish(.llmStreamCompleted)
    }
    /// Handle stream completion (called via event)
    func handleStreamCompleted() {
        guard isStreaming else {
            Logger.warning("handleStreamCompleted called but isStreaming=false", category: .ai)
            return
        }
        isStreaming = false
        hasStreamedFirstResponse = true

        // NOTE: We do NOT reset batch state here. The batch state (expectedToolResponseCount,
        // collectedToolResponses) is managed by startToolCallBatch and enqueueToolResponse.
        // Resetting here would cause race conditions where tool responses are lost.

        Logger.debug("✅ Stream completed (queue size: \(streamQueue.count), pending tools: \(expectedToolResponseCount), collected: \(collectedToolResponses.count))", category: .ai)
        // Process next item in queue if any
        if !streamQueue.isEmpty {
            Task {
                await processQueue()
            }
        }
    }
    /// Check if this is the first response (for toolChoice logic)
    func getHasStreamedFirstResponse() -> Bool {
        hasStreamedFirstResponse
    }
    /// Reset the queue state
    func reset() {
        isStreaming = false
        streamQueue.removeAll()
        hasStreamedFirstResponse = false
        expectedToolResponseCount = 0
        expectedToolCallIds = []
        collectedToolResponses = []
    }
    /// Restore streaming state from snapshot
    func restoreState(hasStreamedFirstResponse: Bool) {
        self.hasStreamedFirstResponse = hasStreamedFirstResponse
        if hasStreamedFirstResponse {
            Logger.info("✅ Restored hasStreamedFirstResponse=true (conversation in progress)", category: .ai)
        }
    }
    // MARK: - Private Methods
    /// Enqueue batched tool responses as a single request
    private func enqueueBatchedToolResponses(_ payloads: [JSON]) {
        streamQueue.append(.batchedToolResponses(payloads: payloads))
        Logger.debug("📥 Batched tool responses enqueued (queue size: \(streamQueue.count))", category: .ai)
        if !isStreaming {
            Task {
                await processQueue()
            }
        }
    }
    /// Process the stream queue serially
    /// Priority: tool responses must complete before ANY other messages when tool calls are pending
    /// This prevents duplicate LLM responses when UI flows send messages during tool execution
    private func processQueue() async {
        while !streamQueue.isEmpty {
            guard !isStreaming else {
                Logger.debug("⏸️ Queue processing paused (stream in progress)", category: .ai)
                return
            }
            // Find the next request to process
            // Priority: tool responses MUST complete before user or developer messages
            // This prevents race conditions where user messages trigger LLM turns before tool responses arrive
            let nextIndex: Int
            if expectedToolResponseCount > 0 || hasPendingToolResponse() || !collectedToolResponses.isEmpty {
                // Tool responses are expected - they MUST be processed first
                if let toolIndex = streamQueue.firstIndex(where: { request in
                    if case .toolResponse = request { return true }
                    if case .batchedToolResponses = request { return true }
                    return false
                }) {
                    nextIndex = toolIndex
                } else {
                    // No tool response in queue yet - wait for it before processing ANY messages
                    // This prevents duplicate LLM responses from user messages arriving during tool execution
                    Logger.debug("⏸️ Queue waiting for tool responses (expectedCount: \(expectedToolResponseCount), held: \(collectedToolResponses.count), queue: \(streamQueue.count))", category: .ai)
                    return
                }
            } else {
                // No pending tool calls - process in FIFO order
                nextIndex = 0
            }
            isStreaming = true
            let request = streamQueue.remove(at: nextIndex)
            Logger.debug("▶️ Processing stream request from queue (\(streamQueue.count) remaining)", category: .ai)
            // Emit event for LLMMessenger to react to
            await emitStreamRequest(request)
            // Note: isStreaming will be set to false when .streamCompleted event is received
        }
    }
    /// Check if there are pending tool responses in the queue
    private func hasPendingToolResponse() -> Bool {
        streamQueue.contains { request in
            if case .toolResponse = request { return true }
            if case .batchedToolResponses = request { return true }
            return false
        }
    }
    /// Emit the appropriate stream request event for LLMMessenger to handle
    private func emitStreamRequest(_ requestType: StreamRequestType) async {
        switch requestType {
        case .userMessage(let payload, let isSystemGenerated, let chatboxMessageId, let originalText, let bundledDeveloperMessages, let toolChoice):
            await eventBus.publish(.llmExecuteUserMessage(
                payload: payload,
                isSystemGenerated: isSystemGenerated,
                chatboxMessageId: chatboxMessageId,
                originalText: originalText,
                bundledDeveloperMessages: bundledDeveloperMessages,
                toolChoice: toolChoice
            ))
        case .toolResponse(let payload):
            await eventBus.publish(.llmExecuteToolResponse(payload: payload))
        case .batchedToolResponses(let payloads):
            await eventBus.publish(.llmExecuteBatchedToolResponses(payloads: payloads))
        case .developerMessage(let payload):
            await eventBus.publish(.llmExecuteDeveloperMessage(payload: payload))
        }
    }
}
