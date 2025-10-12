//
//  RevisionStreamingService.swift
//  Sprung
//

import Foundation

/// Service responsible for managing LLM streaming and reasoning coordination
/// Handles streaming responses, reasoning display, and response collection
@MainActor
class RevisionStreamingService {

    // MARK: - Dependencies
    private let llm: LLMFacade
    private let reasoningStreamManager: ReasoningStreamManager

    // MARK: - State
    private var activeStreamingHandle: LLMStreamingHandle?

    init(llm: LLMFacade, reasoningStreamManager: ReasoningStreamManager) {
        self.llm = llm
        self.reasoningStreamManager = reasoningStreamManager
    }

    // MARK: - Public Interface

    /// Start a new streaming conversation with reasoning support
    /// - Parameters:
    ///   - systemPrompt: The system prompt for the conversation
    ///   - userMessage: The initial user message
    ///   - modelId: The model ID to use
    ///   - reasoning: Reasoning configuration
    ///   - jsonSchema: Expected JSON schema for response
    /// - Returns: Parsed revisions container and conversation ID
    func startConversationStreaming(
        systemPrompt: String,
        userMessage: String,
        modelId: String,
        reasoning: OpenRouterReasoning,
        jsonSchema: [String: Any]
    ) async throws -> (revisions: RevisionsContainer, conversationId: UUID) {

        // Start streaming conversation with reasoning
        cancelActiveStreaming()
        let handle = try await llm.startConversationStreaming(
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            modelId: modelId,
            reasoning: reasoning,
            jsonSchema: jsonSchema
        )

        guard let conversationId = handle.conversationId else {
            throw LLMError.clientError("Failed to establish conversation for revision streaming")
        }

        activeStreamingHandle = handle

        // Process stream and collect full response
        let responseText = try await processStreamWithReasoning(handle: handle, modelName: modelId)

        // Parse the JSON response
        let revisions = try LLMResponseParser.parseJSON(responseText, as: RevisionsContainer.self)

        return (revisions, conversationId)
    }

    /// Continue an existing conversation with streaming
    /// - Parameters:
    ///   - userMessage: The user message to continue with
    ///   - modelId: The model ID to use
    ///   - conversationId: The existing conversation ID
    ///   - reasoning: Reasoning configuration
    ///   - jsonSchema: Expected JSON schema for response
    /// - Returns: Parsed revisions container
    func continueConversationStreaming(
        userMessage: String,
        modelId: String,
        conversationId: UUID,
        reasoning: OpenRouterReasoning,
        jsonSchema: [String: Any]
    ) async throws -> RevisionsContainer {

        // Start streaming
        cancelActiveStreaming()
        let handle = try await llm.continueConversationStreaming(
            userMessage: userMessage,
            modelId: modelId,
            conversationId: conversationId,
            images: [],
            temperature: nil,
            reasoning: reasoning,
            jsonSchema: jsonSchema
        )
        activeStreamingHandle = handle

        // Process stream and collect full response
        let responseText = try await processStreamWithReasoning(handle: handle, modelName: modelId)

        // Parse the JSON response
        return try LLMResponseParser.parseJSON(responseText, as: RevisionsContainer.self)
    }

    /// Cancel any active streaming operation
    func cancelActiveStreaming() {
        activeStreamingHandle?.cancel()
        activeStreamingHandle = nil
    }

    // MARK: - Private Helpers

    /// Process streaming response with reasoning coordination
    /// - Parameters:
    ///   - handle: The streaming handle
    ///   - modelName: The model name for display
    /// - Returns: The full text response for parsing
    private func processStreamWithReasoning(
        handle: LLMStreamingHandle,
        modelName: String
    ) async throws -> String {

        // Clear any previous reasoning text before starting
        reasoningStreamManager.clear()
        reasoningStreamManager.startReasoning(modelName: modelName)

        var fullResponse = ""
        var collectingJSON = false
        var jsonResponse = ""

        for try await chunk in handle.stream {
            // Handle reasoning content
            if let reasoningContent = chunk.reasoning {
                reasoningStreamManager.reasoningText += reasoningContent
            }

            // Collect regular content
            if let content = chunk.content {
                fullResponse += content

                // Try to extract JSON from the response
                if content.contains("{") || collectingJSON {
                    collectingJSON = true
                    jsonResponse += content
                }
            }

            // Handle completion
            if chunk.isFinished {
                reasoningStreamManager.isStreaming = false
                // Hide the reasoning modal when streaming completes
                reasoningStreamManager.isVisible = false
            }
        }

        cancelActiveStreaming()

        // Return JSON response if found, otherwise full response
        return jsonResponse.isEmpty ? fullResponse : jsonResponse
    }
}
