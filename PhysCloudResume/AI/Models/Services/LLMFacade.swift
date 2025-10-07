//
//  LLMFacade.swift
//  PhysCloudResume
//
//  A thin facade over LLMClient that centralizes capability gating (future) and
//  exposes a stable surface to callers.
//

import Foundation
import Observation

@Observable
final class LLMFacade {
    private let client: LLMClient
    private let llmService: LLMService // temporary bridge for conversation flows
    private let appState: AppState
    private let enabledLLMStore: EnabledLLMStore?

    init(client: LLMClient, llmService: LLMService, appState: AppState, enabledLLMStore: EnabledLLMStore?) {
        self.client = client
        self.llmService = llmService
        self.appState = appState
        self.enabledLLMStore = enabledLLMStore
    }

    // MARK: - Capability Validation

    private func validate(modelId: String, requires capabilities: [ModelCapability]) throws {
        guard let model = appState.openRouterService.findModel(id: modelId) else {
            throw LLMError.clientError("Model '\(modelId)' not found")
        }

        for capability in capabilities {
            let supported: Bool
            switch capability {
            case .vision:
                supported = model.supportsImages
            case .structuredOutput:
                supported = model.supportsStructuredOutput
            case .reasoning:
                supported = model.supportsReasoning
            case .textOnly:
                supported = model.isTextToText && !model.supportsImages
            }

            if !supported {
                throw LLMError.clientError("Model '\(modelId)' does not support \(capability.displayName)")
            }
        }
    }

    // Text
    func executeText(prompt: String, modelId: String, temperature: Double? = nil) async throws -> String {
        try validate(modelId: modelId, requires: [])
        return try await client.executeText(prompt: prompt, modelId: modelId, temperature: temperature)
    }

    func executeTextWithImages(prompt: String, modelId: String, images: [Data], temperature: Double? = nil) async throws -> String {
        try validate(modelId: modelId, requires: [.vision])
        return try await client.executeTextWithImages(prompt: prompt, modelId: modelId, images: images, temperature: temperature)
    }

    // Structured
    func executeStructured<T: Decodable & Sendable>(prompt: String, modelId: String, as type: T.Type, temperature: Double? = nil) async throws -> T {
        try validate(modelId: modelId, requires: [.structuredOutput])
        return try await client.executeStructured(prompt: prompt, modelId: modelId, as: type, temperature: temperature)
    }

    func executeStructuredWithImages<T: Decodable & Sendable>(prompt: String, modelId: String, images: [Data], as type: T.Type, temperature: Double? = nil) async throws -> T {
        try validate(modelId: modelId, requires: [.vision, .structuredOutput])
        return try await client.executeStructuredWithImages(prompt: prompt, modelId: modelId, images: images, as: type, temperature: temperature)
    }

    func executeFlexibleJSON<T: Decodable & Sendable>(
        prompt: String,
        modelId: String,
        as type: T.Type,
        temperature: Double? = nil,
        jsonSchema: JSONSchema? = nil
    ) async throws -> T {
        try validate(modelId: modelId, requires: [])
        return try await llmService.executeFlexibleJSON(
            prompt: prompt,
            modelId: modelId,
            responseType: type,
            temperature: temperature,
            jsonSchema: jsonSchema
        )
    }

    // Streaming
    func startStreaming(prompt: String, modelId: String, temperature: Double? = nil) -> AsyncThrowingStream<LLMStreamChunkDTO, Error> {
        do {
            try validate(modelId: modelId, requires: [])
            return client.startStreaming(prompt: prompt, modelId: modelId, temperature: temperature)
        } catch {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: error)
            }
        }
    }

    // MARK: - Conversation (temporary pass-through to LLMService)

    func startConversationStreaming(
        systemPrompt: String? = nil,
        userMessage: String,
        modelId: String,
        temperature: Double? = nil,
        reasoning: OpenRouterReasoning? = nil,
        jsonSchema: JSONSchema? = nil
    ) async throws -> (UUID, AsyncThrowingStream<LLMStreamChunkDTO, Error>) {
        var required: [ModelCapability] = []
        if reasoning != nil { required.append(.reasoning) }
        if jsonSchema != nil { required.append(.structuredOutput) }
        try validate(modelId: modelId, requires: required)

        let (id, stream) = try await llmService.startConversationStreaming(
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            modelId: modelId,
            temperature: temperature,
            reasoning: reasoning,
            jsonSchema: jsonSchema
        )
        let mapped = AsyncThrowingStream<LLMStreamChunkDTO, Error> { continuation in
            Task {
                do {
                    for try await c in stream {
                        let dto = LLMStreamChunkDTO(
                            content: c.content,
                            reasoning: c.reasoningContent,
                            isFinished: c.isFinished,
                            finishReason: c.finishReason
                        )
                        continuation.yield(dto)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
        return (id, mapped)
    }

    func continueConversationStreaming(
        userMessage: String,
        modelId: String,
        conversationId: UUID,
        reasoning: OpenRouterReasoning? = nil
    ) -> AsyncThrowingStream<LLMStreamChunkDTO, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    var required: [ModelCapability] = []
                    if reasoning != nil { required.append(.reasoning) }
                    try validate(modelId: modelId, requires: required)

                    let stream = llmService.continueConversationStreaming(
                        userMessage: userMessage,
                        modelId: modelId,
                        conversationId: conversationId,
                        reasoning: reasoning
                    )

                    for try await c in stream {
                        continuation.yield(LLMStreamChunkDTO(
                            content: c.content,
                            reasoning: c.reasoningContent,
                            isFinished: c.isFinished,
                            finishReason: c.finishReason
                        ))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func continueConversation(
        userMessage: String,
        modelId: String,
        conversationId: UUID,
        images: [Data] = [],
        temperature: Double? = nil
    ) async throws -> String {
        let required: [ModelCapability] = images.isEmpty ? [] : [.vision]
        try validate(modelId: modelId, requires: required)

        return try await llmService.continueConversation(
            userMessage: userMessage,
            modelId: modelId,
            conversationId: conversationId,
            images: images,
            temperature: temperature
        )
    }

    func continueConversationStructured<T: Decodable & Sendable>(
        userMessage: String,
        modelId: String,
        conversationId: UUID,
        as type: T.Type,
        images: [Data] = [],
        temperature: Double? = nil,
        jsonSchema: JSONSchema? = nil
    ) async throws -> T {
        var required: [ModelCapability] = [.structuredOutput]
        if !images.isEmpty { required.append(.vision) }
        try validate(modelId: modelId, requires: required)

        return try await llmService.continueConversationStructured(
            userMessage: userMessage,
            modelId: modelId,
            conversationId: conversationId,
            responseType: type,
            images: images,
            temperature: temperature,
            jsonSchema: jsonSchema
        )
    }

    func startConversation(
        systemPrompt: String? = nil,
        userMessage: String,
        modelId: String,
        temperature: Double? = nil
    ) async throws -> (UUID, String) {
        try validate(modelId: modelId, requires: [])
        return try await llmService.startConversation(
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            modelId: modelId,
            temperature: temperature
        )
    }

    func clearConversation(id: UUID) {
        llmService.clearConversation(id: id)
    }

    func cancelAllRequests() {
        llmService.cancelAllRequests()
    }
}
