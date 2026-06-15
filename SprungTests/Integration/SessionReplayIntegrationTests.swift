//
//  SessionReplayIntegrationTests.swift
//  SprungTests
//
//  Phase 6 capstone. The component tests (RecordingReplayTests, DeterminismSeamTests)
//  each prove one link of the record → store → replay → determinism chain in isolation.
//  These tests wire the whole chain together through the REAL recorder and store, with no
//  live model and no network:
//   - a multi-turn session, recorded to JSONL and replayed back, reconstructs turn-by-turn
//     (model streams served in order by ReplayAnthropicService; tool results resolved by
//     callId through ReplayToolGateway) — exactly the data a live re-drive consumes;
//   - the ids a tool mints under recording, persisted in the tape's `mintedIds` field,
//     reproduce identically on replay — the property that lets a re-executed "create" keep
//     the id a later recorded "update" references.
//
//  The live turn re-drive on top of this (SessionReplayController + the full onboarding
//  coordinator) is exercised at runtime; everything beneath it is covered here.
//

import XCTest
import SwiftOpenAI
@testable import Sprung

@MainActor
final class SessionReplayIntegrationTests: XCTestCase {

    // MARK: - Helpers

    private func streamEvent(from json: String) throws -> AnthropicStreamEvent {
        let data = try XCTUnwrap(json.data(using: .utf8))
        return try JSONDecoder().decode(AnthropicStreamEvent.self, from: data)
    }

    private func collect(_ stream: AsyncThrowingStream<AnthropicStreamEvent, Error>) async throws -> [AnthropicStreamEvent] {
        var events: [AnthropicStreamEvent] = []
        for try await event in stream { events.append(event) }
        return events
    }

