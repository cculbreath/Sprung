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

    init(client: LLMClient, llmService: LLMService) {
        self.client = client
        self.llmService = llmService
    }

    // Text
    func executeText(prompt: String, modelId: String, temperature: Double? = nil) async throws -> String {
        return try await client.executeText(prompt: prompt, modelId: modelId, temperature: temperature)
    }

    func executeTextWithImages(prompt: String, modelId: String, images: [Data], temperature: Double? = nil) async throws -> String {
        return try await client.executeTextWithImages(prompt: prompt, modelId: modelId, images: images, temperature: temperature)
    }

    // Structured
    func executeStructured<T: Decodable & Sendable>(prompt: String, modelId: String, as type: T.Type, temperature: Double? = nil) async throws -> T {
        return try await client.executeStructured(prompt: prompt, modelId: modelId, as: type, temperature: temperature)
    }

    func executeStructuredWithImages<T: Decodable & Sendable>(prompt: String, modelId: String, images: [Data], as type: T.Type, temperature: Double? = nil) async throws -> T {
        return try await client.executeStructuredWithImages(prompt: prompt, modelId: modelId, images: images, as: type, temperature: temperature)
    }

    // Streaming
    func startStreaming(prompt: String, modelId: String, temperature: Double? = nil) -> AsyncThrowingStream<LLMStreamChunkDTO, Error> {
        return client.startStreaming(prompt: prompt, modelId: modelId, temperature: temperature)
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
        let stream = llmService.continueConversationStreaming(
            userMessage: userMessage,
            modelId: modelId,
            conversationId: conversationId,
            reasoning: reasoning
        )
        return AsyncThrowingStream { continuation in
            Task {
                do {
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
