//
//  OpenAIClientProtocol.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 4/22/25.
//

import Foundation
import SwiftUI

/// Protocol defining the interface for OpenAI clients
/// This abstraction allows us to switch between different OpenAI SDK implementations
protocol OpenAIClientProtocol {
    /// The API key to use for requests
    var apiKey: String { get }

    // MARK: - Chat Completion API (Legacy)

    /// Sends a chat completion request
    /// - Parameters:
    ///   - messages: The conversation history
    ///   - model: The model to use for completion
    ///   - temperature: Controls randomness (0-1)
    ///   - onComplete: Callback with completion response
    /// - Returns: A completion with the model's response
    func sendChatCompletion(
        messages: [ChatMessage],
        model: String,
        temperature: Double,
        onComplete: @escaping (Result<ChatCompletionResponse, Error>) -> Void
    )

    /// Sends a chat completion request using async/await
    /// - Parameters:
    ///   - messages: The conversation history
    ///   - model: The model to use for completion
    ///   - temperature: Controls randomness (0-1)
    /// - Returns: A completion with the model's response
    func sendChatCompletionAsync(
        messages: [ChatMessage],
        model: String,
        temperature: Double
    ) async throws -> ChatCompletionResponse

    /// Sends a chat completion request with streaming
    /// - Parameters:
    ///   - messages: The conversation history
    ///   - model: The model to use for completion
    ///   - temperature: Controls randomness (0-1)
    ///   - onChunk: Callback for each chunk of the streaming response
    ///   - onComplete: Callback when streaming is complete
    func sendChatCompletionStreaming(
        messages: [ChatMessage],
        model: String,
        temperature: Double,
        onChunk: @escaping (Result<ChatCompletionResponse, Error>) -> Void,
        onComplete: @escaping (Error?) -> Void
    )

    // MARK: - Responses API (New)

    /// Sends a request to the OpenAI Responses API
    /// - Parameters:
    ///   - message: The current message content
    ///   - model: The model to use
    ///   - temperature: Controls randomness (0-1)
    ///   - previousResponseId: Optional ID from a previous response for conversation state
    ///   - onComplete: Callback with the response
    func sendResponseRequest(
        message: String,
        model: String,
        temperature: Double,
        previousResponseId: String?,
        onComplete: @escaping (Result<ResponsesAPIResponse, Error>) -> Void
    )

    /// Sends a request to the OpenAI Responses API using async/await
    /// - Parameters:
    ///   - message: The current message content
    ///   - model: The model to use
    ///   - temperature: Controls randomness (0-1)
    ///   - previousResponseId: Optional ID from a previous response for conversation state
    /// - Returns: The response from the Responses API
    func sendResponseRequestAsync(
        message: String,
        model: String,
        temperature: Double,
        previousResponseId: String?
    ) async throws -> ResponsesAPIResponse

    /// Sends a streaming request to the OpenAI Responses API
    /// - Parameters:
    ///   - message: The current message content
    ///   - model: The model to use
    ///   - temperature: Controls randomness (0-1)
    ///   - previousResponseId: Optional ID from a previous response for conversation state
    ///   - onChunk: Callback for each chunk of the streaming response
    ///   - onComplete: Callback when streaming is complete
    func sendResponseRequestStreaming(
        message: String,
        model: String,
        temperature: Double,
        previousResponseId: String?,
        onChunk: @escaping (Result<ResponsesAPIStreamChunk, Error>) -> Void,
        onComplete: @escaping (Error?) -> Void
    )

    // MARK: - Text-to-Speech API

    /// Sends a TTS (Text-to-Speech) request
    /// - Parameters:
    ///   - text: The text to convert to speech
    ///   - voice: The voice to use
    ///   - instructions: Voice instructions for TTS generation (optional)
    ///   - onComplete: Callback with audio data
    func sendTTSRequest(
        text: String,
        voice: String,
        instructions: String?,
        onComplete: @escaping (Result<Data, Error>) -> Void
    )

    /// Sends a streaming TTS (Text-to-Speech) request
    /// - Parameters:
    ///   - text: The text to convert to speech
    ///   - voice: The voice to use
    ///   - instructions: Voice instructions for TTS generation (optional)
    ///   - onChunk: Callback for each chunk of audio data
    ///   - onComplete: Callback when streaming is complete
    func sendTTSStreamingRequest(
        text: String,
        voice: String,
        instructions: String?,
        onChunk: @escaping (Result<Data, Error>) -> Void,
        onComplete: @escaping (Error?) -> Void
    )
}

/// Represents a chat message in a conversation
struct ChatMessage: Codable, Equatable {
    /// The role of the message sender (system, user, assistant)
    let role: ChatRole
    /// The content of the message
    let content: String

    /// Creates a new chat message
    /// - Parameters:
    ///   - role: The role of the message sender
    ///   - content: The content of the message
    init(role: ChatRole, content: String) {
        self.role = role
        self.content = content
    }

    enum ChatRole: String, Codable {
        case system
        case user
        case assistant
    }
}

/// Response from an OpenAI chat completion request
struct ChatCompletionResponse: Codable, Equatable {
    /// The completion text
    let content: String
    /// The model used for the completion
    let model: String
    /// The response ID from OpenAI (used for the Responses API)
    var id: String?

    init(content: String, model: String, id: String? = nil) {
        self.content = content
        self.model = model
        self.id = id
    }
}

/// Response from an OpenAI Responses API request
struct ResponsesAPIResponse: Codable, Equatable {
    /// The unique ID of the response (used for continuation)
    let id: String
    /// The content of the response
    let content: String
    /// The model used for the response
    let model: String

    /// Converts to a ChatCompletionResponse for backward compatibility
    func toChatCompletionResponse() -> ChatCompletionResponse {
        return ChatCompletionResponse(content: content, model: model, id: id)
    }
}

/// A chunk from a streaming Responses API request
struct ResponsesAPIStreamChunk: Codable, Equatable {
    /// The ID of the response (only present in the final chunk)
    let id: String?
    /// The content of the chunk
    let content: String
    /// The model used for the response
    let model: String
}
