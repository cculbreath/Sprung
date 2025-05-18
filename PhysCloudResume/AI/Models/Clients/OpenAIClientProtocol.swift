//
//  OpenAIClientProtocol.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 4/22/25.
//

import Foundation
import PDFKit
import AppKit
import SwiftUI

/// Protocol defining the interface for OpenAI clients
/// This abstraction allows us to switch between different OpenAI SDK implementations
protocol OpenAIClientProtocol {
    /// The API key to use for requests
    var apiKey: String { get }

    // MARK: - Chat Completion API (Legacy)

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

    // MARK: - Chat Completion with Structured Output

    /// Sends a chat completion request with structured output using async/await
    /// - Parameters:
    ///   - messages: The conversation history
    ///   - model: The model to use for completion
    ///   - temperature: Controls randomness (0-1)
    ///   - structuredOutputType: The type to use for structured output
    /// - Returns: A completion with the model's response
    func sendChatCompletionWithStructuredOutput<T: StructuredOutput>(
        messages: [ChatMessage],
        model: String,
        temperature: Double,
        structuredOutputType: T.Type
    ) async throws -> T

    // MARK: - Responses API (New)

    /// Sends a request to the OpenAI Responses API using async/await
    /// - Parameters:
    ///   - message: The current message content
    ///   - model: The model to use
    ///   - temperature: Controls randomness (0-1)
    ///   - previousResponseId: Optional ID from a previous response for conversation state
    ///   - schema: Optional JSON schema for structured output
    /// - Returns: The response from the Responses API
    func sendResponseRequestAsync(
        message: String,
        model: String,
        temperature: Double?,
        previousResponseId: String?,
        schema: String?
    ) async throws -> ResponsesAPIResponse

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

// Response types are now defined in AI/Models/ResponseTypes/APIResponses.swift