    private func tempRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("SprungReplayIT-\(UUID().uuidString)", isDirectory: true)
    }

    /// Turn 0: the model calls a tool (`toolu_glob`, name `glob`). Turn 1: it answers in text.
    private static let turn0SSE: [String] = [
        #"{"type":"message_start","message":{"id":"msg_t0","type":"message","role":"assistant","content":[],"model":"claude-test","stop_reason":null,"usage":{"input_tokens":10,"output_tokens":1}}}"#,
        #"{"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu_glob","name":"glob"}}"#,
        #"{"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\"pattern\":\"*.swift\"}"}}"#,
        #"{"type":"content_block_stop","index":0}"#,
        #"{"type":"message_delta","delta":{"stop_reason":"tool_use","stop_sequence":null},"usage":{"output_tokens":20}}"#,
        #"{"type":"message_stop"}"#,
    ]
    private static let turn1SSE: [String] = [
        #"{"type":"message_start","message":{"id":"msg_t1","type":"message","role":"assistant","content":[],"model":"claude-test","stop_reason":null,"usage":{"input_tokens":40,"output_tokens":1}}}"#,
        #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Found 2 files."}}"#,
        #"{"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":8}}"#,
        #"{"type":"message_stop"}"#,
    ]

    // MARK: - Multi-turn reconstruction

    func testMultiTurnSessionRecordsStoresAndReplaysInOrder() async throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        // --- Record a two-turn session through the real recorder ---
        let sessionId = "session-IT"
        let recorder = SessionTapeRecorder(recordingsRoot: root)
        await recorder.start(sessionId: sessionId, modelId: "claude-test")

        let t0 = await recorder.nextModelTurnIndex()
        let turn0 = TapeModelStream(
            turnIndex: t0,
            events: try Self.turn0SSE.map { RecordedStreamEvent(capturing: try streamEvent(from: $0)) }
        )
        await recorder.recordModelStream(turnIndex: t0, events: turn0.events)
        // The tool the model called, resolved and recorded.
        await recorder.recordToolResult(callId: "toolu_glob", name: "glob", argumentsJSON: #"{"pattern":"*.swift"}"#,
                                        output: "a.swift\nb.swift", status: "completed", mintedIds: [])

        let t1 = await recorder.nextModelTurnIndex()
        let turn1 = TapeModelStream(
            turnIndex: t1,
            events: try Self.turn1SSE.map { RecordedStreamEvent(capturing: try streamEvent(from: $0)) }
        )
        await recorder.recordModelStream(turnIndex: t1, events: turn1.events)
        await recorder.stop()

        // --- Load it back from disk ---
        let store = TapeStore(recordingsRoot: root)
        let sessions = await store.listSessions()
        let summary = try XCTUnwrap(sessions.first)
        XCTAssertEqual(summary.turnCount, 2, "two model turns recorded")
        XCTAssertEqual(summary.toolResultCount, 1)

        let streams = try await store.loadModelStreams(sessionId: sessionId)
        let toolResults = try await store.loadToolResults(sessionId: sessionId)

        // --- Replay the whole session offline ---
        let replayService = ReplayAnthropicService(modelStreams: streams)
        let gateway = ReplayToolGateway(toolResults: toolResults)
        let dummy = AnthropicMessageParameter(model: "x", messages: [], maxTokens: 1)

        // Turn 0 serves the tool-use stream, and its tool resolves by callId.
        let served0 = try await collect(replayService.messagesStream(parameters: dummy))
        XCTAssertTrue(served0.contains { $0.isToolUseStart && $0.toolUseInfo?.id == "toolu_glob" },
                      "turn 0 must replay the recorded tool_use block")
        let resolved = try XCTUnwrap(gateway.recordedResult(callId: "toolu_glob"),
                                     "the tool call from turn 0 must resolve through the gateway")
        XCTAssertEqual(resolved.output, "a.swift\nb.swift")
        XCTAssertEqual(resolved.status, "completed")

        // Turn 1 serves the final text answer.
        let served1 = try await collect(replayService.messagesStream(parameters: dummy))
        XCTAssertTrue(served1.contains { $0.textDelta == "Found 2 files." },
                      "turn 1 must replay the recorded text answer")

        // The session has exactly two turns — a third request never falls through to network.
        do {
            _ = try await replayService.messagesStream(parameters: dummy)
            XCTFail("a third turn was never recorded; replay must refuse it")
        } catch let error as ReplayError {
            guard case .noRecordedTurn(let idx) = error else {
                return XCTFail("expected noRecordedTurn, got \(error)")
            }
            XCTAssertEqual(idx, 2)
        }
    }

    func testModelStreamSurvivesTheFileRoundTripByteForByte() async throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let recorder = SessionTapeRecorder(recordingsRoot: root)
        await recorder.start(sessionId: "session-bytes", modelId: "claude-test")
        let idx = await recorder.nextModelTurnIndex()
        let events = try Self.turn0SSE.map { RecordedStreamEvent(capturing: try streamEvent(from: $0)) }
        await recorder.recordModelStream(turnIndex: idx, events: events)
        await recorder.stop()

        let streams = try await TapeStore(recordingsRoot: root).loadModelStreams(sessionId: "session-bytes")
        let loaded = try XCTUnwrap(streams[idx])
        // The exact SSE bytes survive record → JSONL → load, so replay re-emits what was recorded.
        XCTAssertEqual(loaded.events.map(\.sseJSON), events.map(\.sseJSON))
    }

    // MARK: - Determinism re-execution through a recorded tape

    /// The full faithfulness property: ids a tool mints under recording, persisted to the
    /// tape and read back, reproduce identically when replay re-executes that tool.
    func testMintedIdsPersistedInTapeReproduceOnReplay() async throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        // --- Record: a "create" tool mints ids under a recording scope ---
        let recording = DeterminismContext(mode: .recording)
        let mintedDuringRecord = DeterminismScope.$current.withValue(recording) {
            [DeterminismIDProvider.nextUUID(), DeterminismIDProvider.nextUUID()]
        }

        let recorder = SessionTapeRecorder(recordingsRoot: root)
        await recorder.start(sessionId: "session-det", modelId: "claude-test")
        await recorder.recordToolResult(callId: "toolu_create", name: "create_timeline_card",
                                        argumentsJSON: nil, output: #"{"id":"\#(mintedDuringRecord[0])"}"#,
                                        status: "completed", mintedIds: recording.mintedIds)
        await recorder.stop()

        // --- Load: the mintedIds field round-trips through the JSONL ---
        let toolResults = try await TapeStore(recordingsRoot: root).loadToolResults(sessionId: "session-det")
        let recorded = try XCTUnwrap(toolResults["toolu_create"])
        XCTAssertEqual(recorded.mintedIds, mintedDuringRecord,
                       "the tape must persist exactly the ids minted during recording")

        // --- Replay: re-executing the tool under the recorded seed reproduces the ids ---
        let replaying = DeterminismContext(mode: .replaying(try XCTUnwrap(recorded.mintedIds)))
        let mintedDuringReplay = DeterminismScope.$current.withValue(replaying) {
            [DeterminismIDProvider.nextUUID(), DeterminismIDProvider.nextUUID()]
        }
        XCTAssertEqual(mintedDuringReplay, mintedDuringRecord,
                       "replay re-execution must reproduce the recorded id sequence exactly")
        XCTAssertFalse(replaying.didExhaust, "serving exactly the recorded count must not exhaust")
    }
}
