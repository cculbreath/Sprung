//
//  SwiftOpenAIClient.swift
//  PhysCloudResume
//
//  Adapter implementing LLMClient on top of existing LLMRequestExecutor.
//

import Foundation

final class SwiftOpenAIClient: LLMClient {
    // Reuse existing request executor and builders
    private let executor: LLMRequestExecutor
    private let defaultTemperature: Double = 1.0

    init(executor: LLMRequestExecutor = LLMRequestExecutor()) {
        self.executor = executor
        // Ensure client is configured
        Task {
            await self.executor.configureClient()
        }
    }

    func executeText(prompt: String, modelId: String, temperature: Double? = nil) async throws -> String {
        let params = LLMRequestBuilder.buildTextRequest(
            prompt: prompt,
            modelId: modelId,
            temperature: temperature ?? defaultTemperature
        )
        let response = try await executor.execute(parameters: params)
        guard let content = response.choices?.first?.message?.content else {
            throw LLMError.unexpectedResponseFormat
        }
        return content
    }

    func executeTextWithImages(prompt: String, modelId: String, images: [Data], temperature: Double? = nil) async throws -> String {
        let params = LLMRequestBuilder.buildVisionRequest(
            prompt: prompt,
            modelId: modelId,
            images: images,
            temperature: temperature ?? defaultTemperature
        )
        let response = try await executor.execute(parameters: params)
        guard let content = response.choices?.first?.message?.content else {
            throw LLMError.unexpectedResponseFormat
        }
        return content
    }

    func executeStructured<T: Codable & Sendable>(prompt: String, modelId: String, as: T.Type, temperature: Double? = nil) async throws -> T {
        let params = LLMRequestBuilder.buildStructuredRequest(
            prompt: prompt,
            modelId: modelId,
            responseType: T.self,
            temperature: temperature ?? defaultTemperature,
            jsonSchema: nil
        )
        let response = try await executor.execute(parameters: params)
        return try JSONResponseParser.parseStructured(response, as: T.self)
    }

    func executeStructuredWithImages<T: Codable & Sendable>(prompt: String, modelId: String, images: [Data], as: T.Type, temperature: Double? = nil) async throws -> T {
        let params = LLMRequestBuilder.buildStructuredVisionRequest(
            prompt: prompt,
            modelId: modelId,
            images: images,
            responseType: T.self,
            temperature: temperature ?? defaultTemperature
        )
        let response = try await executor.execute(parameters: params)
        return try JSONResponseParser.parseStructured(response, as: T.self)
    }

    func startStreaming(prompt: String, modelId: String, temperature: Double? = nil) -> AsyncThrowingStream<LLMStreamChunkDTO, Error> {
        var params = LLMRequestBuilder.buildTextRequest(
            prompt: prompt,
            modelId: modelId,
            temperature: temperature ?? defaultTemperature
        )
        params.stream = true

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let stream = try await executor.executeStreaming(parameters: params)
                    for try await chunk in stream {
                        if let ch = chunk.choices?.first {
                            let dto = LLMStreamChunkDTO(
                                content: ch.delta?.content,
                                reasoning: ch.delta?.reasoningContent,
                                isFinished: ch.finishReason != nil,
                                finishReason: {
                                    guard let finish = ch.finishReason else { return nil }
                                    switch finish { case .string(let s): return s; case .int(let i): return String(i) }
                                }()
                            )
                            continuation.yield(dto)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
