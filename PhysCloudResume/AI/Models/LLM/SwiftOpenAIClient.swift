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
        let dto = LLMVendorMapper.responseDTO(from: response)
        guard let content = dto.choices.first?.message?.text else {
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
        let dto = LLMVendorMapper.responseDTO(from: response)
        guard let content = dto.choices.first?.message?.text else {
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
        let dto = LLMVendorMapper.responseDTO(from: response)
        return try JSONResponseParser.parseStructured(dto, as: T.self)
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
        let dto = LLMVendorMapper.responseDTO(from: response)
        return try JSONResponseParser.parseStructured(dto, as: T.self)
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
                        let chunkDTO = LLMVendorMapper.streamChunkDTO(from: chunk)
                        continuation.yield(chunkDTO)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
