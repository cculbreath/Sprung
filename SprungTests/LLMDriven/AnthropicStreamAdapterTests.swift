//
//  AnthropicStreamAdapterTests.swift
//  SprungTests
//
//  Phase 5 (LLM-driven subsystem tests — pure units).
//
//  Exercises the OUTPUT half of the onboarding Anthropic wire layer:
//  AnthropicStreamAdapter maps decoded Anthropic SSE events to OnboardingEvent
//  domain deltas, holding state across events to reconstruct messages and tool
//  calls. We feed it canned AnthropicStreamEvents (decoded from real SSE JSON,
//  exactly as RecordingReplayTests does) and assert the mapped output — no live
//  model, no LLMFacade, no network.
//

import XCTest
import SwiftOpenAI
import SwiftyJSON
@testable import Sprung

final class AnthropicStreamAdapterTests: XCTestCase {

    // MARK: - SSE decode helper (mirrors RecordingReplayTests)

    private func event(_ json: String) throws -> AnthropicStreamEvent {
        let data = try XCTUnwrap(json.data(using: .utf8))
        return try JSONDecoder().decode(AnthropicStreamEvent.self, from: data)
    }

    // Canonical SSE lines for a text-only turn.
    private static let messageStartText =
        #"{"type":"message_start","message":{"id":"msg_1","type":"message","role":"assistant","content":[],"model":"claude-test","stop_reason":null,"usage":{"input_tokens":12,"output_tokens":1,"cache_read_input_tokens":3,"cache_creation_input_tokens":7}}}"#
    private static let textBlockStart =
        #"{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#
    private static let textDeltaHello =
        #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello "}}"#
    private static let textDeltaWorld =
        #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"world"}}"#
    private static let textBlockStop =
        #"{"type":"content_block_stop","index":0}"#
    private static let messageDeltaEndTurn =
        #"{"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":57}}"#
    private static let messageStop =
        #"{"type":"message_stop"}"#
    private static let ping = #"{"type":"ping"}"#
    private static let errorOverloaded =
        #"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#

    // Tool-use turn lines.
    private static let toolBlockStart =
        #"{"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"toolu_42","name":"glob"}}"#
    private static let toolInputDelta1 =
        #"{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"pattern\":"}}"#
    private static let toolInputDelta2 =
        #"{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"\"*.swift\"}"}}"#
    private static let toolBlockStop =
        #"{"type":"content_block_stop","index":1}"#

    // MARK: - message_start

    func testMessageStartBeginsStreamingMessage() throws {
        var adapter = AnthropicStreamAdapter()
        let events = adapter.process(try event(Self.messageStartText))

        XCTAssertEqual(events.count, 1)
        guard case .llm(.streamingMessageBegan(_, let text, let status)) = events.first else {
            return XCTFail("message_start must emit .llm(.streamingMessageBegan); got \(events)")
        }
        XCTAssertEqual(text, "", "the begin event carries empty text — deltas follow")
        XCTAssertNil(status)
    }

    // MARK: - text deltas

    func testTextDeltaEmitsUpdatedWithSameMessageId() throws {
        var adapter = AnthropicStreamAdapter()
        let beginEvents = adapter.process(try event(Self.messageStartText))
        guard case .llm(.streamingMessageBegan(let beginId, _, _)) = beginEvents.first else {
            return XCTFail("expected begin")
        }
        _ = adapter.process(try event(Self.textBlockStart))

        let deltaEvents = adapter.process(try event(Self.textDeltaHello))
        XCTAssertEqual(deltaEvents.count, 1)
        guard case .llm(.streamingMessageUpdated(let updateId, let delta, _)) = deltaEvents.first else {
            return XCTFail("text_delta must emit .streamingMessageUpdated; got \(deltaEvents)")
        }
        XCTAssertEqual(delta, "Hello ", "the delta text is passed through verbatim")
        XCTAssertEqual(updateId, beginId, "update id must match the begin id (single message)")
    }

