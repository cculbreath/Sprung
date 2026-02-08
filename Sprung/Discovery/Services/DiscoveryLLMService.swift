//
//  DiscoveryLLMService.swift
//  Sprung
//
//  LLM service for Discovery. Wraps LLMFacade and manages local context
//  for multi-turn conversations using ChatCompletions via OpenRouter.
//

import Foundation
import SwiftOpenAI
import SwiftyJSON

/// Service for LLM interactions in Discovery module.
/// Uses LLMFacade with ChatCompletions/OpenRouter backend.
/// Maintains local conversation context (unlike Onboarding which uses OpenAI Responses API).
@MainActor
final class DiscoveryLLMService {
    let llmFacade: LLMFacade
    private let settingsStore: DiscoverySettingsStore

    /// Active conversations indexed by conversation ID
    private var conversations: [UUID: DiscoveryConversation] = [:]

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

    // MARK: - Conversation Management (Stateful)

    /// Start a new conversation with optional tools
    /// - Parameters:
    ///   - systemPrompt: System prompt for the conversation
    ///   - tools: Optional tools for function calling
    ///   - overrideModelId: Override model ID (nil = use default from settings)
    func startConversation(
        systemPrompt: String,
        tools: [ChatCompletionParameters.Tool] = [],
        overrideModelId: String? = nil
    ) -> UUID {
        let conversationId = UUID()
        let conversation = DiscoveryConversation(
            id: conversationId,
            systemPrompt: systemPrompt,
            tools: tools,
            modelId: overrideModelId
        )
        conversations[conversationId] = conversation
        return conversationId
    }

    /// End a conversation and clean up
    func endConversation(_ conversationId: UUID) {
        conversations.removeValue(forKey: conversationId)
    }

    // MARK: - Single-Turn Tool Calling (No Auto-Loop)

    /// Send a message and get response with tool calls (does NOT auto-execute tools)
    /// Returns the raw message which may contain tool calls that caller must handle
    func sendMessageSingleTurn(
        conversationId: UUID,
        toolChoice: ToolChoice? = nil
    ) async throws -> ChatCompletionObject.ChatChoice.ChatMessage {
        guard var conversation = conversations[conversationId] else {
            throw DiscoveryLLMError.conversationNotFound
        }

        var messages: [ChatCompletionParameters.Message] = [
            .init(role: .system, content: .text(conversation.systemPrompt))
        ]
        messages.append(contentsOf: conversation.messages)

        let completion = try await llmFacade.executeWithTools(
            messages: messages,
            tools: conversation.tools,
            toolChoice: toolChoice ?? .auto,
            modelId: conversation.modelId ?? modelId
        )

        guard let choices = completion.choices,
              let choice = choices.first,
              let message = choice.message else {
            throw DiscoveryLLMError.invalidResponse
        }

        // Add assistant message to conversation
        let assistantContent: ChatCompletionParameters.Message.ContentType
        if let text = message.content {
            assistantContent = .text(text)
        } else {
            assistantContent = .text("")
        }
        conversation.messages.append(ChatCompletionParameters.Message(
            role: .assistant,
            content: assistantContent,
            toolCalls: message.toolCalls
        ))
        conversations[conversationId] = conversation

        return message
    }

    /// Add a tool result to the conversation
    func addToolResult(conversationId: UUID, toolCallId: String, result: String) {
        guard var conversation = conversations[conversationId] else { return }
        conversation.messages.append(ChatCompletionParameters.Message(
            role: .tool,
            content: .text(result),
            toolCallID: toolCallId
        ))
        conversations[conversationId] = conversation
    }

    /// Add a user message to the conversation
    func addUserMessage(conversationId: UUID, message: String) {
        guard var conversation = conversations[conversationId] else { return }
        conversation.messages.append(ChatCompletionParameters.Message(
            role: .user,
            content: .text(message)
        ))
        conversations[conversationId] = conversation
    }
}

// MARK: - Supporting Types

struct DiscoveryConversation {
    let id: UUID
    let systemPrompt: String
    let tools: [ChatCompletionParameters.Tool]
    let modelId: String?  // Override model ID (nil = use default)
    var messages: [ChatCompletionParameters.Message] = []
}

enum DiscoveryLLMError: Error, LocalizedError {
    case conversationNotFound
    case invalidResponse
    case toolExecutionFailed(String)
    case modelNotConfigured

    var errorDescription: String? {
        switch self {
        case .conversationNotFound:
            return "Conversation not found"
        case .invalidResponse:
            return "Invalid response from LLM"
        case .toolExecutionFailed(let reason):
            return "Tool execution failed: \(reason)"
        case .modelNotConfigured:
            return "No LLM model configured"
        }
    }
}
