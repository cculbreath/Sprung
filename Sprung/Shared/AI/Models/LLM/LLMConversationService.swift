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
