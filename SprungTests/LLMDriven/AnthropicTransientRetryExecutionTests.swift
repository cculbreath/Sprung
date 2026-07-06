//
//  AnthropicTransientRetryExecutionTests.swift
//  SprungTests
//
//  Exercises the transient-retry chokepoints in `LLMFacadeSpecializedAPIs`
//  against a scripted `AnthropicService` — no LLMFacade, no network.
//
//  The two retried chokepoints cover every long-run Anthropic caller:
//  - `anthropicMessages` (non-streaming): every agent loop's `runModelTurn`
//    (git analysis, card/background merge, Discovery daily-tasks/coaching/
//    job-triage, event discovery).
//  - `runAnthropicRequest` (open + full drain, via the caching execution
//    helpers): document transcription and every structured extraction pass.
//
//  The raw `anthropicMessagesStream` entry is deliberately NOT retried — the
//  stream is handed to the caller, so the facade cannot know how much was
//  consumed; LLMMessenger owns retry + budget pause for the interview stream.
//

import XCTest
import SwiftOpenAI
@testable import Sprung

// MARK: - Scripted service

private enum ScriptError: Error {
    case unscripted(String)
    case unsupported(String)
}

/// Serves pre-scripted results per call, counting invocations.
private final class ScriptedAnthropicService: AnthropicService {

    enum StreamTurn {
        /// `messagesStream` itself throws (connect failure / non-2xx status —
        /// the fork validates the HTTP status BEFORE returning the stream).
        case openFailure(Error)
        /// A stream that yields `events` then finishes (or throws mid-drain).
        case events([AnthropicStreamEvent], thenThrow: Error?)
    }

    var messagesScript: [Result<AnthropicMessageResponse, Error>] = []
    private(set) var messagesCalls = 0

    var streamScript: [StreamTurn] = []
    private(set) var streamCalls = 0

    func messages(parameters: AnthropicMessageParameter) async throws -> AnthropicMessageResponse {
        let turn = messagesCalls
        messagesCalls += 1
        guard turn < messagesScript.count else { throw ScriptError.unscripted("messages call \(turn)") }
        return try messagesScript[turn].get()
    }

    func messagesStream(
        parameters: AnthropicMessageParameter
    ) async throws -> AsyncThrowingStream<AnthropicStreamEvent, Error> {
        let turn = streamCalls
        streamCalls += 1
        guard turn < streamScript.count else { throw ScriptError.unscripted("stream call \(turn)") }
        switch streamScript[turn] {
        case .openFailure(let error):
            throw error
        case .events(let events, let thenThrow):
            return AsyncThrowingStream { continuation in
                for event in events { continuation.yield(event) }
                if let thenThrow {
                    continuation.finish(throwing: thenThrow)
                } else {
                    continuation.finish()
                }
            }
        }
    }

    // Unused surface — loud failures if reached.
    func listModels() async throws -> AnthropicModelsResponse { throw ScriptError.unsupported("listModels") }
    func retrieveModel(id: String) async throws -> AnthropicModel { throw ScriptError.unsupported("retrieveModel") }
    func countTokens(parameters: AnthropicTokenCountParameter) async throws -> AnthropicTokenCountResponse {
        throw ScriptError.unsupported("countTokens")
    }
    func uploadFile(data: Data, filename: String, mimeType: String) async throws -> AnthropicFileMetadata {
        throw ScriptError.unsupported("uploadFile")
    }
    func retrieveFileMetadata(id: String) async throws -> AnthropicFileMetadata {
        throw ScriptError.unsupported("retrieveFileMetadata")
    }
    func listFiles() async throws -> AnthropicFileListResponse { throw ScriptError.unsupported("listFiles") }
    func deleteFile(id: String) async throws -> AnthropicFileDeletedResponse { throw ScriptError.unsupported("deleteFile") }
}

// MARK: - Fixtures (decoded through the real library decoder)

private func decodeResponse(_ json: String) throws -> AnthropicMessageResponse {
    try JSONDecoder().decode(AnthropicMessageResponse.self, from: Data(json.utf8))
}

