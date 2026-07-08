//
//  NetworkRouter.swift
//  Sprung
//
//  Network stream monitoring and event emission (Spec §4.4)
//  Monitors SSE/WebSocket deltas and converts to events
//
import Foundation
import SwiftOpenAI
import SwiftyJSON
/// Routes inbound network streams to EventBus
/// Responsibilities (Spec §4.4):
/// - Monitor SSE/WebSocket streams
/// - Parse streaming deltas
/// - Emit events: LLM.messageDelta, LLM.messageReceived, LLM.toolCallReceived, LLM.error
actor NetworkRouter: OnboardingEventEmitter {
    // MARK: - Properties
    let eventBus: EventBus
    // Stream buffering for delta accumulation
    private struct StreamBuffer {
        let messageId: UUID
        var text: String
        var pendingFragment: String
        var toolCalls: [OnboardingMessage.ToolCallInfo]
    }
    private var streamingBuffers: [String: StreamBuffer] = [:]
    private var messageIds: [String: UUID] = [:]
    private var receivedOutputItemDone = false
    // MARK: - Initialization
    init(eventBus: EventBus) {
        self.eventBus = eventBus
        Logger.info("📡 NetworkRouter initialized", category: .ai)
    }
    // MARK: - Stream Cancellation (Phase 2)
    /// Cancel and clean up any in-progress streaming messages
    /// Called when user cancels LLM mid-response
    func cancelPendingStreams() async {
        guard !streamingBuffers.isEmpty else {
            Logger.debug("No pending streams to cancel", category: .ai)
            return
        }
        let bufferCount = streamingBuffers.count
        // Finalize all partial messages with their current text
        for (_, buffer) in streamingBuffers {
            let cancelledText = buffer.text.isEmpty ? "(cancelled)" : buffer.text
            await emit(.llm(.streamingMessageFinalized(id: buffer.messageId, finalText: cancelledText, toolCalls: nil, statusMessage: nil)))
            Logger.debug("🛑 Finalized cancelled stream: \(buffer.messageId)", category: .ai)
        }
        // Clean up all tracking state
        streamingBuffers.removeAll()
        messageIds.removeAll()
        receivedOutputItemDone = false
        Logger.info("🧹 NetworkRouter cleaned up \(bufferCount) cancelled stream(s)", category: .ai)
    }
}
