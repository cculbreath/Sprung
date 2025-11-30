//
//  LLMConversationService.swift
//  Sprung
//
//  Defines a lightweight abstraction for backends that support multi-turn
//  conversations. LLMFacade uses this to route conversational traffic to the
//  appropriate provider (OpenRouter, OpenAI Responses, etc.).
//
import Foundation
protocol LLMConversationService: AnyObject {
    func startConversation(
        systemPrompt: String?,
        userMessage: String,
        modelId: String,
        temperature: Double?
    ) async throws -> (UUID, String)
    func continueConversation(
        userMessage: String,
        modelId: String,
        conversationId: UUID,
        images: [Data],
        temperature: Double?
    ) async throws -> String
}
protocol LLMStreamingConversationService: LLMConversationService {
    func startConversationStreaming(
        systemPrompt: String?,
        userMessage: String,
        modelId: String,
        temperature: Double?,
        images: [Data]
    ) async throws -> (UUID, AsyncThrowingStream<LLMStreamChunkDTO, Error>)
    func continueConversationStreaming(
        userMessage: String,
        modelId: String,
        conversationId: UUID,
        images: [Data],
        temperature: Double?
    ) async throws -> AsyncThrowingStream<LLMStreamChunkDTO, Error>
}
final class OpenRouterConversationService: LLMConversationService {
    private let service: _LLMService
    init(service: _LLMService) {
        self.service = service
    }
    func startConversation(
        systemPrompt: String?,
        userMessage: String,
        modelId: String,
        temperature: Double?
    ) async throws -> (UUID, String) {
        try await service.startConversation(
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            modelId: modelId,
            temperature: temperature
        )
    }
    func continueConversation(
        userMessage: String,
        modelId: String,
        conversationId: UUID,
        images: [Data],
        temperature: Double?
    ) async throws -> String {
        try await service.continueConversation(
            userMessage: userMessage,
            modelId: modelId,
            conversationId: conversationId,
            images: images,
            temperature: temperature
        )
    }
}
