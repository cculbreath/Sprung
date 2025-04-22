import Foundation
import SwiftOpenAI

/// Implementation of OpenAIClientProtocol using SwiftOpenAI library
class SwiftOpenAIClient: OpenAIClientProtocol {
    private let service: OpenAIService

    /// The API key used for requests
    var apiKey: String {
        service.apiKey
    }

    /// Initializes a new client with the given API key
    /// - Parameter apiKey: The API key to use for requests
    init(apiKey: String) {
        service = OpenAIService(apiKey: apiKey)
    }

    /// Sends a chat completion request
    /// - Parameters:
    ///   - messages: The conversation history
    ///   - model: The model to use for completion
    ///   - temperature: Controls randomness (0-1)
    ///   - onComplete: Callback with completion response
    func sendChatCompletion(
        messages: [ChatMessage],
        model: String,
        temperature: Double = 0.7,
        onComplete: @escaping (Result<ChatCompletionResponse, Error>) -> Void
    ) {
        // Convert input messages to SwiftOpenAI format
        let chatMessages = messages.map { message in
            ChatCompletionParameters.Message(
                role: ChatCompletionParameters.Message.Role(rawValue: String(describing: message.role)) ?? .user,
                content: .text(message.content)
            )
        }

        // Create chat completion parameters
        let parameters = ChatCompletionParameters(
            messages: chatMessages,
            model: OpenAIModelFetcher.modelFromString(model),
            temperature: temperature,
            responseFormat: .text
        )

        // Send the request
        Task {
            do {
                let result = try await service.startChat(parameters: parameters)

                // Extract the response content
                if let firstChoice = result.choices?.first,
                   let message = firstChoice.message,
                   let content = message.content
                {
                    // Call the completion handler with success
                    let response = ChatCompletionResponse(
                        content: content,
                        model: model
                    )
                    onComplete(.success(response))
                } else {
                    // Handle empty or invalid response
                    onComplete(.failure(NSError(
                        domain: "SwiftOpenAIClient",
                        code: 1001,
                        userInfo: [NSLocalizedDescriptionKey: "No valid response content"]
                    )))
                }
            } catch {
                // Forward the error
                onComplete(.failure(error))
            }
        }
    }

    /// Sends a chat completion request using async/await
    /// - Parameters:
    ///   - messages: The conversation history
    ///   - model: The model to use for completion
    ///   - temperature: Controls randomness (0-1)
    /// - Returns: A completion with the model's response
    func sendChatCompletionAsync(
        messages: [ChatMessage],
        model: String,
        temperature: Double = 0.7
    ) async throws -> ChatCompletionResponse {
        // Convert input messages to SwiftOpenAI format
        let chatMessages = messages.map { message in
            ChatCompletionParameters.Message(
                role: ChatCompletionParameters.Message.Role(rawValue: String(describing: message.role)) ?? .user,
                content: .text(message.content)
            )
        }

        // Create chat completion parameters
        let parameters = ChatCompletionParameters(
            messages: chatMessages,
            model: OpenAIModelFetcher.modelFromString(model),
            temperature: temperature,
            responseFormat: .text
        )

        // Send the request and await the result
        let result = try await service.startChat(parameters: parameters)

        // Extract the response content
        guard let firstChoice = result.choices?.first,
              let message = firstChoice.message,
              let content = message.content
        else {
            throw NSError(
                domain: "SwiftOpenAIClient",
                code: 1001,
                userInfo: [NSLocalizedDescriptionKey: "No valid response content"]
            )
        }

        // Return the response
        return ChatCompletionResponse(
            content: content,
            model: model
        )
    }
    
    /// Sends a chat completion request with streaming - NOT SUPPORTED in SwiftOpenAI
    /// - Parameters:
    ///   - messages: The conversation history
    ///   - model: The model to use for completion
    ///   - temperature: Controls randomness (0-1)
    ///   - onChunk: Callback for each chunk of the streaming response
    ///   - onComplete: Callback when streaming is complete
    func sendChatCompletionStreaming(
        messages: [ChatMessage],
        model: String,
        temperature: Double = 0.7,
        onChunk: @escaping (Result<ChatCompletionResponse, Error>) -> Void,
        onComplete: @escaping (Error?) -> Void
    ) {
        let error = NSError(
            domain: "SwiftOpenAIClient",
            code: 1002,
            userInfo: [NSLocalizedDescriptionKey: "Streaming is not supported in SwiftOpenAI - use MacPawOpenAIClient instead"]
        )
        
        // Notify of error and complete
        onChunk(.failure(error))
        onComplete(error)
    }
    
    /// Sends a TTS (Text-to-Speech) request - NOT SUPPORTED in SwiftOpenAI
    /// - Parameters:
    ///   - text: The text to convert to speech
    ///   - voice: The voice to use
    ///   - onComplete: Callback with audio data
    func sendTTSRequest(
        text: String,
        voice: String,
        onComplete: @escaping (Result<Data, Error>) -> Void
    ) {
        let error = NSError(
            domain: "SwiftOpenAIClient",
            code: 1003,
            userInfo: [NSLocalizedDescriptionKey: "TTS is not supported in SwiftOpenAI - use MacPawOpenAIClient instead"]
        )
        
        // Notify of error
        onComplete(.failure(error))
    }
    
    /// Sends a streaming TTS (Text-to-Speech) request - NOT SUPPORTED in SwiftOpenAI
    /// - Parameters:
    ///   - text: The text to convert to speech
    ///   - voice: The voice to use
    ///   - onChunk: Callback for each chunk of audio data
    ///   - onComplete: Callback when streaming is complete
    func sendTTSStreamingRequest(
        text: String,
        voice: String,
        onChunk: @escaping (Result<Data, Error>) -> Void,
        onComplete: @escaping (Error?) -> Void
    ) {
        let error = NSError(
            domain: "SwiftOpenAIClient",
            code: 1004,
            userInfo: [NSLocalizedDescriptionKey: "TTS streaming is not supported in SwiftOpenAI - use MacPawOpenAIClient instead"]
        )
        
        // Notify of error and complete
        onChunk(.failure(error))
        onComplete(error)
    }
}
