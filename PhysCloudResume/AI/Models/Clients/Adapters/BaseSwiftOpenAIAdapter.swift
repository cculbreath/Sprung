//
//  BaseSwiftOpenAIAdapter.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 5/20/25.
//

import Foundation
import SwiftOpenAI

/// Base class for SwiftOpenAI-based adapters
/// Handles common initialization and message conversion logic
class BaseSwiftOpenAIAdapter: AppLLMClientProtocol {
    /// The SwiftOpenAI service instance
    let swiftService: OpenAIService
    
    /// The provider configuration
    let config: LLMProviderConfig
    
    /// Initializes the adapter with a provider configuration
    /// - Parameter config: The LLM provider configuration
    init(config: LLMProviderConfig) {
        self.config = config
        
        // Configure SwiftOpenAI service
        let urlConfig = URLSessionConfiguration.default
        urlConfig.timeoutIntervalForRequest = 900.0 // 15 minutes for reasoning models
        
        // Configure the service based on provider settings
        if config.providerType == AIModels.Provider.claude {
            // Special handling for Claude API
            Logger.debug("👤 Creating Claude-specific API client")
            
            // Setup extra headers with anthropic-version
            var anthropicHeaders: [String: String] = config.extraHeaders ?? [:]
            anthropicHeaders["anthropic-version"] = "2023-06-01"
            
            // Create the service using the Anthropic API key via standard Authorization header
            swiftService = OpenAIServiceFactory.service(
                apiKey: config.apiKey,
                overrideBaseURL: config.baseURL ?? "https://api.anthropic.com", // Provide a default if nil
                configuration: urlConfig,
                proxyPath: config.proxyPath,
                overrideVersion: config.apiVersion ?? "v1", // Provide a default if nil
                extraHeaders: anthropicHeaders
            )
        } else {
            // Standard configuration for OpenAI-compatible APIs
            Logger.debug("🔄 Creating API client for provider: \(config.providerType)")
            
            // Determine the default base URL based on provider
            let baseURL: String
            let apiVersion: String
            
            switch config.providerType {
            case AIModels.Provider.gemini:
                baseURL = config.baseURL ?? "https://generativelanguage.googleapis.com"
                apiVersion = config.apiVersion ?? "v1beta"
            case AIModels.Provider.grok:
                if config.apiKey.hasPrefix("xai-") {
                    baseURL = config.baseURL ?? "https://api.x.ai"
                } else {
                    baseURL = config.baseURL ?? "https://api.groq.com"
                }
                apiVersion = config.apiVersion ?? "v1"
            case AIModels.Provider.openai:
                baseURL = config.baseURL ?? "https://api.openai.com"
                apiVersion = config.apiVersion ?? "v1"
            default:
                baseURL = config.baseURL ?? "https://api.openai.com"
                apiVersion = config.apiVersion ?? "v1"
            }
            
            // Create the service with proper handling of parameters
            swiftService = OpenAIServiceFactory.service(
                apiKey: config.apiKey,
                overrideBaseURL: baseURL,
                configuration: urlConfig,
                proxyPath: config.proxyPath,
                overrideVersion: apiVersion,
                extraHeaders: config.extraHeaders
            )
        }
    }
    
    /// Default implementation of executeQuery - to be overridden by subclasses
    /// - Parameter query: The query to execute
    /// - Returns: The query response
    func executeQuery(_ query: AppLLMQuery) async throws -> AppLLMResponse {
        // Base class implementation, should be overridden by subclasses
        throw AppLLMError.clientError("BaseSwiftOpenAIAdapter.executeQuery must be overridden by subclasses")
    }
    
    // MARK: - Helper methods for subclasses
    
    /// Prepare chat parameters for SwiftOpenAI request
    /// - Parameter query: The AppLLMQuery to convert
    /// - Returns: ChatCompletionParameters for SwiftOpenAI
    func prepareChatParameters(for query: AppLLMQuery) -> ChatCompletionParameters {
        // Convert messages using the centralized MessageConverter
        let swiftMessages = MessageConverter.swiftOpenAIMessagesFrom(appMessages: query.messages)
        
        // Create model from identifier
        let model = SwiftOpenAI.Model.from(query.modelIdentifier)
        
        // Get response format using the schema builder
        let swiftResponseFormat = LLMSchemaBuilder.createResponseFormat(
            for: query.desiredResponseType,
            jsonSchema: query.jsonSchema
        )
        
        // Build chat completion parameters
        var parameters = ChatCompletionParameters(
            messages: swiftMessages,
            model: model,
            responseFormat: swiftResponseFormat,
            temperature: query.temperature
        )
        
        // For reasoning models (o-series models), constrain reasoning effort to medium
        let idLower = query.modelIdentifier.lowercased()
        if idLower.contains("gpt-4o") || idLower.contains("gpt-4-turbo") {
            parameters.reasoningEffort = "medium"
        }
        
        return parameters
    }
    
    /// Process the API error and convert to AppLLMError
    /// - Parameter error: The API error
    /// - Returns: An AppLLMError
    func processAPIError(_ error: Error) -> AppLLMError {
        if let apiError = error as? SwiftOpenAI.APIError {
            switch apiError {
            case .responseUnsuccessful(let description, let statusCode):
                Logger.error("API error (status code \(statusCode)): \(description)")
                return AppLLMError.clientError("API error (status code \(statusCode)): \(description)")
            default:
                Logger.error("API error: \(apiError.localizedDescription)")
                return AppLLMError.clientError("API error: \(apiError.localizedDescription)")
            }
        } else {
            Logger.error("API error: \(error.localizedDescription)")
            return AppLLMError.clientError("API error: \(error.localizedDescription)")
        }
    }
}
