//
//  LLMFacadeSpecializedAPIs.swift
//  Sprung
//
//  Handles specialized API operations (Anthropic streams/files, OpenAI Responses, TTS).
//  Extracted from LLMFacade for single responsibility.
//

import Foundation
import SwiftOpenAI

/// Handles specialized API operations (Anthropic streams/files, OpenAI Responses, TTS)
@MainActor
final class LLMFacadeSpecializedAPIs {
    private var openAIService: OpenAIService?
    private var anthropicService: AnthropicService?

    // MARK: - Service Registration

    func registerOpenAIService(_ service: OpenAIService) {
        self.openAIService = service
    }

    func registerAnthropicService(_ service: AnthropicService) {
        self.anthropicService = service
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

    func executeWithWebSearch(
        systemPrompt: String,
        userMessage: String,
        modelId: String,
        reasoningEffort: String? = nil,
        webSearchLocation: String? = nil,
        onWebSearching: (@MainActor @Sendable () async -> Void)? = nil,
        onWebSearchComplete: (@MainActor @Sendable () async -> Void)? = nil,
        onTextDelta: (@MainActor @Sendable (String) async -> Void)? = nil
    ) async throws -> String {
        guard let service = openAIService else {
            throw LLMError.clientError("OpenAI service is not configured. Call registerOpenAIService first.")
        }

        // Strip OpenRouter prefix if present
        let openAIModelId = modelId.hasPrefix("openai/") ? String(modelId.dropFirst(7)) : modelId

        let inputItems: [InputItem] = [
            .message(InputMessage(role: "developer", content: .text(systemPrompt))),
            .message(InputMessage(role: "user", content: .text(userMessage)))
        ]

        let reasoning: Reasoning? = reasoningEffort.map { Reasoning(effort: $0) }

        // Configure web search tool if location provided
        var tools: [Tool]?
        if let location = webSearchLocation {
            let webSearchTool = Tool.webSearch(Tool.WebSearchTool(
                type: .webSearch,
                userLocation: Tool.UserLocation(city: location, country: "US")
            ))
            tools = [webSearchTool]
        }

        let parameters = ModelResponseParameter(
            input: .array(inputItems),
            model: .custom(openAIModelId),
            reasoning: reasoning,
            store: true,
            stream: true,
            toolChoice: tools != nil ? .auto : nil,
            tools: tools
        )

        Logger.info("🌐 LLMFacade.executeWithWebSearch (model: \(openAIModelId), webSearch: \(webSearchLocation != nil))", category: .ai)

        var finalResponse: ResponseModel?
        let stream = try await service.responseCreateStream(parameters)

        for try await event in stream {
            switch event {
            case .responseCompleted(let completed):
                finalResponse = completed.response
            case .webSearchCallSearching:
                await onWebSearching?()
            case .webSearchCallCompleted:
                await onWebSearchComplete?()
            case .outputTextDelta(let delta):
                await onTextDelta?(delta.delta)
            case .reasoningSummaryTextDelta(let delta):
                await onTextDelta?(delta.delta)
            default:
                break
            }
        }

        guard let response = finalResponse,
              let outputText = extractResponseText(from: response) else {
            throw LLMError.clientError("No response received from OpenAI")
        }

        Logger.info("✅ LLMFacade.executeWithWebSearch returned \(outputText.count) chars", category: .ai)
        return outputText
    }

    private func extractResponseText(from response: ResponseModel) -> String? {
        if let text = response.outputText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            return text
        }

        for item in response.output {
            if case let .message(message) = item {
                for content in message.content {
                    if case let .outputText(output) = content,
                       !output.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        return output.text
                    }
                }
            }
        }
        return nil
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
        return resultText
    }

    /// Decodes accumulated Anthropic response text into the requested Codable type.
    private func decodeAnthropicResponse<T: Codable>(_ resultText: String, as type: T.Type) throws -> T {
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
        schema: [String: Any]
    ) async throws -> T {
        let parameters = AnthropicMessageParameter(
            model: modelId,
            messages: [.user(userPrompt)],
            system: .blocks(systemContent),
            maxTokens: 4096,
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
