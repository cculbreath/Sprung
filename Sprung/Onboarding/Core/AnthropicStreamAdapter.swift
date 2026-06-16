//
//  AnthropicStreamAdapter.swift
//  Sprung
//
//  Adapts Anthropic stream events to onboarding domain events.
//  Maps Anthropic's SSE streaming format to the existing OnboardingEvent types.
//

import Foundation
import SwiftOpenAI
import SwiftyJSON

/// Adapts Anthropic stream events to onboarding domain events.
/// Maintains state across events to reconstruct complete messages and tool calls.
struct AnthropicStreamAdapter {
    private var messageId: UUID?
    private var accumulatedText: String = ""
    private var pendingToolCalls: [OnboardingMessage.ToolCallInfo] = []
    private var currentToolCall: PartialToolCall?
    private var inputTokens: Int = 0
    private var outputTokens: Int = 0
    private var cacheReadTokens: Int = 0
    private var cacheCreationTokens: Int = 0
    private var modelId: String = ""

    /// Partial tool call being assembled from streaming events
    private struct PartialToolCall {
        let id: String
        let name: String
        var inputJson: String = ""
    }

    /// Process an Anthropic stream event and return domain events to emit
    mutating func process(_ event: AnthropicStreamEvent) -> [OnboardingEvent] {
        switch event {
        case .messageStart(let startEvent):
            return handleMessageStart(startEvent)

        case .contentBlockStart(let blockStart):
            return handleContentBlockStart(blockStart)

        case .contentBlockDelta(let delta):
            return handleContentBlockDelta(delta)

        case .contentBlockStop(let blockStop):
            return handleContentBlockStop(blockStop)

        case .messageDelta(let messageDelta):
            return handleMessageDelta(messageDelta)

        case .messageStop:
            return handleMessageStop()

        case .error(let errorEvent):
            return [.processing(.errorOccurred(errorEvent.error.message))]

        case .ping, .unknown:
            return []
        }
    }

    // MARK: - Event Handlers

    private mutating func handleMessageStart(_ event: AnthropicMessageStartEvent) -> [OnboardingEvent] {
        messageId = UUID()
        accumulatedText = ""
        pendingToolCalls = []
        currentToolCall = nil
        modelId = event.message.model

        // Record initial token counts (cache fields arrive on message_start)
        if let input = event.message.usage.inputTokens {
            inputTokens = input
        }
        if let output = event.message.usage.outputTokens {
            outputTokens = output
        }
        if let cacheRead = event.message.usage.cacheReadInputTokens {
            cacheReadTokens = cacheRead
        }
        if let cacheCreation = event.message.usage.cacheCreationInputTokens {
            cacheCreationTokens = cacheCreation
        }

        return [.llm(.streamingMessageBegan(
            id: messageId!,
            text: "",
            statusMessage: nil
        ))]
    }

    private mutating func handleContentBlockStart(_ event: AnthropicContentBlockStartEvent) -> [OnboardingEvent] {
        let block = event.contentBlock

        if block.type == "tool_use" {
            // Start accumulating tool call
            if let id = block.id, let name = block.name {
                currentToolCall = PartialToolCall(id: id, name: name)
                Logger.debug("🔧 Anthropic: Starting tool use block: \(name) (id: \(id))", category: .ai)
            }
        }

        return []
    }

    private mutating func handleContentBlockDelta(_ event: AnthropicContentBlockDeltaEvent) -> [OnboardingEvent] {
        var events: [OnboardingEvent] = []

        switch event.delta {
        case .textDelta(let text):
            // Text content delta
            accumulatedText += text
            if let id = messageId {
                events.append(.llm(.streamingMessageUpdated(id: id, delta: text, statusMessage: nil)))
            }

        case .inputJsonDelta(let partialJson):
            // Tool input JSON delta
            currentToolCall?.inputJson += partialJson

        case .unknown:
            break
        }

        return events
    }

