import Foundation
import SwiftUI

/// Protocol defining the interface for OpenAI clients
/// This abstraction allows us to switch between different OpenAI SDK implementations
protocol OpenAIClientProtocol {
    /// The API key to use for requests
    var apiKey: String { get }

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

    init(content: String, model: String) {
        self.content = content
        self.model = model
    }
}
