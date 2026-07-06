//
//  LLMFacadeSpecializedAPIs.swift
//  Sprung
//
//  Handles specialized API operations (Anthropic streams/files, OpenAI Responses, TTS).
//  Extracted from LLMFacade for single responsibility.
//

import Foundation
import SwiftOpenAI

/// Provider-agnostic per-request token usage surfaced by the Anthropic
/// structured/text execution chokepoint (`runAnthropicRequest`). The facade
/// reports it to an optional observer so a host (e.g. onboarding) can aggregate
/// cost WITHOUT the facade depending on any host-specific usage taxonomy.
struct LLMRequestUsage: Sendable {
    let modelId: String
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let cacheCreationTokens: Int
}

/// Handles specialized API operations (Anthropic streams/files, OpenAI Responses, TTS)
@MainActor
final class LLMFacadeSpecializedAPIs {
    private var openAIService: OpenAIService?
    private var anthropicService: AnthropicService?

    /// Optional sink for per-request token usage from the Anthropic structured/text
    /// execution path (everything that funnels through `runAnthropicRequest`). Set
    /// by the host; nil disables reporting. The streaming interview and the git
    /// agent use different code paths that self-report, so this never double-counts.
    var anthropicUsageObserver: (@Sendable (LLMRequestUsage) -> Void)?

    /// Transient-failure retry policy for the two Anthropic execution chokepoints
    /// (`anthropicMessages` and `runAnthropicRequest`). Internal so tests can swap
    /// in a zero-delay policy; production always uses the default.
    var anthropicRetryPolicy = AnthropicTransientRetryPolicy()

    // MARK: - Service Registration

    func registerOpenAIService(_ service: OpenAIService) {
        self.openAIService = service
    }

    func registerAnthropicService(_ service: AnthropicService) {
        self.anthropicService = service
    }

    /// The currently-registered Anthropic service, if any. Used by the tape
    /// recorder/replay to wrap the live service in a decorator and to restore it
    /// afterwards.
    func currentAnthropicService() -> AnthropicService? {
        anthropicService
    }

    // MARK: - OpenAI Responses API

    func responseCreateStream(
        parameters: ModelResponseParameter
    ) async throws -> AsyncThrowingStream<ResponseStreamEvent, Error> {
        guard let service = openAIService else {
            throw LLMError.clientError("OpenAI service is not configured. Call registerOpenAIService first.")
        }
        return try await service.responseCreateStream(parameters)
    }

    // MARK: - Anthropic Messages API

    /// Raw streaming entry point — deliberately NOT retried here. The stream is
    /// handed to the caller, so the facade cannot know whether events were already
    /// consumed when a failure surfaces, and a blind re-send could duplicate
    /// partially-processed output. The stream consumers own their own recovery:
    /// the onboarding interview retries whole requests in
    /// `LLMMessenger.executeAnthropicStream` (which also owns the
    /// insufficient-balance pause/resume flow), and the RevisionAgent's
    /// interactive stream surfaces failures to the user.
    func anthropicMessagesStream(
        parameters: AnthropicMessageParameter
    ) async throws -> AsyncThrowingStream<AnthropicStreamEvent, Error> {
        guard let service = anthropicService else {
            throw LLMError.clientError("Anthropic service is not configured. Call registerAnthropicService first.")
        }
        return try await service.messagesStream(parameters: parameters)
    }

    /// Non-streaming Messages call — the chokepoint every multi-turn agent loop's
    /// `runModelTurn` funnels through (git analysis, card/background merge,
    /// Discovery daily tasks/coaching/job triage, event discovery). The full
    /// response is consumed atomically, so a failed attempt exposes nothing to the
    /// caller and a transient failure can be retried with identical request bytes.
    func anthropicMessages(
        parameters: AnthropicMessageParameter
    ) async throws -> AnthropicMessageResponse {
        guard let service = anthropicService else {
            throw LLMError.clientError("Anthropic service is not configured. Call registerAnthropicService first.")
        }
        return try await withAnthropicTransientRetry("messages request (\(parameters.model))") {
            try await service.messages(parameters: parameters)
        }
    }

