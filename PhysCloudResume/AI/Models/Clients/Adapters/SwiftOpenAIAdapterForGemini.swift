//
//  SwiftOpenAIAdapterForGemini.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 5/20/25.
//

import Foundation
import SwiftOpenAI

/// Gemini-specific adapter for SwiftOpenAI
class SwiftOpenAIAdapterForGemini: BaseSwiftOpenAIAdapter {
    /// The app state that contains user settings and preferences
    private weak var appState: AppState?
    
    /// Initializes the adapter with Gemini configuration and app state
    /// - Parameters:
    ///   - config: The provider configuration
    ///   - appState: The application state
    init(config: LLMProviderConfig, appState: AppState) {
        self.appState = appState
        super.init(config: config)
        
        // Log Gemini configuration for debugging
        Logger.debug("🌟 Gemini adapter configured with:")
        Logger.debug("  - Base URL: \(config.baseURL ?? "nil")")
        Logger.debug("  - API Version: \(config.apiVersion ?? "nil")")
        Logger.debug("  - Proxy Path: \(config.proxyPath ?? "nil")")
    }
    
    /// Executes a query against the Gemini API using SwiftOpenAI's OpenAI-compatible endpoint
    /// - Parameter query: The query to execute
    /// - Returns: The response from the Gemini API
    override func executeQuery(_ query: AppLLMQuery) async throws -> AppLLMResponse {
        // Convert AppLLMMessages to SwiftOpenAI Messages
        let swiftMessages = MessageConverter.swiftOpenAIMessagesFrom(appMessages: query.messages)
        
        // Important: For Gemini, we need to ensure the model string is correctly formatted
        // Gemini's OpenAI-compatible API expects model names prefixed with "models/"
        let modelString = query.modelIdentifier
        let fullModelString = modelString.hasPrefix("models/") ? modelString : "models/\(modelString)"
        let model = SwiftOpenAI.Model.custom(fullModelString)
        
        // Handle structured JSON output if desired
        var swiftResponseFormat: SwiftOpenAI.ResponseFormat?
        if query.desiredResponseType != nil {
            // Gemini's OpenAI-compatible API supports the JSON object format
            swiftResponseFormat = .jsonObject
            
            // Log that we're using JSON mode
            Logger.debug("🌟 Gemini adapter using JSON mode for structured output")
        }
        
        // Build chat completion parameters
        let parameters = ChatCompletionParameters(
            messages: swiftMessages,
            model: model,
            responseFormat: swiftResponseFormat,
            temperature: query.temperature
        )
        
        do {
            // Execute the chat request with debug logging
            Logger.debug("🌟 Sending request to Gemini API with model: \(fullModelString)")
            let result = try await swiftService.startChat(parameters: parameters)
            
            // Process the result
            guard let content = result.choices?.first?.message?.content else {
                Logger.error("🌟 Gemini API returned unexpected response format (no content)")
                throw AppLLMError.unexpectedResponseFormat
            }
            
            Logger.debug("🌟 Gemini API request successful")
            
            // Check if we're expecting a structured response
            if query.desiredResponseType != nil {
                // Convert the content string to Data for structured decoding
                guard let contentData = content.data(using: String.Encoding.utf8) else {
                    throw AppLLMError.unexpectedResponseFormat
                }
                return .structured(contentData)
            } else {
                // Return text response
                return .text(content)
            }
        } catch {
            Logger.error("🌟 Gemini API error: \(error.localizedDescription)")
            
            // Provide more detailed error for debugging
            if let apiError = error as? SwiftOpenAI.APIError {
                switch apiError {
                case .responseUnsuccessful(let description, let statusCode):
                    Logger.error("🌟 Gemini API HTTP \(statusCode): \(description)")
                    
                    // Special handling for 400 errors to help diagnose the issue
                    if statusCode == 400 {
                        throw AppLLMError.clientError("Gemini API HTTP 400: \(description). This may be due to incorrect model format or unsupported features.")
                    }
                    
                    throw AppLLMError.clientError("Gemini API HTTP \(statusCode): \(description)")
                    
                case .jsonDecodingFailure(let description):
                    Logger.error("🌟 Gemini API JSON decoding error: \(description)")
                    throw AppLLMError.clientError("Gemini API response parsing error: \(description)")
                    
                default:
                    throw AppLLMError.clientError("Gemini API error: \(apiError.displayDescription)")
                }
            } else {
                throw AppLLMError.clientError("Gemini API error: \(error.localizedDescription)")
            }
        }
    }
}
