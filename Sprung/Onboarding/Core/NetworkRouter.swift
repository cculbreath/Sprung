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
        var toolCalls: [OnboardingMessage.ToolCallInfo]
    }
    private var streamingBuffers: [String: StreamBuffer] = [:]
    private var messageIds: [String: UUID] = [:]
    private var receivedOutputItemDone = false
    // Track tool call IDs for parallel tool call batching
    private var pendingToolCallIds: [String] = []
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
            // Clear any pending state to prevent stuck states
            pendingToolCallIds = []
            receivedOutputItemDone = false
            streamingBuffers.removeAll()
            await emit(.errorOccurred("Stream error: \(message)"))
            // Emit stream completed so the queue can continue processing
            await emit(.llmStreamCompleted)
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
            case .webSearchCall(let webSearch):
                await processWebSearchCall(webSearch)
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
            // If there were tool calls, emit batch start event so StateCoordinator knows how many to collect
            if !pendingToolCallIds.isEmpty {
                let count = pendingToolCallIds.count
                let callIds = pendingToolCallIds
                pendingToolCallIds = []  // Reset for next response
                await emit(.llmToolCallBatchStarted(expectedCount: count, callIds: callIds))
                Logger.info("🔧 Tool call batch started: expecting \(count) response(s)", category: .ai)
            }
            // Emit token usage event if usage data is available
            if let usage = completed.response.usage {
                let modelId = completed.response.model
                await emit(.llmTokenUsageReceived(
                    modelId: modelId,
                    inputTokens: usage.inputTokens ?? 0,
                    outputTokens: usage.outputTokens ?? 0,
                    cachedTokens: usage.inputTokensDetails?.cachedTokens ?? 0,
                    reasoningTokens: usage.outputTokensDetails?.reasoningTokens ?? 0,
                    source: .mainCoordinator
                ))
            }
            // Reset state for next response
            receivedOutputItemDone = false
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
                case .webSearchCall(let webSearch):
                    await processWebSearchCall(webSearch)
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
        // Skip empty text - OpenAI sends empty output_text items before tool-only responses
        guard !text.isEmpty else { return }

        let itemId = "message_\(index)"
        // Initialize buffer for new message
        if streamingBuffers[itemId] == nil {
            let messageId = UUID()
            await emit(.streamingMessageBegan(id: messageId, text: "", reasoningExpected: false, statusMessage: "Receiving response..."))
            streamingBuffers[itemId] = StreamBuffer(
                messageId: messageId,
                text: "",
                pendingFragment: "",
                toolCalls: []
            )
            messageIds[itemId] = messageId
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
    }
    /// Process a completed response that arrived without streaming deltas
    private func processCompletedResponse(_ response: ResponseModel) async {
        // Extract message content and tool calls from the completed response
        var completeText = ""
        var allAnnotations: [OutputItem.ContentItem.Annotation] = []
        var toolCalls: [OnboardingMessage.ToolCallInfo] = []
        // Process all output items
        for outputItem in response.output {
            switch outputItem {
            case .message(let message):
                // Extract the complete text and annotations from the message
                for contentItem in message.content {
                    if case .outputText(let outputText) = contentItem {
                        completeText += outputText.text
                        allAnnotations.append(contentsOf: outputText.annotations)
                    }
                }
            case .functionCall(let toolCall):
                // Collect tool call info for the assistant message
                toolCalls.append(OnboardingMessage.ToolCallInfo(
                    id: toolCall.id,
                    name: toolCall.name,
                    arguments: toolCall.arguments
                ))
                // Track this call ID for parallel tool call batching
                pendingToolCallIds.append(toolCall.callId)
                // Emit tool call event directly (don't call processToolCall which expects buffers)
                let functionName = toolCall.name
                let arguments = toolCall.arguments
                let argsJSON = JSON(parseJSON: arguments)
                let call = ToolCall(
                    name: functionName,
                    arguments: argsJSON,
                    callId: toolCall.callId
                )
                await emit(.toolCallRequested(call, statusMessage: "Executing \(functionName)..."))
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
            // Apply URL citations as markdown links
            let annotatedText = applyURLCitations(to: completeText, annotations: allAnnotations)
            let messageId = UUID()
            await emit(.streamingMessageBegan(id: messageId, text: annotatedText, reasoningExpected: false))
            await emit(.streamingMessageFinalized(id: messageId, finalText: annotatedText, toolCalls: toolCalls.isEmpty ? nil : toolCalls))
            let citationCount = allAnnotations.filter { $0.isURLCitation }.count
            Logger.info("📝 Extracted complete message (\(completeText.count) chars, \(toolCalls.count) tool calls, \(citationCount) citations) from completed response", category: .ai)
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
        receivedOutputItemDone = false
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
            name: functionName,
            arguments: argsJSON,
            callId: toolCall.callId
        )

        // Track this call ID for parallel tool call batching
        pendingToolCallIds.append(toolCall.callId)
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
        await emit(.toolCallRequested(call, statusMessage: "Processing \(functionName)..."))
        Logger.info("🔧 Tool call received: \(functionName)", category: .ai)
    }
    // MARK: - Web Search Support

    /// Process web search tool call from output
    /// Web search is a hosted tool - results are automatically included in the model's response
    private func processWebSearchCall(_ webSearch: OutputItem.WebSearchToolCall) async {
        // Web search results are automatically included in the model's response text
        // The annotations in the message will contain URL citations
        // No explicit action needed here - just log for debugging
        Logger.info("🌐 Web search completed: id=\(webSearch.id), status=\(webSearch.status ?? "unknown")", category: .ai)
    }

    // MARK: - Reasoning Support
    /// Process reasoning item from output (indicates reasoning is present)
    private func processReasoningItem(_ reasoning: OutputItem.Reasoning) async {
        // Reasoning items are handled automatically by previous_response_id
        // No need to track or pass them back with tool responses
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

    // MARK: - URL Citation Processing

    /// Apply URL citations from web search as markdown links
    /// Transforms citation markers in text to clickable markdown links
    private func applyURLCitations(to text: String, annotations: [OutputItem.ContentItem.Annotation]) -> String {
        // Filter to only URL citations and sort by start index descending
        // (Process from end to start so indices remain valid during replacement)
        let urlCitations = annotations
            .filter { $0.isURLCitation }
            .sorted { $0.startIndex > $1.startIndex }

        guard !urlCitations.isEmpty else { return text }

        var result = text
        for citation in urlCitations {
            guard let url = citation.url else { continue }

            let startIndex = citation.startIndex
            let endIndex = citation.endIndex

            // Validate indices are within bounds
            guard startIndex >= 0,
                  endIndex <= result.count,
                  startIndex < endIndex else { continue }

            // Convert string indices
            let start = result.index(result.startIndex, offsetBy: startIndex)
            let end = result.index(result.startIndex, offsetBy: endIndex)

            // Get the original text at this range (e.g., "[1]" or the cited text)
            let originalText = String(result[start..<end])

            // Create markdown link with title or original text as link text
            let linkText = citation.title ?? originalText
            let markdownLink = "[\(linkText)](\(url))"

            // Replace the original text with the markdown link
            result.replaceSubrange(start..<end, with: markdownLink)
        }

        return result
    }
}
