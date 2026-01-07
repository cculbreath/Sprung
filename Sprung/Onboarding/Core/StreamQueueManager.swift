import Foundation
import SwiftyJSON
/// Manages serial streaming queue for LLM requests.
/// Ensures tool responses are processed before coordinator messages when tool calls are pending.
/// Extracted from StateCoordinator to improve testability and separation of concerns.
actor StreamQueueManager {
    // MARK: - Types
    enum StreamRequestType {
        case userMessage(payload: JSON, isSystemGenerated: Bool, chatboxMessageId: String?, originalText: String?, bundledCoordinatorMessages: [JSON], toolChoice: String?)
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
    // MARK: - Parallel Tool Call Batching
    private var expectedToolResponseCount: Int = 0
    private var collectedToolResponses: [JSON] = []
    private var currentBatchCallIds: Set<String> = []
    private var pendingUIToolCallIds: Set<String> = []
    private var batchInfoReceived: Bool = true  // False when waiting for llmToolCallBatchStarted, true after it arrives or when ready to send
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
        currentBatchCallIds = Set(callIds)
        expectedToolResponseCount = expectedCount
        batchInfoReceived = true  // We now have batch info
        Logger.info("📦 [\(instanceId.uuidString.prefix(8))] Tool call batch started: expecting \(expectedCount) responses, callIds: \(callIds.map { String($0.prefix(8)) }), already collected \(collectedToolResponses.count), pending UI: \(pendingUIToolCallIds.count)", category: .ai)

        // Check if we can release any held responses
        tryReleaseBatch()
    }

    /// Mark a tool call as a UI tool (pending user action)
    /// UI tools don't emit responses until user acts
    func markUIToolPending(callId: String) {
        pendingUIToolCallIds.insert(callId)
        Logger.info("📦 [\(instanceId.uuidString.prefix(8))] UI tool marked pending: \(callId.prefix(8)), total pending: \(pendingUIToolCallIds.count)", category: .ai)
    }

    /// Mark a UI tool as complete and try to release the batch
    /// Called when user completes a UI action (choice selection, upload, etc.)
    func markUIToolComplete(callId: String) {
        pendingUIToolCallIds.remove(callId)

        // If this was a solo UI tool completing after its batch was processed,
        // set batchInfoReceived=true so its response can be sent immediately
        if pendingUIToolCallIds.isEmpty && currentBatchCallIds.isEmpty {
            batchInfoReceived = true
        }

        Logger.info("📦 [\(instanceId.uuidString.prefix(8))] UI tool completed: \(callId.prefix(8)), remaining pending: \(pendingUIToolCallIds.count), batchInfoReceived: \(batchInfoReceived)", category: .ai)

        // UI tool's response will be enqueued separately via enqueueToolResponse
        // Try to release the batch if all tools are now complete
        tryReleaseBatch()
    }

    /// Check if we have a pending UI tool in the current batch
    private func hasPendingUIToolInBatch() -> Bool {
        // Check if any of the current batch's callIds are pending UI tools
        !currentBatchCallIds.intersection(pendingUIToolCallIds).isEmpty
    }

    /// Try to release collected responses if all conditions are met
    private func tryReleaseBatch() {
        // Don't release if we're still waiting for UI tools in this batch
        if hasPendingUIToolInBatch() {
            Logger.debug("📦 Holding batch - waiting for UI tool(s): \(currentBatchCallIds.intersection(pendingUIToolCallIds).map { String($0.prefix(8)) })", category: .ai)
            return
        }

        // Don't release if we haven't collected all expected responses
        guard !collectedToolResponses.isEmpty else { return }

        // If we have all responses (accounting for UI tools that added theirs), release
        let uiToolsInBatch = currentBatchCallIds.count > 0 ? currentBatchCallIds.intersection(pendingUIToolCallIds).count : 0
        let expectedNonUIResponses = max(0, expectedToolResponseCount - uiToolsInBatch)

        if collectedToolResponses.count >= expectedNonUIResponses || expectedToolResponseCount == 0 {
            // Release the batch
            if collectedToolResponses.count == 1 {
                enqueue(.toolResponse(payload: collectedToolResponses[0]))
                Logger.info("📦 Released single tool response", category: .ai)
            } else if collectedToolResponses.count > 1 {
                enqueueBatchedToolResponses(collectedToolResponses)
                Logger.info("📦 Released batch of \(collectedToolResponses.count) tool responses", category: .ai)
            }
            // Reset batch state
            collectedToolResponses = []
            expectedToolResponseCount = 0
            currentBatchCallIds = []
        }
    }

    /// Enqueue a tool response, batching if needed for parallel tool calls
    func enqueueToolResponse(_ payload: JSON) {
        let callId = payload["callId"].stringValue
        Logger.info("📦 [\(instanceId.uuidString.prefix(8))] enqueueToolResponse called: callId=\(callId.prefix(8)), expectedCount=\(expectedToolResponseCount), collected=\(collectedToolResponses.count), pendingUI=\(pendingUIToolCallIds.count), batchInfoReceived=\(batchInfoReceived), batchIds=\(currentBatchCallIds.count)", category: .ai)

        // Always collect the response
        collectedToolResponses.append(payload)

        // If we have batch info, use normal release logic
        if batchInfoReceived && (expectedToolResponseCount > 0 || !currentBatchCallIds.isEmpty) {
            tryReleaseBatch()
            return
        }

        // Check if we should hold or send
        if !batchInfoReceived {
            // Don't have batch info yet - hold until llmToolCallBatchStarted arrives
            Logger.info("📦 Holding response - waiting for batch info (llmToolCallBatchStarted)", category: .ai)
            return
        }

        // batchInfoReceived=true but no active batch - this is a solo response (UI tool just completed)
        if pendingUIToolCallIds.isEmpty {
            Logger.info("📦 Solo tool response (no pending UI tools) - sending immediately", category: .ai)
            let responses = collectedToolResponses
            collectedToolResponses = []
            if responses.count == 1 {
                enqueue(.toolResponse(payload: responses[0]))
            } else {
                enqueueBatchedToolResponses(responses)
            }
        } else {
            // There are pending UI tools - hold until they complete
            Logger.info("📦 Holding response - UI tool(s) pending", category: .ai)
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

        Logger.debug("✅ Stream completed (queue size: \(streamQueue.count), pending tools: \(expectedToolResponseCount), collected: \(collectedToolResponses.count), pendingUI: \(pendingUIToolCallIds.count), batchInfoReceived: \(batchInfoReceived))", category: .ai)

        // If batch info hasn't been received yet, don't flush - wait for startToolCallBatch
        // This prevents premature sending before we know about UI tools in the batch
        if !batchInfoReceived {
            Logger.info("📦 Stream completed but waiting for batch info - holding \(collectedToolResponses.count) response(s)", category: .ai)
            // Process queue for non-tool items
            if !streamQueue.isEmpty {
                Task {
                    await processQueue()
                }
            }
            return
        }

        // Try to release any held responses if no UI tools are pending
        if !hasPendingUIToolInBatch() && !collectedToolResponses.isEmpty {
            tryReleaseBatch()
        }

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
        collectedToolResponses = []
        currentBatchCallIds = []
        pendingUIToolCallIds = []
        batchInfoReceived = true  // Reset to true so subsequent solo responses can send
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
    /// Priority: tool responses must complete before system-generated messages when tool calls are pending
    /// Exception: Chatbox (non-system-generated) user messages are HIGH PRIORITY and clear any tool response block
    private func processQueue() async {
        while !streamQueue.isEmpty {
            guard !isStreaming else {
                Logger.debug("⏸️ Queue processing paused (stream in progress)", category: .ai)
                return
            }

            // Check for high-priority chatbox message first
            // Chatbox messages (isSystemGenerated=false) should never be blocked by pending tool responses
            if let chatboxIndex = streamQueue.firstIndex(where: { request in
                if case .userMessage(_, let isSystemGenerated, _, _, _, _) = request {
                    return !isSystemGenerated  // Chatbox messages are NOT system-generated
                }
                return false
            }) {
                // Clear tool response expectation - chatbox messages take priority
                if expectedToolResponseCount > 0 || !collectedToolResponses.isEmpty {
                    Logger.info("🔔 Chatbox message detected - clearing tool response block (was expecting \(expectedToolResponseCount), held \(collectedToolResponses.count))", category: .ai)
                    expectedToolResponseCount = 0
                    collectedToolResponses = []
                }
                isStreaming = true
                batchInfoReceived = false  // Reset - new stream may have tool calls
                let request = streamQueue.remove(at: chatboxIndex)
                Logger.info("▶️ Processing HIGH PRIORITY chatbox message", category: .ai)
                await emitStreamRequest(request)
                continue
            }

            // Find the next request to process
            // Priority: tool responses MUST complete before system-generated user or developer messages
            // This prevents race conditions where system messages trigger LLM turns before tool responses arrive
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
                    // No tool response in queue yet - wait for it before processing system messages
                    Logger.debug("⏸️ Queue waiting for tool responses (expectedCount: \(expectedToolResponseCount), held: \(collectedToolResponses.count), queue: \(streamQueue.count))", category: .ai)
                    return
                }
            } else {
                // No pending tool calls - process in FIFO order
                nextIndex = 0
            }
            isStreaming = true
            let request = streamQueue.remove(at: nextIndex)

            // Reset batchInfoReceived for requests that may trigger tool calls
            // (user messages, coordinator messages) but NOT for tool responses
            switch request {
            case .userMessage, .coordinatorMessage:
                batchInfoReceived = false  // New stream may have tool calls
            case .toolResponse, .batchedToolResponses:
                break  // Don't reset for tool responses
            }

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
        case .userMessage(let payload, let isSystemGenerated, let chatboxMessageId, let originalText, let bundledCoordinatorMessages, let toolChoice):
            await eventBus.publish(.llmExecuteUserMessage(
                payload: payload,
                isSystemGenerated: isSystemGenerated,
                chatboxMessageId: chatboxMessageId,
                originalText: originalText,
                bundledCoordinatorMessages: bundledCoordinatorMessages,
                toolChoice: toolChoice
            ))
        case .toolResponse(let payload):
            await eventBus.publish(.llmExecuteToolResponse(payload: payload))
        case .batchedToolResponses(let payloads):
            await eventBus.publish(.llmExecuteBatchedToolResponses(payloads: payloads))
        case .coordinatorMessage(let payload):
            await eventBus.publish(.llmExecuteCoordinatorMessage(payload: payload))
        }
    }
}
