//
//  SearchOpsLLMService.swift
//  Sprung
//
//  LLM service for SearchOps. Wraps LLMFacade and manages local context
//  for multi-turn conversations using ChatCompletions via OpenRouter.
//

import Foundation
import SwiftOpenAI
import SwiftyJSON

/// Service for LLM interactions in SearchOps module.
/// Uses LLMFacade with ChatCompletions/OpenRouter backend.
/// Maintains local conversation context (unlike Onboarding which uses OpenAI Responses API).
@MainActor
final class SearchOpsLLMService {
    let llmFacade: LLMFacade
    private let settingsStore: SearchOpsSettingsStore

    /// Active conversations indexed by conversation ID
    private var conversations: [UUID: SearchOpsConversation] = [:]

    init(llmFacade: LLMFacade, settingsStore: SearchOpsSettingsStore) {
        self.llmFacade = llmFacade
        self.settingsStore = settingsStore
    }

    /// Get the configured model ID for SearchOps
    var modelId: String {
        settingsStore.current().llmModelId
    }

    // MARK: - Simple Structured Requests (Stateless)

    /// Execute a simple structured request without maintaining conversation state.
    /// Use for one-shot LLM calls like generating daily tasks or discovering sources.
    func executeStructured<T: Codable & Sendable>(
        prompt: String,
        systemPrompt: String? = nil,
        as type: T.Type,
        temperature: Double = 0.7
    ) async throws -> T {
        var fullPrompt = prompt
        if let sys = systemPrompt {
            fullPrompt = "\(sys)\n\n\(prompt)"
        }

        return try await llmFacade.executeStructured(
            prompt: fullPrompt,
            modelId: modelId,
            as: type,
            temperature: temperature
        )
    }

    /// Execute a flexible JSON request that can work with or without strict schema
    func executeFlexibleJSON<T: Codable & Sendable>(
        prompt: String,
        systemPrompt: String? = nil,
        as type: T.Type,
        jsonSchema: JSONSchema? = nil,
        temperature: Double = 0.7
    ) async throws -> T {
        var fullPrompt = prompt
        if let sys = systemPrompt {
            fullPrompt = "\(sys)\n\n\(prompt)"
        }

        return try await llmFacade.executeFlexibleJSON(
            prompt: fullPrompt,
            modelId: modelId,
            as: type,
            temperature: temperature,
            jsonSchema: jsonSchema
        )
    }

