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

    // MARK: - Synthetic-tape restore end-to-end (through the real replay + registration seam)

    /// Turn 0: the model calls `glob`. Turn 1: it answers in text. Each carries a
    /// `usage` block so the tape looks like a real recording.
    private static let restoreTurn0SSE: [String] = [
        #"{"type":"message_start","message":{"id":"msg_r0","type":"message","role":"assistant","content":[],"model":"claude-test","stop_reason":null,"usage":{"input_tokens":10,"output_tokens":1}}}"#,
        #"{"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu_glob","name":"glob"}}"#,
        #"{"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\"pattern\":\"*.swift\"}"}}"#,
        #"{"type":"content_block_stop","index":0}"#,
        #"{"type":"message_delta","delta":{"stop_reason":"tool_use","stop_sequence":null},"usage":{"output_tokens":20}}"#,
        #"{"type":"message_stop"}"#,
    ]
    private static let restoreTurn1SSE: [String] = [
        #"{"type":"message_start","message":{"id":"msg_r1","type":"message","role":"assistant","content":[],"model":"claude-test","stop_reason":null,"usage":{"input_tokens":40,"output_tokens":1}}}"#,
        #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Found 2 files."}}"#,
        #"{"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":8}}"#,
        #"{"type":"message_stop"}"#,
    ]

    /// Drives the full RESTORE data flow — build a synthetic tape in-code, load it
    /// back through the real store, install replay over a live service, re-serve
    /// every recorded turn, then go live — through the SAME pipeline objects the
    /// live re-drive uses below `SessionReplayService` (recorder, store,
    /// `ReplayAnthropicService`, `ReplayToolGateway`) and the SAME registration
    /// object `SessionReplayService.swapToLiveService` swaps against
    /// (`LLMFacadeSpecializedAPIs`, to which `LLMFacade` delegates verbatim). No UI,
    /// no `LLMFacade`, no network. Asserts the three restore guarantees:
    ///   (a) replayed turns issue ZERO live API calls,
    ///   (b) session state (model-turn count + injected user messages) matches the tape,
    ///   (c) the go-live swap installs the live service exactly once.
    @MainActor
    func testSyntheticTapeRestoreServesFromTapeWithZeroLiveCallsThenGoesLiveOnce() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SprungRestoreTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // --- Record a synthetic session through the REAL recorder ---
        // A system-generated opener (re-fires on its own during replay → must NOT be
        // injected) and one user-typed message (must be injected), around two model
        // turns whose tool call resolves from the tape.
        let sessionId = "restore-synthetic"
        let recorder = SessionTapeRecorder(recordingsRoot: root)
        await recorder.start(sessionId: sessionId, modelId: "claude-test")

        await recorder.recordUserMessage(entryId: "opener", wireText: "I'm ready to proceed",
                                         attachmentBase64: nil, attachmentMediaType: nil,
                                         isSystemGenerated: true)
        let t0 = await recorder.nextModelTurnIndex()
        let turn0 = try Self.restoreTurn0SSE.map { RecordedStreamEvent(capturing: try streamEvent(from: $0)) }
        await recorder.recordModelStream(turnIndex: t0, events: turn0)
        await recorder.recordToolResult(callId: "toolu_glob", name: "glob",
                                        argumentsJSON: #"{"pattern":"*.swift"}"#,
                                        output: "a.swift\nb.swift", status: "completed", mintedIds: [])
        await recorder.recordUserMessage(entryId: "u1", wireText: "here is my background",
                                         attachmentBase64: nil, attachmentMediaType: nil,
                                         isSystemGenerated: false)
        let t1 = await recorder.nextModelTurnIndex()
        let turn1 = try Self.restoreTurn1SSE.map { RecordedStreamEvent(capturing: try streamEvent(from: $0)) }
        await recorder.recordModelStream(turnIndex: t1, events: turn1)
        await recorder.stop()

        // --- Load it back exactly as SessionReplayService.restore does ---
        let store = TapeStore(recordingsRoot: root)
        let events = try await store.loadEvents(sessionId: sessionId)
        let modelStreams = try await store.loadModelStreams(sessionId: sessionId)
        let toolResults = try await store.loadToolResults(sessionId: sessionId)

        // (b) Session state matches the tape. This is the EXACT injection predicate
        // SessionReplayService.restore uses — only NON-system-generated user messages
        // are injected; the opener re-fires on its own.
        let userTyped: [TapeUserMessage] = events.compactMap {
            if case .userMessage(let message) = $0, !message.isSystemGenerated { return message }
            return nil
        }
        XCTAssertEqual(modelStreams.count, 2, "two model turns are on the tape")
        XCTAssertEqual(userTyped.map(\.wireText), ["here is my background"],
                       "only the user-typed message is injected; the system opener is filtered out")

        // --- Install replay over the live service, in the REAL registration seam ---
        // LLMFacade.registerAnthropicService/currentAnthropicService delegate straight
        // to this object, so the swap logic exercised here is the production swap.
        let specialized = LLMFacadeSpecializedAPIs()
        let live = CountingAnthropicService()
        specialized.registerAnthropicService(live)
        let savedLive = specialized.currentAnthropicService()   // what go-live restores

        let replay = ReplayAnthropicService(modelStreams: modelStreams)
        let gateway = ReplayToolGateway(toolResults: toolResults)
        specialized.registerAnthropicService(replay)            // replay is now current

        // (a) Drive every recorded turn through the CURRENTLY-registered service (the
        // replay one). The pipeline issues one model request per assistant turn; the
        // tape has exactly two, so two requests serve from the tape and a third
        // refuses rather than falling through to the live API.
        let dummy = AnthropicMessageParameter(model: "x", messages: [], maxTokens: 1)
        let current = try XCTUnwrap(specialized.currentAnthropicService())

        let served0 = try await collect(current.messagesStream(parameters: dummy))
        XCTAssertTrue(served0.contains { $0.toolUseInfo?.id == "toolu_glob" },
                      "turn 0 replays the recorded tool_use block")
        XCTAssertEqual(gateway.recordedResult(callId: "toolu_glob")?.output, "a.swift\nb.swift",
                       "the tool call resolves from the tape — the external tool never re-runs")

        let served1 = try await collect(current.messagesStream(parameters: dummy))
        XCTAssertTrue(served1.contains { $0.textDelta == "Found 2 files." },
                      "turn 1 replays the recorded text answer")

        do {
            _ = try await current.messagesStream(parameters: dummy)
            XCTFail("a third turn was never recorded — replay must refuse it, never hit the live API")
        } catch let error as ReplayError {
            guard case .noRecordedTurn(let idx) = error else { return XCTFail("expected noRecordedTurn, got \(error)") }
            XCTAssertEqual(idx, 2)
        }

        XCTAssertEqual(live.messagesStreamCalls, 0, "replay must issue ZERO live streaming calls")
        XCTAssertEqual(live.nonStreamCalls, 0, "no live files/tokens/models calls during replay")

        // (c) GO LIVE: register the saved live service back and clear the gateway —
        // the exact operations of SessionReplayService.swapToLiveService.
        let restoredLive = try XCTUnwrap(savedLive)
        specialized.registerAnthropicService(restoredLive)
        XCTAssertTrue((specialized.currentAnthropicService() as AnyObject?) === (restoredLive as AnyObject),
                      "go-live restores the exact saved live service")
        XCTAssertFalse((specialized.currentAnthropicService() as AnyObject?) === (replay as AnyObject),
                       "the replay service is no longer installed after go-live")

        // swapToLiveService is documented safe to call repeatedly: a second swap is a
        // no-op that keeps the live service current (installed exactly once, not toggled).
        specialized.registerAnthropicService(restoredLive)
        XCTAssertTrue((specialized.currentAnthropicService() as AnyObject?) === (restoredLive as AnyObject))

        // The next (post-go-live) turn hits the LIVE service exactly once — the real
        // API path has resumed, and it was untouched throughout the replay window.
        _ = try await collect(specialized.anthropicMessagesStream(parameters: dummy))
        XCTAssertEqual(live.messagesStreamCalls, 1, "exactly one live call after go-live, none before")
    }

    // MARK: - Stream collection helper

    private func collect(_ stream: AsyncThrowingStream<AnthropicStreamEvent, Error>) async throws -> [AnthropicStreamEvent] {
        var events: [AnthropicStreamEvent] = []
        for try await event in stream { events.append(event) }
        return events
    }
}