    /// Run `operation` with bounded transient-failure retry (exponential backoff +
    /// jitter). Terminal errors — every 4xx including the insufficient-balance 400
    /// that `BudgetPauseGate` owns, decode failures, cancellation — are rethrown
    /// UNCHANGED on the first failure so downstream handling sees the original
    /// error. Each retry re-invokes the same closure with the same parameter
    /// value, so the fork re-encodes byte-identical request bytes (same encoder
    /// path, `.sortedKeys`) — a retry adds nothing to any conversation history.
    private func withAnthropicTransientRetry<T>(
        _ operationName: String,
        _ operation: () async throws -> T
    ) async throws -> T {
        let policy = anthropicRetryPolicy
        var attempt = 1
        while true {
            try Task.checkCancellation()
            do {
                return try await operation()
            } catch {
                guard attempt < policy.maxAttempts,
                      let label = AnthropicTransientRetryPolicy.transientLabel(for: error) else {
                    // Terminal error, or transient with attempts exhausted: propagate
                    // the ORIGINAL error — callers log/handle it exactly as before.
                    throw error
                }
                attempt += 1
                let delay = policy.delay(beforeAttempt: attempt)
                Logger.warning(
                    "Anthropic \(operationName) failed (\(label)) — retrying, attempt \(attempt)/\(policy.maxAttempts) in \(String(format: "%.1f", delay))s",
                    category: .ai
                )
                // Task.sleep throws CancellationError if cancelled, so cancellation
                // propagates immediately instead of burning remaining attempts.
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }

    func anthropicListModels() async throws -> AnthropicModelsResponse {
        guard let service = anthropicService else {
            throw LLMError.clientError("Anthropic service is not configured. Call registerAnthropicService first.")
        }
        return try await service.listModels()
    }

    // MARK: - Anthropic Files API & Token Counting

    /// Upload a file to the Anthropic Files API (`POST /v1/files`).
    /// The fork attaches the `files-api-2025-04-14` beta header automatically.
    func anthropicUploadFile(data: Data, filename: String, mimeType: String) async throws -> AnthropicFileMetadata {
        guard let service = anthropicService else {
            throw LLMError.clientError("Anthropic service is not configured. Call registerAnthropicService first.")
        }
        return try await service.uploadFile(data: data, filename: filename, mimeType: mimeType)
    }

    /// Delete a file from the Anthropic Files API (`DELETE /v1/files/{id}`).
    func anthropicDeleteFile(id: String) async throws -> AnthropicFileDeletedResponse {
        guard let service = anthropicService else {
            throw LLMError.clientError("Anthropic service is not configured. Call registerAnthropicService first.")
        }
        return try await service.deleteFile(id: id)
    }

    /// Count tokens for a prospective Anthropic Messages API request.
    func anthropicCountTokens(parameters: AnthropicTokenCountParameter) async throws -> AnthropicTokenCountResponse {
        guard let service = anthropicService else {
            throw LLMError.clientError("Anthropic service is not configured. Call registerAnthropicService first.")
        }
        return try await service.countTokens(parameters: parameters)
    }

    // MARK: - Anthropic Execution Helpers

    /// Drives the Anthropic streaming event loop and returns the accumulated text.
    /// Logs cache telemetry per request — this is the regression signal for the
    /// document-analysis caching design (cache_read should cover the shared
    /// document prefix on every pass after the first).
    ///
    /// The WHOLE open+drain is one transient-retry unit: the stream never escapes
    /// this method, so even a mid-stream drop exposes nothing to the caller — the
    /// partial accumulator is discarded and the identical request is re-sent.
    /// Usage telemetry and the usage observer fire only for the successful
    /// attempt. (During onboarding recording, a stream that fails mid-drain rolls
    /// back its claimed tape turn in `RecordingAnthropicService`, so the retried
    /// attempt reuses the same turn index and failed attempts leave no model
    /// stream on the tape.)
    private func runAnthropicRequest(parameters: AnthropicMessageParameter) async throws -> String {
        try await withAnthropicTransientRetry("structured/text request (\(parameters.model))") {
            let stream = try await anthropicMessagesStream(parameters: parameters)
            var resultText = ""
            var inputTokens = 0
            var outputTokens = 0
            var cacheRead = 0
            var cacheCreation = 0

            for try await event in stream {
                switch event {
                case .contentBlockDelta(let delta):
                    if case .textDelta(let text) = delta.delta {
                        resultText += text
                    }
                case .messageStop:
                    break
                default:
                    break
                }
                if let usage = event.usage {
                    inputTokens = max(inputTokens, usage.inputTokens ?? 0)
                    outputTokens = max(outputTokens, usage.outputTokens ?? 0)
                    cacheRead = max(cacheRead, usage.cacheReadInputTokens ?? 0)
                    cacheCreation = max(cacheCreation, usage.cacheCreationInputTokens ?? 0)
                }
            }

            Logger.info(
                "Anthropic usage (\(parameters.model)): input=\(inputTokens) cache_read=\(cacheRead) cache_create=\(cacheCreation) output=\(outputTokens)",
                category: .ai
            )
            anthropicUsageObserver?(LLMRequestUsage(
                modelId: parameters.model,
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                cacheReadTokens: cacheRead,
                cacheCreationTokens: cacheCreation
            ))
            return resultText
        }
    }

    /// Decodes accumulated Anthropic response text into the requested Codable type.
    /// `internal` (not `private`) so the pure response-parse half can be unit-tested
    /// directly without constructing the facade or hitting the network.
    func decodeAnthropicResponse<T: Codable>(_ resultText: String, as type: T.Type) throws -> T {
        guard let data = resultText.data(using: .utf8) else {
            throw LLMError.clientError("Failed to convert Anthropic response to data")
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            Logger.warning("Failed to parse Anthropic structured response as \(T.self): \(error)", category: .ai)
            Logger.debug("Response was: \(resultText.prefix(500))", category: .ai)
            throw LLMError.clientError("Failed to parse structured response: \(error.localizedDescription)")
        }
    }

    /// Execute a text prompt via direct Anthropic API with prompt caching.
    /// Builds the request parameters, drives the streaming event loop, and returns the accumulated text.
    func executeTextWithAnthropicCaching(
        systemContent: [AnthropicSystemBlock],
        userPrompt: String,
        modelId: String
    ) async throws -> String {
        let parameters = AnthropicMessageParameter(
            model: modelId,
            messages: [.user(userPrompt)],
            system: .blocks(systemContent),
            maxTokens: 4096,
            stream: false
        )

        let resultText = try await runAnthropicRequest(parameters: parameters)
        Logger.info("Anthropic cached request completed: \(resultText.count) chars", category: .ai)
        return resultText
    }

    /// Execute a structured JSON request via direct Anthropic API with prompt caching and schema enforcement.
    /// Builds the request parameters, drives the streaming event loop, decodes the result, and returns the parsed object.
    func executeStructuredWithAnthropicCaching<T: Codable>(
        systemContent: [AnthropicSystemBlock],
        userPrompt: String,
        modelId: String,
        responseType: T.Type,
        schema: [String: Any],
        maxTokens: Int
    ) async throws -> T {
        let parameters = AnthropicMessageParameter(
            model: modelId,
            messages: [.user(userPrompt)],
            system: .blocks(systemContent),
            maxTokens: maxTokens,
            stream: false,
            outputConfig: AnthropicOutputConfig.schema(schema)
        )

        let resultText = try await runAnthropicRequest(parameters: parameters)
        Logger.info("Anthropic structured request completed: \(resultText.count) chars", category: .ai)
        return try decodeAnthropicResponse(resultText, as: responseType)
    }

    /// Execute a structured JSON request whose user content is arbitrary content blocks
    /// (document blocks with cache control, cached text blocks, instructions).
    func executeStructuredWithAnthropicBlocks<T: Codable>(
        systemContent: [AnthropicSystemBlock],
        userBlocks: [AnthropicContentBlock],
        modelId: String,
        responseType: T.Type,
        schema: [String: Any],
        maxTokens: Int = 8192
    ) async throws -> T {
        let parameters = AnthropicMessageParameter(
            model: modelId,
            messages: [AnthropicMessage(role: "user", content: .blocks(userBlocks))],
            system: .blocks(systemContent),
            maxTokens: maxTokens,
            stream: false,
            outputConfig: AnthropicOutputConfig.schema(schema)
        )

        let resultText = try await runAnthropicRequest(parameters: parameters)
        Logger.info("Anthropic structured block request completed: \(resultText.count) chars", category: .ai)
        return try decodeAnthropicResponse(resultText, as: responseType)
    }

    // MARK: - Text-to-Speech

    func createTTSClient() -> TTSCapable {
        guard let service = openAIService else {
            Logger.warning("⚠️ No OpenAI service configured for TTS", category: .ai)
            return UnavailableTTSClient(errorMessage: "OpenAI service is not configured for TTS")
        }
        return OpenAIServiceTTSWrapper(service: service)
    }
}