    private mutating func handleContentBlockStop(_ event: AnthropicContentBlockStopEvent) -> [OnboardingEvent] {
        // If we were building a tool call, finalize it
        if let toolCall = currentToolCall {
            // Store as raw string for ToolCallInfo (used in message display)
            let toolCallInfo = OnboardingMessage.ToolCallInfo(
                id: toolCall.id,
                name: toolCall.name,
                arguments: toolCall.inputJson  // Store raw JSON string
            )
            pendingToolCalls.append(toolCallInfo)

            Logger.debug("🔧 Anthropic: Tool call finalized: \(toolCall.name)", category: .ai)
            currentToolCall = nil
        }

        return []
    }

    private mutating func handleMessageDelta(_ event: AnthropicMessageDeltaEvent) -> [OnboardingEvent] {
        // Update token counts from final usage
        if let usage = event.usage {
            if let output = usage.outputTokens {
                outputTokens = output
            }
            if let input = usage.inputTokens {
                inputTokens = input
            }
            if let cacheRead = usage.cacheReadInputTokens {
                cacheReadTokens = cacheRead
            }
            if let cacheCreation = usage.cacheCreationInputTokens {
                cacheCreationTokens = cacheCreation
            }
        }

        return []
    }

    private mutating func handleMessageStop() -> [OnboardingEvent] {
        guard let id = messageId else { return [] }

        var events: [OnboardingEvent] = []

        // Finalize the message
        events.append(.llm(.streamingMessageFinalized(
            id: id,
            finalText: accumulatedText,
            toolCalls: pendingToolCalls.isEmpty ? nil : pendingToolCalls,
            statusMessage: nil
        )))

        // Emit token usage with distinct cache read/creation counts.
        // This log line is the regression test for prompt caching: from turn 2
        // within a phase, cacheRead should be ≈ the full prompt minus the latest turn.
        Logger.info(
            "📊 Anthropic request usage: input=\(inputTokens) cacheRead=\(cacheReadTokens) cacheCreate=\(cacheCreationTokens) output=\(outputTokens)",
            category: .ai
        )
        events.append(.llm(.tokenUsageReceived(
            modelId: modelId,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheReadTokens: cacheReadTokens,
            cacheCreationTokens: cacheCreationTokens,
            reasoningTokens: 0,  // Extended thinking would go here if enabled
            source: .mainCoordinator
        )))

        // Emit tool call events for each pending tool call
        for toolCallInfo in pendingToolCalls {
            // Parse arguments string to JSON for ToolCall
            let argsJSON = JSON(parseJSON: toolCallInfo.arguments)
            let call = ToolCall(
                name: toolCallInfo.name,
                arguments: argsJSON,
                callId: toolCallInfo.id  // Anthropic tool_use.id serves as callId
            )
            // Display tool name as code symbol
            events.append(.tool(.callRequested(call, statusMessage: "\(toolCallInfo.name)()")))
        }

        // Emit batch started event for any tool calls (including single tool)
        // StreamQueue needs this to know when it's safe to release tool responses
        if !pendingToolCalls.isEmpty {
            let callIds = pendingToolCalls.map { $0.id }
            events.append(.llm(.toolCallBatchStarted(expectedCount: pendingToolCalls.count, callIds: callIds)))
        }

        // Reset state
        messageId = nil
        accumulatedText = ""
        pendingToolCalls = []
        inputTokens = 0
        outputTokens = 0
        cacheReadTokens = 0
        cacheCreationTokens = 0

        return events
    }

    // MARK: - Stream Cancellation

    /// Called when the stream is cancelled to finalize any partial content
    mutating func finalizeCancelled() -> [OnboardingEvent] {
        guard let id = messageId else { return [] }

        // Finalize with whatever we have
        return [.llm(.streamingMessageFinalized(
            id: id,
            finalText: accumulatedText,
            toolCalls: pendingToolCalls.isEmpty ? nil : pendingToolCalls,
            statusMessage: "Cancelled"
        ))]
    }
}