// MARK: - Live-service tripwire

/// A stand-in for the real, live `AnthropicService` saved across a restore. It
/// counts calls so a test can prove the replay window issued ZERO live API calls
/// and that go-live routes exactly one subsequent call back to the live service.
/// Streaming returns an immediately-finishing stream (a successful post-go-live
/// turn); every non-stream endpoint throws — none should ever run.
private final class CountingAnthropicService: AnthropicService, @unchecked Sendable {
    private let lock = NSLock()
    private var _messagesStreamCalls = 0
    private var _nonStreamCalls = 0

    var messagesStreamCalls: Int { lock.lock(); defer { lock.unlock() }; return _messagesStreamCalls }
    var nonStreamCalls: Int { lock.lock(); defer { lock.unlock() }; return _nonStreamCalls }

    private enum ProbeError: Error { case unexpectedNonStreamCall(String) }

    private func countNonStream(_ op: String) throws -> Never {
        lock.lock(); _nonStreamCalls += 1; lock.unlock()
        throw ProbeError.unexpectedNonStreamCall(op)
    }

    func messagesStream(parameters: AnthropicMessageParameter) async throws -> AsyncThrowingStream<AnthropicStreamEvent, Error> {
        lock.lock(); _messagesStreamCalls += 1; lock.unlock()
        return AsyncThrowingStream { $0.finish() }
    }

    func messages(parameters: AnthropicMessageParameter) async throws -> AnthropicMessageResponse { try countNonStream("messages") }
    func listModels() async throws -> AnthropicModelsResponse { try countNonStream("listModels") }
    func retrieveModel(id: String) async throws -> AnthropicModel { try countNonStream("retrieveModel") }
    func countTokens(parameters: AnthropicTokenCountParameter) async throws -> AnthropicTokenCountResponse { try countNonStream("countTokens") }
    func uploadFile(data: Data, filename: String, mimeType: String) async throws -> AnthropicFileMetadata { try countNonStream("uploadFile") }
    func retrieveFileMetadata(id: String) async throws -> AnthropicFileMetadata { try countNonStream("retrieveFileMetadata") }
    func listFiles() async throws -> AnthropicFileListResponse { try countNonStream("listFiles") }
    func deleteFile(id: String) async throws -> AnthropicFileDeletedResponse { try countNonStream("deleteFile") }
}