private func streamEvent(_ json: String) throws -> AnthropicStreamEvent {
    try JSONDecoder().decode(AnthropicStreamEvent.self, from: Data(json.utf8))
}

private let okResponseJSON = #"""
{"id":"msg_ok","type":"message","role":"assistant","model":"test-model","content":[
  {"type":"text","text":"ok"}
],"stop_reason":"end_turn","stop_sequence":null,
"usage":{"input_tokens":1,"output_tokens":1}}
"""#

private let creditBalanceBody = #"""
{"type":"error","error":{"type":"invalid_request_error","message":"Your credit balance is too low to access the Anthropic API. Please go to Plans & Billing to upgrade or purchase credits."}}
"""#

// MARK: - Tests

@MainActor
final class AnthropicTransientRetryExecutionTests: XCTestCase {

    private var service: ScriptedAnthropicService!
    private var apis: LLMFacadeSpecializedAPIs!

    override func setUp() async throws {
        try await super.setUp()
        service = ScriptedAnthropicService()
        apis = LLMFacadeSpecializedAPIs()
        apis.registerAnthropicService(service)
        // Zero backoff so retry tests run instantly; attempt cap unchanged.
        apis.anthropicRetryPolicy = AnthropicTransientRetryPolicy(maxAttempts: 3, baseDelay: 0)
    }

    private func goodStreamEvents() throws -> [AnthropicStreamEvent] {
        try [
            streamEvent(#"{"type":"message_start","message":{"id":"msg_1","type":"message","role":"assistant","content":[],"model":"test-model","stop_reason":null,"usage":{"input_tokens":10,"output_tokens":1,"cache_read_input_tokens":4,"cache_creation_input_tokens":0}}}"#),
            streamEvent(#"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}"#),
            streamEvent(#"{"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":5}}"#),
            streamEvent(#"{"type":"message_stop"}"#),
        ]
    }

    // MARK: - anthropicMessages (agent-loop chokepoint)

    func testMessagesRetriesTransientFailuresThenSucceeds() async throws {
        service.messagesScript = [
            .failure(URLError(.networkConnectionLost)),
            .failure(APIError.responseUnsuccessful(description: "Request failed", statusCode: 529, responseBody: "overloaded_error")),
            .success(try decodeResponse(okResponseJSON)),
        ]

        let response = try await apis.anthropicMessages(
            parameters: AnthropicMessageParameter(model: "test-model", messages: [.user("hi")], maxTokens: 64)
        )

        XCTAssertEqual(service.messagesCalls, 3, "two transient failures then success = exactly three sends")
        let firstBlock = try XCTUnwrap(response.content.first)
        guard case .text(let block) = firstBlock else {
            return XCTFail("expected the scripted success response")
        }
        XCTAssertEqual(block.text, "ok")
    }

    func testMessagesDoesNotRetryInsufficientBalance400AndRethrowsItUnchanged() async throws {
        let creditError = APIError.responseUnsuccessful(
            description: "Request failed", statusCode: 400, responseBody: creditBalanceBody
        )
        service.messagesScript = [.failure(creditError)]

        do {
            _ = try await apis.anthropicMessages(
                parameters: AnthropicMessageParameter(model: "test-model", messages: [.user("hi")], maxTokens: 64)
            )
            XCTFail("expected the credit-balance 400 to propagate")
        } catch {
            XCTAssertEqual(service.messagesCalls, 1, "a 4xx must never be retried")
            guard case APIError.responseUnsuccessful(_, let status, let body) = error else {
                return XCTFail("error must propagate as the original APIError, got \(error)")
            }
            XCTAssertEqual(status, 400)
            XCTAssertEqual(body, creditBalanceBody, "the wire body must survive unchanged")
            // The exact contract BudgetPauseGate's interception relies on:
            XCTAssertTrue(LLMErrorHandler().isInsufficientBalanceError(error))
        }
    }

    func testMessagesGivesUpAfterMaxAttemptsAndThrowsOriginalError() async {
        service.messagesScript = [
            .failure(URLError(.timedOut)),
            .failure(URLError(.timedOut)),
            .failure(URLError(.timedOut)),
            .failure(URLError(.timedOut)), // must never be reached
        ]

        do {
            _ = try await apis.anthropicMessages(
                parameters: AnthropicMessageParameter(model: "test-model", messages: [.user("hi")], maxTokens: 64)
            )
            XCTFail("expected the exhausted transient failure to propagate")
        } catch {
            XCTAssertEqual(service.messagesCalls, 3, "bounded attempts: exactly maxAttempts sends")
            XCTAssertEqual((error as? URLError)?.code, .timedOut, "original error propagates")
        }
    }

    // MARK: - runAnthropicRequest (transcription / structured-pass chokepoint)

    func testTextRequestRetriesOpenFailureThenSucceeds() async throws {
        service.streamScript = [
            .openFailure(URLError(.cannotConnectToHost)),
            .events(try goodStreamEvents(), thenThrow: nil),
        ]

        let text = try await apis.executeTextWithAnthropicCaching(
            systemContent: [AnthropicSystemBlock(text: "system")],
            userPrompt: "prompt",
            modelId: "test-model"
        )

        XCTAssertEqual(text, "Hello")
        XCTAssertEqual(service.streamCalls, 2, "open failure happens before any event exists — safe to re-send")
    }

    /// Collects usage reports from the `@Sendable` observer. The facade invokes
    /// the observer synchronously on the main actor, so plain appends are safe.
    private final class UsageSink: @unchecked Sendable {
        private(set) var usages: [LLMRequestUsage] = []
        func record(_ usage: LLMRequestUsage) { usages.append(usage) }
    }

    func testTextRequestRetriesMidDrainDropAndDiscardsPartialText() async throws {
        // The stream never escapes runAnthropicRequest, so even a drop AFTER
        // partial text is safe to retry: the partial accumulator is discarded
        // and the identical request is re-sent (nothing was exposed upstream).
        let sink = UsageSink()
        apis.anthropicUsageObserver = { sink.record($0) }

        service.streamScript = [
            .events(
                [try streamEvent(#"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"partial garbage"}}"#)],
                thenThrow: URLError(.networkConnectionLost)
            ),
            .events(try goodStreamEvents(), thenThrow: nil),
        ]

        let text = try await apis.executeTextWithAnthropicCaching(
            systemContent: [AnthropicSystemBlock(text: "system")],
            userPrompt: "prompt",
            modelId: "test-model"
        )

        XCTAssertEqual(text, "Hello", "partial text from the failed attempt must not leak into the result")
        XCTAssertEqual(service.streamCalls, 2)
        XCTAssertEqual(sink.usages.count, 1, "usage must be reported once, for the successful attempt only")
        XCTAssertEqual(sink.usages.first?.outputTokens, 5)
    }

    func testTextRequestDoesNotRetryInsufficientBalance400() async {
        let creditError = APIError.responseUnsuccessful(
            description: "Request failed", statusCode: 400, responseBody: creditBalanceBody
        )
        service.streamScript = [.openFailure(creditError)]

        do {
            _ = try await apis.executeTextWithAnthropicCaching(
                systemContent: [AnthropicSystemBlock(text: "system")],
                userPrompt: "prompt",
                modelId: "test-model"
            )
            XCTFail("expected the credit-balance 400 to propagate")
        } catch {
            XCTAssertEqual(service.streamCalls, 1, "budget errors must reach the caller on the first failure")
            XCTAssertTrue(LLMErrorHandler().isInsufficientBalanceError(error))
        }
    }

    // MARK: - Raw stream entry (deliberately NOT retried)

    func testRawMessagesStreamOpenFailureIsNotRetried() async {
        service.streamScript = [.openFailure(URLError(.timedOut))]

        do {
            _ = try await apis.anthropicMessagesStream(
                parameters: AnthropicMessageParameter(model: "test-model", messages: [.user("hi")], maxTokens: 64)
            )
            XCTFail("expected the open failure to propagate")
        } catch {
            // The raw stream is handed to callers who own their consumption
            // state (LLMMessenger retries whole requests itself, including the
            // budget pause/resume flow) — the facade must not stack a second
            // retry layer under them.
            XCTAssertEqual(service.streamCalls, 1)
            XCTAssertEqual((error as? URLError)?.code, .timedOut)
        }
    }
}
