//
//  LLMFacadeSpecializedAPIs.swift
//  Sprung
//
//  Handles specialized API operations (Gemini vision, TTS, Anthropic streams).
//  Extracted from LLMFacade for single responsibility.
//

import Foundation
import SwiftOpenAI

/// Handles specialized API operations (Gemini vision, TTS, Anthropic streams)
@MainActor
final class LLMFacadeSpecializedAPIs {
    private var openAIService: OpenAIService?
    private var googleAIService: GoogleAIService?
    private var anthropicService: AnthropicService?

    // MARK: - Service Registration

    func registerOpenAIService(_ service: OpenAIService) {
        self.openAIService = service
    }

    func registerGoogleAIService(_ service: GoogleAIService) {
        self.googleAIService = service
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

    // MARK: - Gemini Vision & Documents

    func generateFromPDF(
        pdfData: Data,
        filename: String,
        prompt: String,
        modelId: String? = nil,
        maxOutputTokens: Int = 65536
    ) async throws -> (text: String, tokenUsage: GoogleAIService.GeminiTokenUsage?) {
        guard let service = googleAIService else {
            throw LLMError.clientError("Google AI service is not configured. Call registerGoogleAIService first.")
        }

        // Use provided model or require configuration
        let effectiveModelId: String
        if let providedModelId = modelId, !providedModelId.isEmpty {
            effectiveModelId = providedModelId
        } else {
            guard let configuredModelId = UserDefaults.standard.string(forKey: "onboardingPDFExtractionModelId"), !configuredModelId.isEmpty else {
                throw ModelConfigurationError.modelNotConfigured(
                    settingKey: "onboardingPDFExtractionModelId",
                    operationName: "LLM Facade Image Analysis"
                )
            }
            effectiveModelId = configuredModelId
        }

        return try await service.generateFromPDF(
            pdfData: pdfData,
            filename: filename,
            prompt: prompt,
            modelId: effectiveModelId,
            maxOutputTokens: maxOutputTokens
        )
    }

    func generateDocumentSummary(
        content: String,
        filename: String,
        modelId: String? = nil
    ) async throws -> DocumentSummary {
        guard let service = googleAIService else {
            throw LLMError.clientError("Google AI service is not configured. Call registerGoogleAIService first.")
        }
        return try await service.generateSummary(
            content: content,
            filename: filename,
            modelId: modelId
        )
    }

    func analyzeImagesWithGemini(
        images: [Data],
        prompt: String,
        modelId: String? = nil
    ) async throws -> String {
        guard let service = googleAIService else {
            throw LLMError.clientError("Google AI service is not configured. Call registerGoogleAIService first.")
        }
        return try await service.analyzeImages(
            images: images,
            prompt: prompt,
            modelId: modelId
        )
    }

    func analyzeImagesWithGeminiStructured(
        images: [Data],
        prompt: String,
        jsonSchema: [String: Any],
        modelId: String? = nil
    ) async throws -> String {
        guard let service = googleAIService else {
            throw LLMError.clientError("Google AI service is not configured. Call registerGoogleAIService first.")
        }
        return try await service.analyzeImagesStructured(
            images: images,
            prompt: prompt,
            jsonSchema: jsonSchema,
            modelId: modelId
        )
    }

    func generateStructuredJSON(
        prompt: String,
        modelId: String,
        maxOutputTokens: Int,
        jsonSchema: [String: Any],
        thinkingLevel: String? = nil
    ) async throws -> String {
        guard let service = googleAIService else {
            throw LLMError.clientError("Google AI service is not configured. Call registerGoogleAIService first.")
        }
        return try await service.generateStructuredJSON(
            prompt: prompt,
            modelId: modelId,
            maxOutputTokens: maxOutputTokens,
            jsonSchema: jsonSchema,
            thinkingLevel: thinkingLevel
        )
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
