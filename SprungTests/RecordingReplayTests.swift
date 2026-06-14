//
//  RecordingReplayTests.swift
//  SprungTests
//
//  Validates the record → store → replay DATA PATH end to end without a live
//  interview: the AnthropicStreamEvent mirror, the tape JSONL round-trip through
//  the real recorder + store, and the replay services' serving contract.
//  (The live turn re-drive — driving the actual interview loop — is exercised
//  separately at runtime; everything below it is covered here.)
//

import XCTest
import SwiftOpenAI
@testable import Sprung

final class RecordingReplayTests: XCTestCase {

    // MARK: - Helpers

    private func streamEvent(from json: String) throws -> AnthropicStreamEvent {
        let data = try XCTUnwrap(json.data(using: .utf8))
        return try JSONDecoder().decode(AnthropicStreamEvent.self, from: data)
    }

    /// One representative line of each Anthropic SSE event kind.
    private static let sampleSSE: [String] = [
        #"{"type":"message_start","message":{"id":"msg_1","type":"message","role":"assistant","content":[],"model":"claude-test","stop_reason":null,"usage":{"input_tokens":12,"output_tokens":1,"cache_read_input_tokens":3}}}"#,
        #"{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#,
        #"{"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"toolu_42","name":"glob"}}"#,
        #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello world"}}"#,
        #"{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"pattern\":\"*.swift\"}"}}"#,
        #"{"type":"content_block_stop","index":0}"#,
        #"{"type":"message_delta","delta":{"stop_reason":"tool_use","stop_sequence":null},"usage":{"output_tokens":57}}"#,
        #"{"type":"message_stop"}"#,
        #"{"type":"ping"}"#,
        #"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#,
    ]

    // MARK: - Stream-event mirror

    /// capture → decode → re-capture must be byte-idempotent for every event kind:
    /// the recorded SSE JSON re-decodes through the REAL library decoder and
    /// re-captures to the identical bytes. This is the load-bearing invariant —
    /// replay re-emits exactly what was recorded.
    func testStreamEventMirrorIsByteIdempotent() throws {
        for json in Self.sampleSSE {
            let original = try streamEvent(from: json)
            let captured = RecordedStreamEvent(capturing: original)
            let reCaptured = RecordedStreamEvent(capturing: try captured.decoded())
            XCTAssertEqual(captured.sseJSON, reCaptured.sseJSON,
                           "mirror not idempotent for SSE: \(json)")
        }
    }

