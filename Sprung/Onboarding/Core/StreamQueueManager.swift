import Foundation
import SwiftyJSON
/// Manages serial streaming queue for LLM requests.
/// Ensures tool responses are processed before developer messages when tool calls are pending.
/// Extracted from StateCoordinator to improve testability and separation of concerns.
actor StreamQueueManager {
    // MARK: - Types
    enum StreamRequestType {
        case userMessage(payload: JSON, isSystemGenerated: Bool, chatboxMessageId: String?, originalText: String?)
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
    // When true, we're waiting for responseCompleted to tell us the batch count
    // Tool responses that arrive in this state are held until we know the count
    private var awaitingBatchInfo: Bool = false
    // MARK: - Initialization
    init(eventBus: EventCoordinator) {
        self.eventBus = eventBus
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
    /// Signal that tool calls are being received and we should hold responses
    /// Called when the first tool call is received during streaming
    func beginToolCallCollection() {
        guard !awaitingBatchInfo else { return }
        awaitingBatchInfo = true
        Logger.debug("📦 Tool call collection started - holding responses until batch count known", category: .ai)
    }

    /// Start collecting tool responses for a batch
    /// Called when responseCompleted fires and we know the final count
    func startToolCallBatch(expectedCount: Int, callIds: [String]) {
        awaitingBatchInfo = false
        expectedToolResponseCount = expectedCount
        expectedToolCallIds = Set(callIds)
        Logger.info("📦 Tool call batch started: expecting \(expectedCount) responses, already collected \(collectedToolResponses.count)", category: .ai)

        // If we've already collected all responses while waiting, process them now
        if collectedToolResponses.count >= expectedCount {
            let batch = collectedToolResponses
            collectedToolResponses = []
            expectedToolResponseCount = 0
            expectedToolCallIds = []

            if expectedCount == 1 {
                // Single response - send individually
                if let payload = batch.first {
                    enqueue(.toolResponse(payload: payload))
                    Logger.info("📦 Single tool response (collected early) - sending immediately", category: .ai)
                }
            } else {
                // Multiple responses - send as batch
                enqueueBatchedToolResponses(batch)
                Logger.info("📦 All \(batch.count) tool responses (collected early) - sending batch", category: .ai)
            }
        } else if expectedCount == 1 && collectedToolResponses.count == 1 {
            // Single response already collected
            if let payload = collectedToolResponses.first {
                collectedToolResponses = []
                expectedToolResponseCount = 0
                expectedToolCallIds = []
                enqueue(.toolResponse(payload: payload))
                Logger.info("📦 Single tool response (collected early) - sending immediately", category: .ai)
            }
        }
    }
    /// Enqueue a tool response, batching if needed
    func enqueueToolResponse(_ payload: JSON) {
        // If we're waiting to learn the batch count, always collect
        if awaitingBatchInfo {
            collectedToolResponses.append(payload)
            Logger.debug("📦 Holding tool response (awaiting batch info) - collected \(collectedToolResponses.count) so far", category: .ai)
            return
        }

        if expectedToolResponseCount > 1 {
            // Collecting for batch - add to collection
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
            // Single tool call or no batch context - send immediately (preserves blocking behavior)
            enqueue(.toolResponse(payload: payload))
            // Reset batch state for single tool calls
            if expectedToolResponseCount == 1 {
                expectedToolResponseCount = 0
                expectedToolCallIds = []
                Logger.debug("📦 Single tool response processed - batch state reset", category: .ai)
            }
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

        // Reset tool call batch state - LLM has moved on, we shouldn't block waiting
        // for tool responses that may never come or that the LLM no longer expects
        if expectedToolResponseCount > 0 || awaitingBatchInfo {
            Logger.debug("🔄 Stream completed - resetting batch state (expectedCount: \(expectedToolResponseCount), awaitingBatchInfo: \(awaitingBatchInfo))", category: .ai)
            expectedToolResponseCount = 0
            expectedToolCallIds = []
            collectedToolResponses = []
            awaitingBatchInfo = false
        }

        Logger.debug("✅ Stream completed (queue size: \(streamQueue.count))", category: .ai)
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
        awaitingBatchInfo = false
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
    /// Priority: tool responses must be sent before developer messages when tool calls are pending
    private func processQueue() async {
        while !streamQueue.isEmpty {
            guard !isStreaming else {
                Logger.debug("⏸️ Queue processing paused (stream in progress)", category: .ai)
                return
            }
            // Find the next request to process
            // Priority: tool responses > user messages > developer messages
            // Developer messages must wait if tool responses are expected
            let nextIndex: Int
            if expectedToolResponseCount > 0 || hasPendingToolResponse() {
                // Tool responses are expected - prioritize them over developer messages
                if let toolIndex = streamQueue.firstIndex(where: { request in
                    if case .toolResponse = request { return true }
                    if case .batchedToolResponses = request { return true }
                    return false
                }) {
                    nextIndex = toolIndex
                } else {
                    // No tool response in queue yet - wait for it before processing developer messages
                    // But allow user messages to go through
                    if let userIndex = streamQueue.firstIndex(where: { request in
                        if case .userMessage = request { return true }
                        return false
                    }) {
                        nextIndex = userIndex
                    } else {
                        // Only developer messages in queue - wait for tool responses
                        Logger.warning("⏸️ Queue has developer message but waiting for tool responses (expectedCount: \(expectedToolResponseCount), callIds: \(expectedToolCallIds))", category: .ai)
                        return
                    }
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
        case .userMessage(let payload, let isSystemGenerated, let chatboxMessageId, let originalText):
            await eventBus.publish(.llmExecuteUserMessage(
                payload: payload,
                isSystemGenerated: isSystemGenerated,
                chatboxMessageId: chatboxMessageId,
                originalText: originalText
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
