//
//  LegacyOpenAIClientAdapter.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 5/20/25.
//

import Foundation
import SwiftOpenAI

/// Adapter that wraps AppLLMClientProtocol to provide OpenAIClientProtocol compatibility
/// This allows gradual migration of existing code to the new unified interface
/// @available(*, deprecated, message: "Use AppLLMClientProtocol directly instead")
class LegacyOpenAIClientAdapter: OpenAIClientProtocol {
    /// The underlying app LLM client
    private let appLLMClient: AppLLMClientProtocol
    
    /// The API key (for protocol compatibility)
    let apiKey: String
    
    // MARK: - Initializers
    
    /// Initializes a new client with the given custom configuration
    /// - Parameter configuration: The custom configuration to use for requests
    /// @available(*, deprecated, message: "Use AppLLMClientFactory.createClient instead")
    required init(configuration: OpenAIConfiguration) {
        self.apiKey = configuration.token ?? ""
        
        // Create appropriate config for the provider
        let providerType: String
        if configuration.host == "api.anthropic.com" {
            providerType = AIModels.Provider.claude
        } else if configuration.host == "api.groq.com" || configuration.host == "api.x.ai" {
            providerType = AIModels.Provider.grok
        } else if configuration.host == "generativelanguage.googleapis.com" {
            providerType = AIModels.Provider.gemini
        } else {
            providerType = AIModels.Provider.openai
        }
        
        // Create provider config
        let providerConfig = LLMProviderConfig(
            providerType: providerType,
            apiKey: self.apiKey,
            baseURL: "https://\(configuration.host)",
            apiVersion: configuration.basePath.replacingOccurrences(of: "/", with: ""),
            proxyPath: nil,
            extraHeaders: configuration.customHeaders
        )
        
        // Create appropriate adapter
        let appState = AppState()
        self.appLLMClient = AppLLMClientFactory.createClient(for: providerType, appState: appState)
    }
    
    /// Initializes a new client with the given API key
    /// - Parameter apiKey: The API key to use for requests
    /// @available(*, deprecated, message: "Use AppLLMClientFactory.createClient instead")
    required init(apiKey: String) {
        self.apiKey = apiKey
        
        // Create client for OpenAI
        let appState = AppState()
        self.appLLMClient = AppLLMClientFactory.createClient(for: AIModels.Provider.openai, appState: appState)
    }
    
    /// Initializes with an existing AppLLMClientProtocol for direct wrapping
    /// - Parameter client: The AppLLMClientProtocol to wrap
    /// @available(*, deprecated, message: "Use AppLLMClientProtocol directly instead")
    init(client: AppLLMClientProtocol) {
        self.appLLMClient = client
        self.apiKey = "unknown" // API key is stored in the client already
    }
    
    /// Initializes with an existing AppLLMClientProtocol and known API key
    /// - Parameters:
    ///   - client: The AppLLMClientProtocol to wrap
    ///   - apiKey: The API key for protocol compatibility
    /// @available(*, deprecated, message: "Use AppLLMClientProtocol directly instead")
    init(client: AppLLMClientProtocol, apiKey: String) {
        self.appLLMClient = client
        self.apiKey = apiKey
    }
    
    // MARK: - Chat Completion API
    
    /// Sends a chat completion request using async/await
    /// - Parameters:
    ///   - messages: The conversation history
    ///   - model: The model to use for completion
    ///   - responseFormat: Optional response format (e.g., JSON mode)
    ///   - temperature: Controls randomness (0-1)
    /// - Returns: A completion with the model's response
    /// @available(*, deprecated, message: "Use AppLLMClientProtocol.executeQuery() instead")
    func sendChatCompletionAsync(
        messages: [ChatMessage],
        model: String,
        responseFormat: AIResponseFormat?,
        temperature: Double?
    ) async throws -> ChatCompletionResponse {
        // Convert legacy messages to AppLLMMessages using MessageConverter
        let appMessages = MessageConverter.appLLMMessagesFrom(chatMessages: messages)
        
        // Create query
        let query = AppLLMQuery(
            messages: appMessages,
            modelIdentifier: model,
            temperature: temperature
        )
        
        // Execute query
        let response = try await appLLMClient.executeQuery(query)
        
        // Extract response content
        let responseText: String
        switch response {
        case .text(let text):
            responseText = text
        case .structured(let data):
            responseText = String(data: data, encoding: .utf8) ?? ""
        }
        
        // Create and return ChatCompletionResponse
        return ChatCompletionResponse(
            content: responseText,
            model: model,
            id: UUID().uuidString
        )
    }
    
