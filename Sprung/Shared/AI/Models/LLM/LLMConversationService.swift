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
        modelId: String
    ) async throws -> (UUID, String)
    func continueConversation(
        userMessage: String,
        modelId: String,
        conversationId: UUID,
        images: [Data]
    ) async throws -> String
}
protocol LLMStreamingConversationService: LLMConversationService {
    func startConversationStreaming(
        systemPrompt: String?,
        userMessage: String,
        modelId: String,
        images: [Data]
    ) async throws -> (UUID, AsyncThrowingStream<LLMStreamChunkDTO, Error>)
    func continueConversationStreaming(
        userMessage: String,
        modelId: String,
        conversationId: UUID,
        images: [Data]
    ) async throws -> AsyncThrowingStream<LLMStreamChunkDTO, Error>
}
final class OpenRouterConversationService: LLMConversationService {
    private let service: OpenRouterServiceBackend
    init(service: OpenRouterServiceBackend) {
        self.service = service
    }
    func startConversation(
        systemPrompt: String?,
        userMessage: String,
        modelId: String
    ) async throws -> (UUID, String) {
        try await service.startConversation(
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            modelId: modelId
        )
    }
    func continueConversation(
        userMessage: String,
        modelId: String,
        conversationId: UUID,
        images: [Data]
    ) async throws -> String {
        try await service.continueConversation(
            userMessage: userMessage,
            modelId: modelId,
            conversationId: conversationId,
            images: images
        )
    }
}