    /// Execute a simple text request
    func executeText(
        prompt: String,
        systemPrompt: String? = nil,
        temperature: Double = 0.7,
        overrideModelId: String? = nil
    ) async throws -> String {
        var fullPrompt = prompt
        if let sys = systemPrompt {
            fullPrompt = "\(sys)\n\n\(prompt)"
        }

        return try await llmFacade.executeText(
            prompt: fullPrompt,
            modelId: overrideModelId ?? modelId,
            temperature: temperature
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
        let conversation = SearchOpsConversation(
            id: conversationId,
            systemPrompt: systemPrompt,
            tools: tools,
            modelId: overrideModelId
        )
        conversations[conversationId] = conversation
        return conversationId
    }

    /// Send a user message and get response (handles tool calls internally if configured)
    /// - Parameters:
    ///   - message: The user message to send
    ///   - conversationId: The conversation ID
    ///   - toolChoice: Optional tool choice to force a specific tool (e.g., `.function(name: "tool_name")`)
    ///   - handleToolCalls: Handler for processing tool calls
    func sendMessage(
        _ message: String,
        conversationId: UUID,
        toolChoice: ToolChoice? = nil,
        handleToolCalls: ((String, JSON) async throws -> JSON)? = nil
    ) async throws -> String {
        guard var conversation = conversations[conversationId] else {
            throw SearchOpsLLMError.conversationNotFound
        }

        // Add user message to context
        conversation.messages.append(.init(
            role: .user,
            content: .text(message)
        ))

        // Execute with tools if configured
        if !conversation.tools.isEmpty {
            return try await executeWithToolLoop(
                conversation: &conversation,
                toolChoice: toolChoice,
                handleToolCalls: handleToolCalls
            )
        }

        // Simple completion without tools
        let (_, response) = try await llmFacade.startConversation(
            systemPrompt: conversation.systemPrompt,
            userMessage: message,
            modelId: modelId
        )

        // Add assistant response to context
        conversation.messages.append(.init(
            role: .assistant,
            content: .text(response)
        ))

        conversations[conversationId] = conversation
        return response
    }

    /// Continue a conversation using LLMFacade's conversation API
    func continueConversation(
        _ message: String,
        conversationId: UUID
    ) async throws -> String {
        guard var conversation = conversations[conversationId] else {
            throw SearchOpsLLMError.conversationNotFound
        }

        // Use LLMFacade's conversation continuation if we have an underlying conversation ID
        let response: String
        if let underlyingId = conversation.underlyingConversationId {
            response = try await llmFacade.continueConversation(
                userMessage: message,
                modelId: modelId,
                conversationId: underlyingId
            )
        } else {
            // Start a new underlying conversation
            let (newId, resp) = try await llmFacade.startConversation(
                systemPrompt: conversation.systemPrompt,
                userMessage: message,
                modelId: modelId
            )
            conversation.underlyingConversationId = newId
            response = resp
        }

        // Update local context
        conversation.messages.append(.init(role: .user, content: .text(message)))
        conversation.messages.append(.init(role: .assistant, content: .text(response)))
        conversations[conversationId] = conversation

        return response
    }

    /// End a conversation and clean up
    func endConversation(_ conversationId: UUID) {
        conversations.removeValue(forKey: conversationId)
    }

    // MARK: - Tool Calling

    private func executeWithToolLoop(
        conversation: inout SearchOpsConversation,
        toolChoice: ToolChoice? = nil,
        handleToolCalls: ((String, JSON) async throws -> JSON)?
    ) async throws -> String {
        var maxIterations = 10  // Prevent infinite loops
        var currentToolChoice = toolChoice ?? .auto  // Use provided or default to auto

        while maxIterations > 0 {
            maxIterations -= 1

            // Build messages array for ChatCompletion
            var messages: [ChatCompletionParameters.Message] = [
                .init(role: .system, content: .text(conversation.systemPrompt))
            ]
            messages.append(contentsOf: conversation.messages)

            // Execute with tools (use conversation's model ID if specified)
            let completion = try await llmFacade.executeWithTools(
                messages: messages,
                tools: conversation.tools,
                toolChoice: currentToolChoice,
                modelId: conversation.modelId ?? modelId,
                temperature: 0.7
            )

            // After first tool call, switch to auto for subsequent iterations
            currentToolChoice = .auto

            guard let choices = completion.choices,
                  let choice = choices.first,
                  let message = choice.message else {
                throw SearchOpsLLMError.invalidResponse
            }

            // Check for tool calls
            if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                // Add assistant message with tool calls (pass toolCalls directly - types are compatible)
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

                // Process tool calls
                for toolCall in toolCalls {
                    let toolCallId = toolCall.id ?? UUID().uuidString
                    let toolName = toolCall.function.name ?? "unknown"
                    let arguments = JSON(parseJSON: toolCall.function.arguments)

                    // Execute tool via handler
                    let result: JSON
                    if let handler = handleToolCalls {
                        result = try await handler(toolName, arguments)
                    } else {
                        result = JSON(["error": "No tool handler configured"])
                    }

                    // Add tool result to context
                    conversation.messages.append(ChatCompletionParameters.Message(
                        role: .tool,
                        content: .text(result.rawString() ?? "{}"),
                        toolCallID: toolCallId
                    ))

                    // Check if tool handler signals to pause for user input
                    if result["_pauseForUser"].boolValue {
                        conversations[conversation.id] = conversation
                        throw SearchOpsLLMError.pausedForUserInput
                    }
                }

                // Continue loop to get assistant's final response
                continue
            }

            // No tool calls - we have final response
            let responseText = message.content ?? ""
            conversation.messages.append(ChatCompletionParameters.Message(
                role: .assistant,
                content: .text(responseText)
            ))

            conversations[conversation.id] = conversation
            return responseText
        }

        throw SearchOpsLLMError.toolLoopExceeded
    }

    // MARK: - Conversation State Access

    func getConversation(_ id: UUID) -> SearchOpsConversation? {
        conversations[id]
    }

    func conversationMessageCount(_ id: UUID) -> Int {
        conversations[id]?.messages.count ?? 0
    }
}

// MARK: - Supporting Types

struct SearchOpsConversation {
    let id: UUID
    let systemPrompt: String
    let tools: [ChatCompletionParameters.Tool]
    let modelId: String?  // Override model ID (nil = use default)
    var messages: [ChatCompletionParameters.Message] = []
    var underlyingConversationId: UUID?
}

enum SearchOpsLLMError: Error, LocalizedError {
    case conversationNotFound
    case invalidResponse
    case toolLoopExceeded
    case toolExecutionFailed(String)
    case pausedForUserInput

    var errorDescription: String? {
        switch self {
        case .conversationNotFound:
            return "Conversation not found"
        case .invalidResponse:
            return "Invalid response from LLM"
        case .toolLoopExceeded:
            return "Tool call loop exceeded maximum iterations"
        case .toolExecutionFailed(let reason):
            return "Tool execution failed: \(reason)"
        case .pausedForUserInput:
            return "Waiting for user input"
        }
    }
}
