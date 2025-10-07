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

    init(client: LLMClient) {
        self.client = client
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
}