    // MARK: - Chat Completion with Structured Output
    
    /// Sends a chat completion request with structured output using async/await
    /// - Parameters:
    ///   - messages: The conversation history
    ///   - model: The model to use for completion
    ///   - temperature: Controls randomness (0-1)
    ///   - structuredOutputType: The type to use for structured output
    /// - Returns: A completion with the model's response
    /// @available(*, deprecated, message: "Use AppLLMClientProtocol.executeQuery() with responseType instead")
    func sendChatCompletionWithStructuredOutput<T: StructuredOutput>(
        messages: [ChatMessage],
        model: String,
        temperature: Double?,
        structuredOutputType: T.Type
    ) async throws -> T {
        // Convert legacy messages to AppLLMMessages using MessageConverter
        let appMessages = MessageConverter.appLLMMessagesFrom(chatMessages: messages)
        
        // Create query for structured output
        let query = AppLLMQuery(
            messages: appMessages,
            modelIdentifier: model,
            temperature: temperature,
            responseType: structuredOutputType
        )
        
        // Execute query
        let response = try await appLLMClient.executeQuery(query)
        
        // Process response
        switch response {
        case .structured(let data):
            // Decode structured data
            do {
                let decoder = JSONDecoder()
                return try decoder.decode(T.self, from: data)
            } catch {
                throw AppLLMError.decodingFailed(error)
            }
        case .text(let text):
            // Try to decode text as JSON
            if let data = text.data(using: .utf8) {
                do {
                    let decoder = JSONDecoder()
                    return try decoder.decode(T.self, from: data)
                } catch {
                    throw AppLLMError.decodingFailed(error)
                }
            } else {
                throw AppLLMError.unexpectedResponseFormat
            }
        }
    }
    
    // MARK: - Text-to-Speech API
    
    /// Sends a TTS (Text-to-Speech) request
    /// - Parameters:
    ///   - text: The text to convert to speech
    ///   - voice: The voice to use
    ///   - instructions: Voice instructions for TTS generation (optional)
    ///   - onComplete: Callback with audio data
    /// @available(*, deprecated, message: "Use AppLLMClientProtocol with TTSProvider instead")
    func sendTTSRequest(
        text: String,
        voice: String,
        instructions: String?,
        onComplete: @escaping (Result<Data, Error>) -> Void
    ) {
        // For now, TTS support is maintained through the legacy OpenAI client
        // Create a direct client for OpenAI TTS
        let openAIClient = SwiftOpenAIClient(apiKey: apiKey)
        
        // Forward the request
        openAIClient.sendTTSRequest(
            text: text,
            voice: voice,
            instructions: instructions,
            onComplete: onComplete
        )
    }
    
    /// Sends a streaming TTS (Text-to-Speech) request
    /// - Parameters:
    ///   - text: The text to convert to speech
    ///   - voice: The voice to use
    ///   - instructions: Voice instructions for TTS generation (optional)
    ///   - onChunk: Callback for each chunk of audio data
    ///   - onComplete: Callback when streaming is complete
    /// @available(*, deprecated, message: "Use AppLLMClientProtocol with TTSProvider instead")
    func sendTTSStreamingRequest(
        text: String,
        voice: String,
        instructions: String?,
        onChunk: @escaping (Result<Data, Error>) -> Void,
        onComplete: @escaping (Error?) -> Void
    ) {
        // For now, TTS support is maintained through the legacy OpenAI client
        // Create a direct client for OpenAI TTS
        let openAIClient = SwiftOpenAIClient(apiKey: apiKey)
        
        // Forward the request
        openAIClient.sendTTSStreamingRequest(
            text: text,
            voice: voice,
            instructions: instructions,
            onChunk: onChunk,
            onComplete: onComplete
        )
    }
}
