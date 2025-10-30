//
//  SwiftOpenAIClient.swift
//  Sprung
//
//  Adapter implementing LLMClient on top of existing LLMRequestExecutor.
//

import Foundation
import SwiftOpenAI

// MARK: - Sprung Logger Adapter for SwiftOpenAI

/// Implements OpenAILoggerProtocol to route SwiftOpenAI logs through Sprung's centralized Logger
private class SprungOpenAILogger: OpenAILoggerProtocol {
  func debug(_ message: String) {
    Logger.debug(message, category: .ai)
  }

  func error(_ message: String) {
    Logger.error(message, category: .ai)
  }
}

final class SwiftOpenAIClient: LLMClient {
    // Reuse existing request executor and builders
    private let executor: LLMRequestExecutor
    private let defaultTemperature: Double = 1.0

    // Class-level flag to ensure logger is only injected once
    private static var loggerInjected = false
    private static let loggerInjectionLock = NSLock()

    init(executor: LLMRequestExecutor = LLMRequestExecutor()) {
        self.executor = executor

        // Inject Sprung's Logger into SwiftOpenAI for unified logging with timestamps
        // Only inject once to avoid repeated initialization
        Self.loggerInjectionLock.lock()
        defer { Self.loggerInjectionLock.unlock() }

        if !Self.loggerInjected {
            setOpenAILogger(SprungOpenAILogger())
            Self.loggerInjected = true
            Logger.debug("Injected Sprung's Logger into SwiftOpenAI", category: .ai)
        }

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

}
