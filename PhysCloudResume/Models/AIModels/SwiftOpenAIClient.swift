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
        self.service = OpenAIService(apiKey: apiKey)
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
                role: ChatCompletionParameters.Message.Role(rawValue: message.role.rawValue) ?? .user,
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
                   let content = message.content {
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
                role: ChatCompletionParameters.Message.Role(rawValue: message.role.rawValue) ?? .user,
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
              let content = message.content else {
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
}