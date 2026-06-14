//
//  RecordedStreamEvent.swift
//  Sprung
//
//  A tape-storable projection of one Anthropic SSE stream event.
//
//  WHY THIS EXISTS: `AnthropicStreamEvent` (SwiftOpenAI) is `Decodable`-ONLY, and
//  its associated-value structs have internal memberwise inits — so from the
//  Sprung module the ONLY way to construct an `AnthropicStreamEvent` is to decode
//  it from JSON. The tape recorder, however, observes events AFTER they are
//  decoded (at the `AnthropicService` boundary). So we re-render each decoded
//  event back to the EXACT SSE JSON shape its own decoder reads, store that, and
//  on replay decode it through the REAL `AnthropicStreamEvent.init(from:)`. The
//  forward decode path is the library's, so there is no second reconstruction
//  path to drift from the real one.
//
//  FAITHFULNESS NOTE: a tool-use `content_block_start` carries an EMPTY input on
//  the wire (the tool arguments stream separately as `input_json_delta`
//  `partial_json` text, which we capture verbatim). We therefore omit the content
//  block's `input` field on re-render — the downstream assembler rebuilds tool
//  input from the captured deltas, identically to a live stream.
//

import Foundation
import SwiftOpenAI

/// One recorded SSE event. Stores the decoder-compatible JSON as a string so the
/// tape stays human-inspectable and replay round-trips through the library decoder.
struct RecordedStreamEvent: Codable, Sendable {
    /// The Anthropic SSE event re-rendered as the exact JSON `AnthropicStreamEvent`
    /// decodes from (snake_case keys, discriminated by `type`).
    let sseJSON: String

    init(sseJSON: String) {
        self.sseJSON = sseJSON
    }

    /// Capture: project a live, decoded event back to its SSE JSON.
    init(capturing event: AnthropicStreamEvent) {
        let object = RecordedStreamEvent.sseObject(for: event)
        if let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
           let string = String(data: data, encoding: .utf8) {
            self.sseJSON = string
        } else {
            // Should never happen for the dictionaries we build; fall back to a
            // benign ping so a single malformed event can't abort a recording.
            self.sseJSON = #"{"type":"ping"}"#
        }
    }

    /// Replay: decode back into a real `AnthropicStreamEvent` via the library
    /// decoder — the same path a live response takes.
    func decoded() throws -> AnthropicStreamEvent {
        guard let data = sseJSON.data(using: .utf8) else {
            throw RecordedStreamEventError.invalidJSON
        }
        return try JSONDecoder().decode(AnthropicStreamEvent.self, from: data)
    }

    // MARK: - SSE JSON reconstruction

    /// Build the `[String: Any]` SSE object the Anthropic decoder reads for `event`.
    /// nil fields are OMITTED (the decoder uses `decodeIfPresent` for optionals).
    private static func sseObject(for event: AnthropicStreamEvent) -> [String: Any] {
        switch event {
        case .messageStart(let e):
            return [
                "type": "message_start",
                "message": messageObject(e.message)
            ]
        case .contentBlockStart(let e):
            return [
                "type": "content_block_start",
                "index": e.index,
                "content_block": contentBlockObject(e.contentBlock)
            ]
        case .contentBlockDelta(let e):
            return [
                "type": "content_block_delta",
                "index": e.index,
                "delta": deltaObject(e.delta)
            ]
        case .contentBlockStop(let e):
            return [
                "type": "content_block_stop",
                "index": e.index
            ]
        case .messageDelta(let e):
            var object: [String: Any] = [
                "type": "message_delta",
                "delta": messageDeltaObject(e.delta)
            ]
            if let usage = e.usage {
                object["usage"] = usageObject(usage)
            }
            return object
        case .messageStop:
            return ["type": "message_stop"]
        case .ping:
            return ["type": "ping"]
        case .error(let e):
            return [
                "type": "error",
                "error": ["type": e.error.type, "message": e.error.message]
            ]
        case .unknown(let type):
            return ["type": type]
        }
    }

    private static func messageObject(_ message: AnthropicMessageStartEvent.AnthropicStreamMessage) -> [String: Any] {
        var object: [String: Any] = [
            "id": message.id,
            "type": message.type,
            "role": message.role,
            "model": message.model,
            "content": message.content.map(contentBlockObject),
            "usage": usageObject(message.usage)
        ]
        if let stopReason = message.stopReason { object["stop_reason"] = stopReason }
        if let stopSequence = message.stopSequence { object["stop_sequence"] = stopSequence }
        return object
    }

    private static func contentBlockObject(_ block: AnthropicStreamContentBlock) -> [String: Any] {
        // `input` is intentionally omitted — see the faithfulness note above.
        var object: [String: Any] = ["type": block.type]
        if let text = block.text { object["text"] = text }
        if let id = block.id { object["id"] = id }
        if let name = block.name { object["name"] = name }
        return object
    }

    private static func deltaObject(_ delta: AnthropicContentDelta) -> [String: Any] {
        switch delta {
        case .textDelta(let text):
            return ["type": "text_delta", "text": text]
        case .inputJsonDelta(let partialJson):
            return ["type": "input_json_delta", "partial_json": partialJson]
        case .unknown(let type):
            return ["type": type]
        }
    }

    private static func messageDeltaObject(_ delta: AnthropicMessageDeltaContent) -> [String: Any] {
        var object: [String: Any] = [:]
        if let stopReason = delta.stopReason { object["stop_reason"] = stopReason }
        if let stopSequence = delta.stopSequence { object["stop_sequence"] = stopSequence }
        return object
    }

    private static func usageObject(_ usage: AnthropicStreamUsage) -> [String: Any] {
        var object: [String: Any] = [:]
        if let inputTokens = usage.inputTokens { object["input_tokens"] = inputTokens }
        if let outputTokens = usage.outputTokens { object["output_tokens"] = outputTokens }
        if let cacheCreation = usage.cacheCreationInputTokens { object["cache_creation_input_tokens"] = cacheCreation }
        if let cacheRead = usage.cacheReadInputTokens { object["cache_read_input_tokens"] = cacheRead }
        return object
    }
}

enum RecordedStreamEventError: Error {
    case invalidJSON
}
