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
        case .messageStart:
            accumulatedText = ""
            pendingToolCalls = []
            currentToolCall = nil
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
            // Usage fields are intentionally not surfaced here (telemetry is
            // a separate workstream); only the stop reason matters to the loop.
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

            // Reset
            accumulatedText = ""
            pendingToolCalls = []

            return events

        case .error(let errorEvent):
            return [.streamError("\(errorEvent.error.type): \(errorEvent.error.message)")]

        case .ping, .unknown:
            return []
        }
    }
}
