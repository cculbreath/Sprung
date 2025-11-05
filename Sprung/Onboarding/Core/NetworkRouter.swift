//
//  NetworkRouter.swift
//  Sprung
//
//  Network stream monitoring and event emission (Spec §4.4)
//  Monitors SSE/WebSocket deltas from OpenAI and converts to events
//

import Foundation
import SwiftOpenAI
import SwiftyJSON

/// Routes inbound network streams to EventCoordinator
/// Responsibilities (Spec §4.4):
/// - Monitor SSE/WebSocket streams
/// - Parse streaming deltas
/// - Emit events: LLM.messageDelta, LLM.messageReceived, LLM.toolCallReceived,
///                LLM.reasoningDelta, LLM.reasoningDone, LLM.error
actor NetworkRouter: OnboardingEventEmitter {
    // MARK: - Properties

    let eventBus: EventCoordinator

    // Stream buffering for delta accumulation
    private struct StreamBuffer {
        let messageId: UUID
        var text: String
        var pendingFragment: String
        let startedAt: Date
        var firstDeltaLogged: Bool
    }

    private var streamingBuffers: [String: StreamBuffer] = [:]
    private var messageIds: [String: UUID] = [:]
    private var lastMessageUUID: UUID?

    // MARK: - Initialization

    init(eventBus: EventCoordinator) {
        self.eventBus = eventBus
        Logger.info("📡 NetworkRouter initialized", category: .ai)
    }

    // MARK: - Stream Processing

    /// Process a ResponseStreamEvent from OpenAI
    func handleResponseEvent(_ event: ResponseStreamEvent) async {
        switch event {
        case .responseFailed(let failed):
            let message = failed.response.error?.message ?? "Response failed"
            await emit(.errorOccurred("Stream error: \(message)"))

        case .responseCompleted(let completed):
            await finalizePendingMessages()
            // Emit completion event with response ID
            Logger.info("📨 Response completed: \(completed.response.id)", category: .ai)

        case .responseInProgress(let inProgress):
            // Process deltas from in-progress response
            for item in inProgress.response.output {
                switch item {
                case .message(let message):
                    await processMessageContent(message)

                case .functionCall(let toolCall):
                    await processToolCall(toolCall)

                default:
                    break
                }
            }

        case .responseCreated, .responseIncomplete:
            // These events don't need special handling
            break

        default:
            break
        }
    }

    // MARK: - Message Processing

    private func processMessageContent(_ message: OutputItem.Message) async {
        for contentItem in message.content {
            if case .outputText(let outputText) = contentItem {
                await processContentDelta(0, outputText.text)
            }
        }
    }

    private func processContentDelta(_ index: Int, _ text: String) async {
        let itemId = "message_\(index)"

        // Initialize buffer for new message
        if streamingBuffers[itemId] == nil {
            let messageId = UUID()
            await emit(.streamingMessageBegan(id: messageId, text: "", reasoningExpected: false))
            streamingBuffers[itemId] = StreamBuffer(
                messageId: messageId,
                text: "",
                pendingFragment: "",
                startedAt: Date(),
                firstDeltaLogged: false
            )
            messageIds[itemId] = messageId
            lastMessageUUID = messageId
        }

        guard var buffer = streamingBuffers[itemId] else { return }
        buffer.text += text
        buffer.pendingFragment += text

        // Emit delta event
        await emit(.streamingMessageUpdated(id: buffer.messageId, delta: buffer.pendingFragment))
        buffer.pendingFragment = ""
        streamingBuffers[itemId] = buffer
    }

    private func finalizePendingMessages() async {
        for (_, buffer) in streamingBuffers {
            await emit(.streamingMessageFinalized(id: buffer.messageId, finalText: buffer.text))
        }

        streamingBuffers.removeAll()
        messageIds.removeAll()
        lastMessageUUID = nil
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
            await emit(.streamingMessageFinalized(id: buffer.messageId, finalText: cancelledText))
            Logger.debug("🛑 Finalized cancelled stream: \(buffer.messageId)", category: .ai)
        }

        // Clean up all tracking state
        streamingBuffers.removeAll()
        messageIds.removeAll()
        lastMessageUUID = nil

        Logger.info("🧹 NetworkRouter cleaned up \(bufferCount) cancelled stream(s)", category: .ai)
    }

    // MARK: - Tool Call Processing

    private func processToolCall(_ toolCall: OutputItem.FunctionToolCall) async {
        let functionName = toolCall.name
        let arguments = toolCall.arguments

        // Convert arguments string to JSON
        let argsJSON = JSON(parseJSON: arguments)

        // Create tool call with OpenAI's call ID (important for continuations)
        let call = ToolCall(
            id: UUID().uuidString,
            name: functionName,
            arguments: argsJSON,
            callId: toolCall.id ?? UUID().uuidString
        )

        // Emit tool call event (Spec §6: LLM.toolCallReceived)
        // Orchestrator will subscribe to this and manage continuations
        await emit(.toolCallRequested(call))

        Logger.info("🔧 Tool call received: \(functionName)", category: .ai)
    }

    // MARK: - Reasoning Support (TODO)

    /// Process reasoning deltas (for future implementation)
    /// Spec §4.4: Should emit LLM.reasoningDelta and LLM.reasoningDone
    func processReasoningDelta(_ delta: String) async {
        // TODO: Implement when OpenAI exposes reasoning in Responses API
        Logger.debug("Reasoning delta: \(delta.prefix(50))...", category: .ai)
    }
}