    func testTextDeltaBeforeMessageStartEmitsNothing() throws {
        // No messageId yet — a stray delta cannot key to a message, so the adapter
        // emits no update (guarded on `if let id = messageId`).
        var adapter = AnthropicStreamAdapter()
        let events = adapter.process(try event(Self.textDeltaHello))
        XCTAssertTrue(events.isEmpty, "a text delta with no active message emits nothing; got \(events)")
    }

    // MARK: - accumulation + finalization (text-only turn)

    func testTextOnlyTurnFinalizesWithAccumulatedText() throws {
        var adapter = AnthropicStreamAdapter()
        _ = adapter.process(try event(Self.messageStartText))
        _ = adapter.process(try event(Self.textBlockStart))
        _ = adapter.process(try event(Self.textDeltaHello))
        _ = adapter.process(try event(Self.textDeltaWorld))
        _ = adapter.process(try event(Self.textBlockStop))
        _ = adapter.process(try event(Self.messageDeltaEndTurn))
        let stopEvents = adapter.process(try event(Self.messageStop))

        // message_stop emits: finalized + token usage (and NO tool events here).
        var finalText: String?
        var sawFinalized = false
        var finalizedToolCallCount = -1   // -1 == nil toolCalls; >= 0 == count
        var sawTokenUsage = false
        for e in stopEvents {
            switch e {
            case .llm(.streamingMessageFinalized(_, let text, let calls, _)):
                finalText = text
                sawFinalized = true
                finalizedToolCallCount = calls?.count ?? -1
            case .llm(.tokenUsageReceived):
                sawTokenUsage = true
            default:
                break
            }
        }
        XCTAssertTrue(sawFinalized, "expected a finalized event")
        XCTAssertEqual(finalText, "Hello world", "accumulated deltas concatenate in order")
        XCTAssertEqual(finalizedToolCallCount, -1, "a text-only turn finalizes with nil toolCalls")
        XCTAssertTrue(sawTokenUsage, "message_stop must emit token usage")
    }

    func testFinalizedTokenUsageReportsCacheReadAndCreationDistinctly() throws {
        var adapter = AnthropicStreamAdapter()
        _ = adapter.process(try event(Self.messageStartText))   // cacheRead=3, cacheCreate=7, input=12
        _ = adapter.process(try event(Self.messageDeltaEndTurn)) // output -> 57
        let stopEvents = adapter.process(try event(Self.messageStop))

        var usage: (input: Int, output: Int, cacheRead: Int, cacheCreate: Int, model: String)?
        for e in stopEvents {
            if case .llm(.tokenUsageReceived(let model, let input, let output, let cacheRead, let cacheCreate, _, _)) = e {
                usage = (input, output, cacheRead, cacheCreate, model)
            }
        }
        let u = try XCTUnwrap(usage, "message_stop must emit tokenUsageReceived")
        XCTAssertEqual(u.model, "claude-test")
        XCTAssertEqual(u.input, 12)
        XCTAssertEqual(u.output, 57, "final usage from message_delta overrides the message_start estimate")
        XCTAssertEqual(u.cacheRead, 3, "cache read tokens reported distinctly")
        XCTAssertEqual(u.cacheCreate, 7, "cache creation tokens reported distinctly")
    }

    // MARK: - tool-use turn

    func testToolUseTurnFinalizesWithToolCallAndBatchEvents() throws {
        var adapter = AnthropicStreamAdapter()
        _ = adapter.process(try event(Self.messageStartText))
        // Tool block: start -> input json (split across two deltas) -> stop.
        XCTAssertTrue(adapter.process(try event(Self.toolBlockStart)).isEmpty,
                      "tool_use content_block_start emits no domain event")
        XCTAssertTrue(adapter.process(try event(Self.toolInputDelta1)).isEmpty,
                      "input_json_delta accumulates silently")
        XCTAssertTrue(adapter.process(try event(Self.toolInputDelta2)).isEmpty)
        XCTAssertTrue(adapter.process(try event(Self.toolBlockStop)).isEmpty,
                      "content_block_stop finalizes the tool call but emits no event yet")

        let stopEvents = adapter.process(try event(Self.messageStop))

        var finalizedToolCalls: [OnboardingMessage.ToolCallInfo]?
        var callRequested: Sprung.ToolCall?   // disambiguate from SwiftOpenAI.ToolCall
        var batch: (count: Int, ids: [String])?
        for e in stopEvents {
            switch e {
            case .llm(.streamingMessageFinalized(_, _, let calls, _)):
                finalizedToolCalls = calls
            case .tool(.callRequested(let call, _)):
                callRequested = call
            case .llm(.toolCallBatchStarted(let expected, let ids)):
                batch = (expected, ids)
            default:
                break
            }
        }

        // Finalized message carries the pending tool call (raw args string).
        let calls = try XCTUnwrap(finalizedToolCalls, "tool turn finalizes with non-nil toolCalls")
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.id, "toolu_42")
        XCTAssertEqual(calls.first?.name, "glob")
        XCTAssertEqual(calls.first?.arguments, #"{"pattern":"*.swift"}"#,
                       "input_json_delta fragments accumulate into the raw arguments string")

