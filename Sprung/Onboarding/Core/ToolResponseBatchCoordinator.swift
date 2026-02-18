import Foundation
import SwiftyJSON

/// Coordinates tool response batching: collects payloads from individual
/// .enqueueToolResponse events and releases them as a single batch once all
/// ConversationLog slots are filled.
actor ToolResponseBatchCoordinator {
    private let conversationLog: ConversationLog
    private let streamQueueManager: StreamQueueManager
    private var collectedPayloads: [JSON] = []

    init(conversationLog: ConversationLog, streamQueueManager: StreamQueueManager) {
        self.conversationLog = conversationLog
        self.streamQueueManager = streamQueueManager
    }

    /// Reset collected payloads for a new batch.
    /// Called when a tool call batch starts (ConversationLog already has slots via appendAssistant).
    func batchStarted(expectedCount: Int, callIds: [String]) {
        collectedPayloads = []
        Logger.info("📦 Tool call batch started: expecting \(expectedCount) responses, callIds: \(callIds.map { String($0.prefix(8)) })", category: .ai)
    }

    /// Collect a tool response payload and release the batch if all slots are filled.
    func payloadReceived(_ payload: JSON) async {
        collectedPayloads.append(payload)
        let callId = payload["callId"].stringValue
        Logger.info("📦 Tool response collected: \(callId.prefix(8)) (total: \(collectedPayloads.count))", category: .ai)

        // Check if all ConversationLog slots are filled (including UI tool slots)
        let hasPending = await conversationLog.hasPendingToolCalls
        if !hasPending {
            await releasePayloads()
        } else {
            Logger.debug("📦 Holding tool response - waiting for more slots to fill", category: .ai)
        }
    }

    /// A tool slot was filled in ConversationLog -- check if held payloads can now be released.
    func slotFilled() async {
        if !collectedPayloads.isEmpty {
            let hasPending = await conversationLog.hasPendingToolCalls
            if !hasPending {
                await releasePayloads()
            }
        }
    }

    /// Discard all collected payloads (used during reset).
    func reset() {
        collectedPayloads = []
    }

    // MARK: - Private

    private func releasePayloads() async {
        let payloadsToSend = collectedPayloads
        collectedPayloads = []
        if payloadsToSend.count == 1 {
            await streamQueueManager.enqueue(.toolResponse(payload: payloadsToSend[0]))
            Logger.info("📦 Single tool response enqueued", category: .ai)
        } else if payloadsToSend.count > 1 {
            await streamQueueManager.enqueue(.batchedToolResponses(payloads: payloadsToSend))
            Logger.info("📦 Batched tool responses enqueued (\(payloadsToSend.count) responses)", category: .ai)
        }
    }
}
