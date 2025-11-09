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
        var toolCalls: [OnboardingMessage.ToolCallInfo]
    }

    private var streamingBuffers: [String: StreamBuffer] = [:]
    private var messageIds: [String: UUID] = [:]
    private var lastMessageUUID: UUID?
    private var receivedOutputItemDone = false

    // Reasoning items tracking - must be passed back with tool outputs
    private var currentResponseReasoningItemIds: [String] = []
    private var currentResponseHasToolCalls = false

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

        case .outputTextDelta(let delta):
            // Handle streaming text deltas for real-time message display
            await processContentDelta(0, delta.delta)

        case .outputItemDone(let done):
            // Handle completed output items (messages, function calls, etc.)
            // Mark that we've received output items so we don't double-process in responseCompleted
            receivedOutputItemDone = true

            switch done.item {
            case .functionCall(let toolCall):
                await processToolCall(toolCall)

            case .message(let message):
                // Only process message content if we're NOT streaming
                // (streaming messages already accumulated via outputTextDelta events)
                if streamingBuffers.isEmpty {
                    await processMessageContent(message)
                }

            case .reasoning(let reasoning):
                await processReasoningItem(reasoning)

            default:
                break
            }

        case .responseCompleted(let completed):
            // If we have buffered messages from streaming, finalize them
            if !streamingBuffers.isEmpty {
                await finalizePendingMessages()
            } else if !receivedOutputItemDone {
                // No streaming occurred AND no outputItemDone events received
                // Extract complete message from final response (fallback for non-streaming responses)
                await processCompletedResponse(completed.response)
            }

            // Store reasoning items if this response had tool calls
            if currentResponseHasToolCalls {
                await emit(.llmReasoningItemsForToolCalls(ids: currentResponseReasoningItemIds))
                Logger.info("🧠 Stored \(currentResponseReasoningItemIds.count) reasoning item(s) for tool response", category: .ai)
            }

            // Reset state for next response
            receivedOutputItemDone = false
            currentResponseReasoningItemIds = []
            currentResponseHasToolCalls = false

            // Emit completion event with response ID
            Logger.info("📨 Response completed: \(completed.response.id)", category: .ai)

        case .responseInProgress(let inProgress):
            // Process deltas from in-progress response
            // Note: Tool calls are handled by outputItemDone, not here
            for item in inProgress.response.output {
                switch item {
                case .message(let message):
                    await processMessageContent(message)

                case .reasoning(let reasoning):
                    await processReasoningItem(reasoning)

                default:
                    break
                }
            }

        case .reasoningSummaryTextDelta(let delta):
            await processReasoningSummaryDelta(delta)

        case .reasoningSummaryTextDone(let done):
            await processReasoningSummaryDone(done)

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
                firstDeltaLogged: false,
                toolCalls: []
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
            let toolCalls = buffer.toolCalls.isEmpty ? nil : buffer.toolCalls
            await emit(.streamingMessageFinalized(id: buffer.messageId, finalText: buffer.text, toolCalls: toolCalls))
        }

        streamingBuffers.removeAll()
        messageIds.removeAll()
        lastMessageUUID = nil
    }

    /// Process a completed response that arrived without streaming deltas
    private func processCompletedResponse(_ response: ResponseModel) async {
        // Extract message content and tool calls from the completed response
        var completeText = ""
        var toolCalls: [OnboardingMessage.ToolCallInfo] = []

        // Process all output items
        for outputItem in response.output {
            switch outputItem {
            case .message(let message):
                // Extract the complete text from the message
                for contentItem in message.content {
                    if case .outputText(let outputText) = contentItem {
                        completeText += outputText.text
                    }
                }

            case .functionCall(let toolCall):
                // Collect tool call info for the assistant message
                toolCalls.append(OnboardingMessage.ToolCallInfo(
                    id: toolCall.id,
                    name: toolCall.name,
                    arguments: toolCall.arguments
                ))

                // Emit tool call event directly (don't call processToolCall which expects buffers)
                let functionName = toolCall.name
                let arguments = toolCall.arguments
                let argsJSON = JSON(parseJSON: arguments)

                let call = ToolCall(
                    id: UUID().uuidString,
                    name: functionName,
                    arguments: argsJSON,
                    callId: toolCall.callId
                )

                await emit(.toolCallRequested(call))
                Logger.info("🔧 Tool call received: \(functionName)", category: .ai)

            case .reasoning(let reasoning):
                await processReasoningItem(reasoning)

            default:
                break
            }
        }

        // Only emit message events if there's actual text content
        // Tool-only responses shouldn't create empty chat bubbles
        if !completeText.isEmpty {
            let messageId = UUID()
            await emit(.streamingMessageBegan(id: messageId, text: completeText, reasoningExpected: false))
            await emit(.streamingMessageFinalized(id: messageId, finalText: completeText, toolCalls: toolCalls.isEmpty ? nil : toolCalls))
            Logger.info("📝 Extracted complete message (\(completeText.count) chars, \(toolCalls.count) tool calls) from completed response", category: .ai)
        } else if !toolCalls.isEmpty {
            Logger.info("🔧 Tool-only response (\(toolCalls.count) tool calls, no text) from completed response", category: .ai)
        } else {
            Logger.warning("⚠️ No text or tool calls in LLM response", category: .ai)
        }
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
        receivedOutputItemDone = false

        Logger.info("🧹 NetworkRouter cleaned up \(bufferCount) cancelled stream(s)", category: .ai)
    }

    // MARK: - Tool Call Processing

    private func processToolCall(_ toolCall: OutputItem.FunctionToolCall) async {
        let functionName = toolCall.name
        let arguments = toolCall.arguments

        // Mark that this response has tool calls (for reasoning item tracking)
        currentResponseHasToolCalls = true

        // Convert arguments string to JSON
        let argsJSON = JSON(parseJSON: arguments)

        // Create tool call with OpenAI's call ID (important for continuations)
        let call = ToolCall(
            id: UUID().uuidString,
            name: functionName,
            arguments: argsJSON,
            callId: toolCall.callId
        )

        // Store tool call info in the current message buffer
        // Assumes tool calls arrive for message_0 (standard assistant message index)
        let itemId = "message_0"
        if var buffer = streamingBuffers[itemId] {
            buffer.toolCalls.append(OnboardingMessage.ToolCallInfo(
                id: toolCall.id,
                name: functionName,
                arguments: arguments
            ))
            streamingBuffers[itemId] = buffer
            Logger.debug("📎 Tool call stored in buffer: \(functionName)", category: .ai)
        } else {
            Logger.warning("⚠️ Tool call received but no message buffer exists: \(functionName)", category: .ai)
        }

        // Emit tool call event (Spec §6: LLM.toolCallReceived)
        // Orchestrator will subscribe to this and manage continuations
        await emit(.toolCallRequested(call))

        Logger.info("🔧 Tool call received: \(functionName)", category: .ai)
    }

    // MARK: - Reasoning Support

    /// Process reasoning item from output (indicates reasoning is present)
    private func processReasoningItem(_ reasoning: OutputItem.Reasoning) async {
        // Store reasoning item ID to pass back with tool responses
        currentResponseReasoningItemIds.append(reasoning.id)
        Logger.debug("🧠 Reasoning output: \(reasoning.id)", category: .ai)
    }

    /// Process reasoning summary text delta (streaming)
    /// Reasoning summaries display in a separate sidebar, not attached to specific messages
    private func processReasoningSummaryDelta(_ event: ReasoningSummaryTextDeltaEvent) async {
        // Emit the actual delta text for StateCoordinator to accumulate in sidebar
        await emit(.llmReasoningSummaryDelta(delta: event.delta))
        Logger.debug("🧠 Reasoning summary delta: \(event.delta.prefix(50))...", category: .ai)
    }

    /// Process reasoning summary completion
    /// Reasoning summaries display in a separate sidebar, not attached to specific messages
    private func processReasoningSummaryDone(_ event: ReasoningSummaryTextDoneEvent) async {
        // Emit the complete text for sidebar display
        await emit(.llmReasoningSummaryComplete(text: event.text))
        Logger.info("🧠 Reasoning summary complete (\(event.text.count) chars)", category: .ai)
    }
}
