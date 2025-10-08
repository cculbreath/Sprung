//
//  LLMClient.swift
//  PhysCloudResume
//
//  A small, stable protocol and DTOs that decouple the app from vendor SDK types.
//

import Foundation

struct LLMStreamChunkDTO: Sendable {
    let content: String?
    let reasoning: String?
    let isFinished: Bool
    let finishReason: String?
}

protocol LLMClient {
    // Text
    func executeText(prompt: String, modelId: String, temperature: Double?) async throws -> String
    func executeTextWithImages(prompt: String, modelId: String, images: [Data], temperature: Double?) async throws -> String

    // Structured
    func executeStructured<T: Codable & Sendable>(prompt: String, modelId: String, as: T.Type, temperature: Double?) async throws -> T
    func executeStructuredWithImages<T: Codable & Sendable>(prompt: String, modelId: String, images: [Data], as: T.Type, temperature: Double?) async throws -> T

    // Streaming
    func startStreaming(prompt: String, modelId: String, temperature: Double?) -> AsyncThrowingStream<LLMStreamChunkDTO, Error>
}
