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
        
        // ENHANCED DEBUG: Log the actual configuration being used
        Logger.debug("🔄 Creating API client for provider: \(config.providerType)")
        Logger.debug("🔧 Configuration: baseURL=\(config.baseURL ?? "nil"), apiVersion=\(config.apiVersion ?? "nil")")
        
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
                Logger.debug("📱 Using Gemini endpoints: \(baseURL)")
            case AIModels.Provider.grok:
                if config.apiKey.hasPrefix("xai-") {
                    baseURL = config.baseURL ?? "https://api.x.ai"
                } else {
                    baseURL = config.baseURL ?? "https://api.groq.com"
                }
                apiVersion = config.apiVersion ?? "v1"
                Logger.debug("🚀 Using Grok endpoints: \(baseURL)")
            case AIModels.Provider.openai:
                baseURL = config.baseURL ?? "https://api.openai.com"
                apiVersion = config.apiVersion ?? "v1"
                Logger.debug("🤖 Using OpenAI endpoints: \(baseURL)")
            default:
                baseURL = config.baseURL ?? "https://api.openai.com"
                apiVersion = config.apiVersion ?? "v1"
                Logger.debug("❓ Using default OpenAI endpoints for unknown provider \(config.providerType): \(baseURL)")
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
            
            Logger.debug("✅ Service created with baseURL: \(baseURL)")
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
        Logger.debug("📥 Preparing chat parameters with \(query.messages.count) messages")
        if query.messages.isEmpty {
            Logger.error("⚠️ Query messages array is empty!")
        }
        let swiftMessages = MessageConverter.swiftOpenAIMessagesFrom(appMessages: query.messages)
        Logger.debug("🔄 Converted to \(swiftMessages.count) SwiftOpenAI messages")
        
        // Use the config model if specified, otherwise use the query model
        let modelId = config.model ?? query.modelIdentifier
        
        // CRITICAL FIX: Validate model and provider compatibility
        validateModelProviderCompatibility(modelId: modelId, providerType: config.providerType)
        
        // Create model from identifier
        let model = SwiftOpenAI.Model.from(modelId)
        
        // Log the actual model being used for debugging
        Logger.debug("🔄 Using model: \(modelId) for \(config.providerType) request")
        
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
        
        // For reasoning models, apply appropriate reasoning effort parameters
        // Different models support different reasoning parameters
        let idLower = query.modelIdentifier.lowercased()
        
        // Only apply reasoning_effort to models that support it
        // This is a critical fix to prevent 400 errors
        if idLower.contains("o3") {
            // OpenAI 'o3' models support reasoning_effort
            parameters.reasoningEffort = "medium"
        } else if idLower.contains("grok-3-mini") {
            // Grok-3-mini supports reasoning with high effort
            parameters.reasoningEffort = "high"
        } else if idLower.contains("gemini") {
            // Gemini models (especially 2.5 and newer) support reasoning
            parameters.reasoningEffort = "medium"
        }
        // Do NOT apply reasoning_effort to:
        // - o4 models (they don't support it yet)
        // - gpt-4.1, gpt-4o models
        // - claude models
        
        // Special treatment for structured outputs with newer models
        if query.desiredResponseType != nil && (idLower.contains("gpt-4") || idLower.contains("o4") || idLower.contains("o1")) {
            // Enhance system message to enforce JSON output format if possible
            if let firstMessage = swiftMessages.first, 
               let roleString = String(describing: firstMessage.role).components(separatedBy: ".").last,
               roleString == "system" {
                let originalContent: String
                if case let .text(text) = firstMessage.content {
                    originalContent = text
                } else {
                    originalContent = ""
                }
                
                // Type name for better model guidance
                let typeName = String(describing: query.desiredResponseType).components(separatedBy: ".").last ?? "Object"
                
                let enhancedContent = originalContent + "\n\nIMPORTANT: Your response MUST be valid JSON conforming to the \(typeName) schema. "
                    + "Output ONLY the JSON object with no additional text, comments, or explanation."
                
                // Replace first message with enhanced content
                var enhancedMessages = swiftMessages
                enhancedMessages[0] = ChatCompletionParameters.Message(
                    role: .system,
                    content: .text(enhancedContent)
                )
                
                parameters.messages = enhancedMessages
            }
        }
        
        return parameters
    }
    
    /// Validates that the model and provider are compatible
    /// - Parameters:
    ///   - modelId: The model identifier
    ///   - providerType: The provider type
    private func validateModelProviderCompatibility(modelId: String, providerType: String) {
        let modelLower = modelId.lowercased()
        var expectedProvider = ""
        
        // Check model name to determine expected provider
        if modelLower.contains("claude") {
            expectedProvider = AIModels.Provider.claude
        } else if modelLower.contains("gpt") || modelLower.contains("o3") || modelLower.contains("o4") {
            expectedProvider = AIModels.Provider.openai
        } else if modelLower.contains("grok") {
            expectedProvider = AIModels.Provider.grok
        } else if modelLower.contains("gemini") {
            expectedProvider = AIModels.Provider.gemini
        }
        
        // Check for mismatches
        if !expectedProvider.isEmpty && expectedProvider != providerType {
            Logger.warning("⚠️ Model-provider mismatch detected: \(modelId) is being used with \(providerType) provider, but should be used with \(expectedProvider)")
        }
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
