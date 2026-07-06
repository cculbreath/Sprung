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

    func anthropicMessagesStream(
        parameters: AnthropicMessageParameter
    ) async throws -> AsyncThrowingStream<AnthropicStreamEvent, Error> {
        guard let service = anthropicService else {
            throw LLMError.clientError("Anthropic service is not configured. Call registerAnthropicService first.")
        }
        return try await service.messagesStream(parameters: parameters)
    }

    func anthropicMessages(
        parameters: AnthropicMessageParameter
    ) async throws -> AnthropicMessageResponse {
        guard let service = anthropicService else {
            throw LLMError.clientError("Anthropic service is not configured. Call registerAnthropicService first.")
        }
        return try await service.messages(parameters: parameters)
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
    private func runAnthropicRequest(parameters: AnthropicMessageParameter) async throws -> String {
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