        // A callRequested event carries the parsed JSON arguments.
        let call = try XCTUnwrap(callRequested, "tool turn must emit .tool(.callRequested)")
        XCTAssertEqual(call.name, "glob")
        XCTAssertEqual(call.callId, "toolu_42")
        XCTAssertEqual(call.arguments["pattern"].stringValue, "*.swift",
                       "callId-keyed JSON arguments are parsed from the accumulated string")

        // A batch-started event lists the call ids for the queue manager.
        let b = try XCTUnwrap(batch, "any tool call must emit .toolCallBatchStarted")
        XCTAssertEqual(b.count, 1)
        XCTAssertEqual(b.ids, ["toolu_42"])
    }

    // MARK: - error / ping passthrough

    func testErrorEventMapsToProcessingError() throws {
        var adapter = AnthropicStreamAdapter()
        let events = adapter.process(try event(Self.errorOverloaded))
        XCTAssertEqual(events.count, 1)
        guard case .processing(.errorOccurred(let message)) = events.first else {
            return XCTFail("error event must map to .processing(.errorOccurred); got \(events)")
        }
        XCTAssertEqual(message, "Overloaded", "the Anthropic error message is surfaced verbatim")
    }

    func testPingEmitsNothing() throws {
        var adapter = AnthropicStreamAdapter()
        XCTAssertTrue(adapter.process(try event(Self.ping)).isEmpty, "ping is a keep-alive — no domain event")
    }

    // MARK: - state reset between turns

    func testMessageStopResetsStateForNextTurn() throws {
        var adapter = AnthropicStreamAdapter()
        // Turn 1
        _ = adapter.process(try event(Self.messageStartText))
        _ = adapter.process(try event(Self.textDeltaHello))
        _ = adapter.process(try event(Self.messageStop))
        // Turn 2: a stray delta arriving before the next message_start must NOT
        // re-emit turn 1's accumulated text (state was reset at message_stop).
        let strayEvents = adapter.process(try event(Self.textDeltaWorld))
        XCTAssertTrue(strayEvents.isEmpty,
                      "after message_stop the messageId is cleared, so a stray delta emits nothing")
    }

    // MARK: - cancellation

    func testFinalizeCancelledEmitsPartialWithCancelledStatus() throws {
        var adapter = AnthropicStreamAdapter()
        _ = adapter.process(try event(Self.messageStartText))
        _ = adapter.process(try event(Self.textDeltaHello))
        let events = adapter.finalizeCancelled()

        XCTAssertEqual(events.count, 1)
        guard case .llm(.streamingMessageFinalized(_, let text, let calls, let status)) = events.first else {
            return XCTFail("finalizeCancelled must emit .streamingMessageFinalized; got \(events)")
        }
        XCTAssertEqual(text, "Hello ", "cancellation finalizes with whatever text accumulated")
        XCTAssertNil(calls, "no completed tool calls before cancellation")
        XCTAssertEqual(status, "Cancelled")
    }

    func testFinalizeCancelledWithNoActiveMessageEmitsNothing() {
        var adapter = AnthropicStreamAdapter()
        XCTAssertTrue(adapter.finalizeCancelled().isEmpty,
                      "no active message -> cancellation emits nothing")
    }
}
