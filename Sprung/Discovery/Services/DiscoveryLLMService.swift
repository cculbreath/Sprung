//
//  DiscoveryLLMService.swift
//  Sprung
//
//  Stateless structured-request helpers for Discovery. Wraps LLMFacade.
//  Multi-turn Discovery conversations run on the shared
//  AnthropicToolLoopRunner (see DiscoveryAgentService / CoachingService),
//  not through this service.
//

import Foundation
import SwiftOpenAI

/// Service for stateless LLM requests in the Discovery module.
@MainActor
final class DiscoveryLLMService {
    let llmFacade: LLMFacade
    private let settingsStore: DiscoverySettingsStore

    init(llmFacade: LLMFacade, settingsStore: DiscoverySettingsStore) {
        self.llmFacade = llmFacade
        self.settingsStore = settingsStore
    }

    /// Get the configured model ID for Discovery
    var modelId: String {
        settingsStore.current().llmModelId
    }

    // MARK: - Simple Structured Requests (Stateless)

    /// Execute a simple structured request without maintaining conversation state.
    /// Use for one-shot LLM calls like generating daily tasks or discovering sources.
    /// - Parameter backend: Which LLM backend to use (.openRouter default, .openAI for web_search)
    /// - Parameter modelId: Model ID to use (defaults to discovery model from settings)
    /// - Parameter schema: JSON schema for structured output (required for .openAI backend)
    /// - Parameter schemaName: Name for the schema (required for .openAI backend)
    func executeStructured<T: Codable & Sendable>(
        prompt: String,
        systemPrompt: String? = nil,
        as type: T.Type,
        backend: LLMFacade.Backend = .openRouter,
        modelId: String? = nil,
        schema: JSONSchema? = nil,
        schemaName: String? = nil
    ) async throws -> T {
        var fullPrompt = prompt
        if let sys = systemPrompt {
            fullPrompt = "\(sys)\n\n\(prompt)"
        }

        // For OpenAI backend, use schema-based structured output
        if backend == .openAI {
            guard let schema = schema, let schemaName = schemaName else {
                throw DiscoveryLLMError.toolExecutionFailed("OpenAI backend requires schema and schemaName for structured output")
            }
            return try await llmFacade.executeStructuredWithSchema(
                prompt: fullPrompt,
                modelId: modelId ?? self.modelId,
                as: type,
                schema: schema,
                schemaName: schemaName,
                backend: backend
            )
        }

        return try await llmFacade.executeStructured(
            prompt: fullPrompt,
            modelId: modelId ?? self.modelId,
            as: type,
            backend: backend
        )
    }

    /// Execute a flexible JSON request that can work with or without strict schema
    /// - Parameter backend: Which LLM backend to use (.openRouter default, .openAI for web_search)
    /// - Parameter modelId: Model ID to use (defaults to discovery model from settings)
    /// - Parameter schema: JSON schema for structured output (required for .openAI backend)
    /// - Parameter schemaName: Name for the schema (required for .openAI backend)
    func executeFlexibleJSON<T: Codable & Sendable>(
        prompt: String,
        systemPrompt: String? = nil,
        as type: T.Type,
        jsonSchema: JSONSchema? = nil,
        backend: LLMFacade.Backend = .openRouter,
        modelId: String? = nil,
        schemaName: String? = nil
    ) async throws -> T {
        var fullPrompt = prompt
        if let sys = systemPrompt {
            fullPrompt = "\(sys)\n\n\(prompt)"
        }

        // For OpenAI backend, use schema-based structured output
        if backend == .openAI {
            guard let schema = jsonSchema, let schemaName = schemaName else {
                throw DiscoveryLLMError.toolExecutionFailed("OpenAI backend requires jsonSchema and schemaName for structured output")
            }
            return try await llmFacade.executeStructuredWithSchema(
                prompt: fullPrompt,
                modelId: modelId ?? self.modelId,
                as: type,
                schema: schema,
                schemaName: schemaName,
                backend: backend
            )
        }

        return try await llmFacade.executeFlexibleJSON(
            prompt: fullPrompt,
            modelId: modelId ?? self.modelId,
            as: type,
            jsonSchema: jsonSchema,
            backend: backend
        )
    }
}

// MARK: - Supporting Types

enum DiscoveryLLMError: Error, LocalizedError {
    case conversationNotFound
    case toolExecutionFailed(String)

    var errorDescription: String? {
        switch self {
        case .conversationNotFound:
            return "Conversation not found"
        case .toolExecutionFailed(let reason):
            return "Tool execution failed: \(reason)"
        }
    }
}
