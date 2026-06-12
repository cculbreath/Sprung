import Foundation
import SwiftOpenAI

// MARK: - Stream Events

/// Domain events produced by the revision stream processor.
enum RevisionStreamEvent {
    case textDelta(String)
    case textFinalized(String)
    case toolCallReady(id: String, name: String, arguments: String)
    /// Stop reason from `message_delta` (e.g. "end_turn", "tool_use",
    /// "max_tokens"). Surfaced so the loop can detect truncated output.
    case stopReason(String)
    /// Final per-turn token usage, assembled from `message_start` (input and
    /// cache fields) and `message_delta` (final output). Emitted at
    /// `message_stop` so the loop can log per-turn cache hit rates and
    /// accumulate session totals.
    case usage(inputTokens: Int, cacheReadTokens: Int, cacheCreationTokens: Int, outputTokens: Int)
    /// In-stream `error` event, formatted "type: message". Surfaced so the
    /// loop can classify it and back off or abort instead of retrying blind.
    case streamError(String)
}

// MARK: - Stream Processor

/// Processes Anthropic stream events into domain events for the revision agent.
/// Based on AnthropicStreamAdapter but simplified for non-onboarding context.
struct RevisionStreamProcessor {
    private var accumulatedText: String = ""
    private var currentToolCall: PartialToolCall?
    private var pendingToolCalls: [ToolCallInfo] = []

    // Per-turn token usage. input/cache fields arrive on message_start; the
    // final output count arrives on message_delta. Surfaced as one .usage
    // event at message_stop.
    private var inputTokens = 0
    private var cacheReadTokens = 0
    private var cacheCreationTokens = 0
    private var outputTokens = 0

    struct ToolCallInfo {
        let id: String
        let name: String
        let arguments: String
    }

    private struct PartialToolCall {
        let id: String
        let name: String
        var inputJson: String = ""
    }

    /// Process an Anthropic stream event and return domain events.
    mutating func process(_ event: AnthropicStreamEvent) -> [RevisionStreamEvent] {
        switch event {
        case .messageStart(let event):
            accumulatedText = ""
            pendingToolCalls = []
            currentToolCall = nil
            inputTokens = event.message.usage.inputTokens ?? 0
            cacheReadTokens = event.message.usage.cacheReadInputTokens ?? 0
            cacheCreationTokens = event.message.usage.cacheCreationInputTokens ?? 0
            outputTokens = event.message.usage.outputTokens ?? 0
            return []

        case .contentBlockStart(let blockStart):
            if blockStart.contentBlock.type == "tool_use",
               let id = blockStart.contentBlock.id,
               let name = blockStart.contentBlock.name {
                currentToolCall = PartialToolCall(id: id, name: name)
            }
            return []

        case .contentBlockDelta(let delta):
            switch delta.delta {
            case .textDelta(let text):
                accumulatedText += text
                return [.textDelta(text)]
            case .inputJsonDelta(let partialJson):
                currentToolCall?.inputJson += partialJson
                return []
            case .unknown:
                return []
            }

        case .contentBlockStop:
            if let toolCall = currentToolCall {
                pendingToolCalls.append(ToolCallInfo(
                    id: toolCall.id,
                    name: toolCall.name,
                    arguments: toolCall.inputJson
                ))
                currentToolCall = nil
            }
            return []

        case .messageDelta(let event):
            if let usage = event.usage {
                if let input = usage.inputTokens { inputTokens = input }
                if let cacheRead = usage.cacheReadInputTokens { cacheReadTokens = cacheRead }
                if let cacheCreation = usage.cacheCreationInputTokens { cacheCreationTokens = cacheCreation }
                if let output = usage.outputTokens { outputTokens = output }
            }
            if let stopReason = event.delta.stopReason {
                return [.stopReason(stopReason)]
            }
            return []

        case .messageStop:
            var events: [RevisionStreamEvent] = []

            if !accumulatedText.isEmpty {
                events.append(.textFinalized(accumulatedText))
            }

            for toolCall in pendingToolCalls {
                events.append(.toolCallReady(
                    id: toolCall.id,
                    name: toolCall.name,
                    arguments: toolCall.arguments
                ))
            }

            events.append(.usage(
                inputTokens: inputTokens,
                cacheReadTokens: cacheReadTokens,
                cacheCreationTokens: cacheCreationTokens,
                outputTokens: outputTokens
            ))

            // Reset
            accumulatedText = ""
            pendingToolCalls = []
            inputTokens = 0
            cacheReadTokens = 0
            cacheCreationTokens = 0
            outputTokens = 0

            return events

        case .error(let errorEvent):
            return [.streamError("\(errorEvent.error.type): \(errorEvent.error.message)")]

        case .ping, .unknown:
            return []
        }
    }
}