    /// Salient fields survive the capture→decode round-trip (spot checks across kinds).
    func testStreamEventMirrorPreservesSalientFields() throws {
        let messageStart = try RecordedStreamEvent(capturing: streamEvent(from: Self.sampleSSE[0])).decoded()
        XCTAssertEqual(messageStart.messageId, "msg_1")
        XCTAssertEqual(messageStart.usage?.inputTokens, 12)
        XCTAssertEqual(messageStart.usage?.cacheReadInputTokens, 3)

        let toolStart = try RecordedStreamEvent(capturing: streamEvent(from: Self.sampleSSE[2])).decoded()
        XCTAssertTrue(toolStart.isToolUseStart)
        XCTAssertEqual(toolStart.toolUseInfo?.id, "toolu_42")
        XCTAssertEqual(toolStart.toolUseInfo?.name, "glob")

        let textDelta = try RecordedStreamEvent(capturing: streamEvent(from: Self.sampleSSE[3])).decoded()
        XCTAssertEqual(textDelta.textDelta, "Hello world")

        let jsonDelta = try RecordedStreamEvent(capturing: streamEvent(from: Self.sampleSSE[4])).decoded()
        XCTAssertEqual(jsonDelta.toolInputPartialJson, #"{"pattern":"*.swift"}"#)

        let messageDelta = try RecordedStreamEvent(capturing: streamEvent(from: Self.sampleSSE[6])).decoded()
        XCTAssertEqual(messageDelta.stopReason, "tool_use")
        XCTAssertEqual(messageDelta.usage?.outputTokens, 57)
    }

    // MARK: - Tape JSONL round-trip via the real recorder + store

    func testRecorderStoreFileRoundTrip() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("SprungRecTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let sessionId = "session-A"
        let recorder = SessionTapeRecorder(recordingsRoot: tempRoot)
        await recorder.start(sessionId: sessionId, modelId: "claude-test")

        // Turn 0: a model stream, a user message, and a tool result.
        let turn0 = TapeModelStream(
            turnIndex: await recorder.nextModelTurnIndex(),
            events: try Self.sampleSSE.map { RecordedStreamEvent(capturing: try streamEvent(from: $0)) }
        )
        await recorder.recordModelStream(turnIndex: turn0.turnIndex, events: turn0.events)
        await recorder.recordUserMessage(entryId: "entry-1", wireText: "hi there",
                                         attachmentBase64: nil, attachmentMediaType: nil,
                                         isSystemGenerated: false)
        await recorder.recordToolResult(callId: "toolu_42", name: "glob", argumentsJSON: nil,
                                        output: "a.swift\nb.swift", status: "completed", mintedIds: [])
        await recorder.stop()

        let store = TapeStore(recordingsRoot: tempRoot)

        // Enumeration sees the session with correct counts.
        let sessions = await store.listSessions()
        XCTAssertEqual(sessions.count, 1)
        let summary = try XCTUnwrap(sessions.first)
        XCTAssertEqual(summary.sessionId, sessionId)
        XCTAssertEqual(summary.modelId, "claude-test")
        XCTAssertEqual(summary.turnCount, 1)
        XCTAssertEqual(summary.userMessageCount, 1)
        XCTAssertEqual(summary.toolResultCount, 1)

        // Events round-trip in order (header first).
        let events = try await store.loadEvents(sessionId: sessionId)
        guard case .header(let header) = events.first else {
            return XCTFail("first tape line must be the header")
        }
        XCTAssertEqual(header.sessionId, sessionId)
        XCTAssertEqual(header.schemaVersion, TapeSchema.version)

        // The model stream round-trips byte-for-byte through the file.
        let streams = try await store.loadModelStreams(sessionId: sessionId)
        let loaded0 = try XCTUnwrap(streams[0])
        XCTAssertEqual(loaded0.events.map(\.sseJSON), turn0.events.map(\.sseJSON))

        // The tool result is keyed by callId and served verbatim.
        let tools = try await store.loadToolResults(sessionId: sessionId)
        XCTAssertEqual(tools["toolu_42"]?.output, "a.swift\nb.swift")
        XCTAssertEqual(tools["toolu_42"]?.status, "completed")
    }

    func testStoreSkipsMalformedLines() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("SprungRecTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let sessionId = "session-B"
        let dir = RecordingPaths.sessionDirectory(sessionId, in: tempRoot)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let header = try JSONEncoder().encode(TapeEvent.header(
            TapeHeader(sessionId: sessionId, schemaVersion: TapeSchema.version, recordedAt: "", modelId: nil)))
        var contents = String(decoding: header, as: UTF8.self) + "\n"
        contents += "this is not valid json\n"   // a corrupt/partially-flushed line
        let good = try JSONEncoder().encode(TapeEvent.coordinatorTurn(
            TapeCoordinatorTurn(turnIndex: 0, text: "ok", anchorEntryId: nil)))
        contents += String(decoding: good, as: UTF8.self) + "\n"
        try contents.write(to: RecordingPaths.tapeFile(sessionId, in: tempRoot), atomically: true, encoding: .utf8)

        let events = try await TapeStore(recordingsRoot: tempRoot).loadEvents(sessionId: sessionId)
        // The malformed middle line is skipped; the two valid lines survive.
        XCTAssertEqual(events.count, 2)
    }

    // MARK: - Turn-index rollback on failed streams (C3a)

    func testRecorderDiscardsFailedTailTurnForReuse() async {
        let recorder = SessionTapeRecorder(recordingsRoot: FileManager.default.temporaryDirectory)
        let t0 = await recorder.nextModelTurnIndex()       // 0
        let t1 = await recorder.nextModelTurnIndex()       // 1
        await recorder.discardClaimedModelTurn(t1)         // tail discard → roll back
        let reused = await recorder.nextModelTurnIndex()   // 1 reused (contiguous)
        XCTAssertEqual([t0, t1, reused], [0, 1, 1])

        // A non-tail discard is a no-op (only the most-recent claim rolls back).
        await recorder.discardClaimedModelTurn(t0)
        let next = await recorder.nextModelTurnIndex()     // 2, unaffected
        XCTAssertEqual(next, 2)
    }

    // MARK: - Replay services

    func testReplayServiceServesByTurnOrder() async throws {
        let turn0 = TapeModelStream(turnIndex: 0, events: [
            RecordedStreamEvent(capturing: try streamEvent(from: Self.sampleSSE[3]))
        ])
        let turn1 = TapeModelStream(turnIndex: 1, events: [
            RecordedStreamEvent(capturing: try streamEvent(from: Self.sampleSSE[6]))
        ])
        let service = ReplayAnthropicService(modelStreams: [0: turn0, 1: turn1])

        let dummyParams = AnthropicMessageParameter(model: "x", messages: [], maxTokens: 1)

        let first = try await collect(service.messagesStream(parameters: dummyParams))
        XCTAssertEqual(first.first?.textDelta, "Hello world")

        let second = try await collect(service.messagesStream(parameters: dummyParams))
        XCTAssertEqual(second.first?.stopReason, "tool_use")

        // A third request (no turn 2 recorded) throws — never falls through to network.
        do {
            _ = try await service.messagesStream(parameters: dummyParams)
            XCTFail("expected noRecordedTurn for turn 2")
        } catch let error as ReplayError {
            guard case .noRecordedTurn(let idx) = error else {
                return XCTFail("expected noRecordedTurn, got \(error)")
            }
            XCTAssertEqual(idx, 2)
        } catch {
            XCTFail("expected ReplayError, got \(error)")
        }
    }

    func testReplayServiceUnsupportedOpsThrow() async {
        let service = ReplayAnthropicService(modelStreams: [:])
        do {
            _ = try await service.uploadFile(data: Data(), filename: "f", mimeType: "application/pdf")
            XCTFail("uploadFile must throw during replay")
        } catch let error as ReplayError {
            guard case .unsupported = error else { return XCTFail("expected .unsupported") }
        } catch {
            XCTFail("expected ReplayError, got \(error)")
        }
    }

    @MainActor
    func testReplayToolGatewayServesByCallId() {
        let result = TapeToolResult(turnIndex: 0, callId: "toolu_42", name: "glob",
                                    argumentsJSON: nil, output: "a.swift", status: "completed", mintedIds: nil)
        let gateway = ReplayToolGateway(toolResults: ["toolu_42": result])
        XCTAssertEqual(gateway.recordedResult(callId: "toolu_42")?.output, "a.swift")
        XCTAssertTrue(gateway.hasRecordedResult(callId: "toolu_42"))
        XCTAssertNil(gateway.recordedResult(callId: "nope"))
    }

    // MARK: - Stream collection helper

    private func collect(_ stream: AsyncThrowingStream<AnthropicStreamEvent, Error>) async throws -> [AnthropicStreamEvent] {
        var events: [AnthropicStreamEvent] = []
        for try await event in stream { events.append(event) }
        return events
    }
}
