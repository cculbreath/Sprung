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
        
        var swiftMessages = MessageConverter.swiftOpenAIMessagesFrom(appMessages: query.messages)
        Logger.debug("🔄 Converted to \(swiftMessages.count) SwiftOpenAI messages")
        
        // Use the config model if specified, otherwise use the query model
        let modelId = config.model ?? query.modelIdentifier
        
        // CRITICAL FIX: Validate model and provider compatibility
        validateModelProviderCompatibility(modelId: modelId, providerType: config.providerType)
        
        // Special handling for o1 models which don't support system messages
        let isO1Model = isReasoningModel(modelId)
        if isO1Model {
            Logger.debug("🧠 Detected o1 reasoning model: \(modelId) - applying special handling")
            swiftMessages = handleO1ModelMessages(swiftMessages, desiredResponseType: query.desiredResponseType)
        }
        
        // Create model from identifier
        let model = SwiftOpenAI.Model.from(modelId)
        
        // Log the actual model being used for debugging
        Logger.debug("🔄 Using model: \(modelId) for \(config.providerType) request")
        
        // Get response format using the schema builder
        let swiftResponseFormat = LLMSchemaBuilder.createResponseFormat(
            for: query.desiredResponseType,
            jsonSchema: query.jsonSchema
        )
        
        // Build chat completion parameters with conditional temperature for o1 models
        let temperatureValue = isO1Model ? nil : query.temperature
        if isO1Model && query.temperature != nil {
            Logger.debug("🧠 Excluding temperature parameter for o1 model (not supported)")
        }
        
        var parameters = ChatCompletionParameters(
            messages: swiftMessages,
            model: model,
            responseFormat: swiftResponseFormat,
            temperature: temperatureValue
        )
        
        
        // For reasoning models, apply appropriate reasoning effort parameters
        // Different models support different reasoning parameters
        let idLower = query.modelIdentifier.lowercased()
        
        // Only apply reasoning_effort to models that support it
        // This is a critical fix to prevent 400 errors
        if !isO1Model && idLower.contains("o3") {
            // OpenAI 'o3' models support reasoning_effort
            parameters.reasoningEffort = "medium"
        } else if idLower.contains("grok-3-mini") {
            // Grok-3-mini supports reasoning with high effort
            parameters.reasoningEffort = "high"
        } else if idLower.contains("gemini") && !idLower.contains("pro") {
            // Gemini models support reasoning_effort, but NOT the "pro" variants
            parameters.reasoningEffort = "medium"
        }
        // Do NOT apply reasoning_effort to:
        // - o1 and o1-mini models (they handle reasoning automatically)
        // - o4 models (they don't support it yet)
        // - gpt-4.1, gpt-4o models
        // - claude models
        // - gemini "pro" models (they don't support this parameter)
        
        // Special treatment for structured outputs with newer models (but not o1 models which handle this differently)
        if !isO1Model && query.desiredResponseType != nil && (idLower.contains("gpt-4") || idLower.contains("o4")) {
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
    
    /// Determines if a model is an o1-series reasoning model that has special requirements
    /// - Parameter modelId: The model identifier to check
    /// - Returns: True if this is an o1 or o1-mini model
    private func isReasoningModel(_ modelId: String) -> Bool {
        let modelLower = modelId.lowercased()
        return modelLower.contains("o1") && !modelLower.contains("o3") && !modelLower.contains("o4")
    }
    
    /// Handles message conversion for o1 models which don't support system messages
    /// - Parameters:
    ///   - messages: Original SwiftOpenAI messages
    ///   - desiredResponseType: The desired response type for structured output (if any)
    /// - Returns: Modified messages with system content moved to user messages
    private func handleO1ModelMessages(_ messages: [ChatCompletionParameters.Message], desiredResponseType: Any.Type?) -> [ChatCompletionParameters.Message] {
        guard !messages.isEmpty else { return messages }
        
        var modifiedMessages: [ChatCompletionParameters.Message] = []
        var systemContent: String = ""
        
        // Extract all system messages and collect their content
        for message in messages {
            let roleString = String(describing: message.role)
            if roleString.hasSuffix(".system") {
                // Extract text content from system message
                if case let .text(text) = message.content {
                    if !systemContent.isEmpty {
                        systemContent += "\n\n"
                    }
                    systemContent += text
                }
            } else {
                modifiedMessages.append(message)
            }
        }
        
        // If we found system content, prepend it to the first user message
        if !systemContent.isEmpty && !modifiedMessages.isEmpty {
            // Find the first user message
            for (index, message) in modifiedMessages.enumerated() {
                let roleString = String(describing: message.role)
                if roleString.hasSuffix(".user") {
                    // Extract existing user content
                    var existingContent = ""
                    if case let .text(text) = message.content {
                        existingContent = text
                    } else if case let .contentArray(contents) = message.content {
                        // For multimodal messages, extract text parts
                        let textParts = contents.compactMap { content in
                            if case let .text(text) = content {
                                return text
                            }
                            return nil
                        }
                        existingContent = textParts.joined(separator: "\n")
                    }
                    
                    // Create new content with system instructions prepended
                    var newContent = systemContent
                    
                    // Add structured output instructions if needed
                    if let responseType = desiredResponseType {
                        let typeName = String(describing: responseType).components(separatedBy: ".").last ?? "Object"
                        let structuredInstructions = "\n\nIMPORTANT: Your response MUST be valid JSON conforming to the \(typeName) schema. Output ONLY the JSON object with no additional text, comments, or explanation."
                        newContent += structuredInstructions
                    }
                    
                    // Add existing user content if any
                    if !existingContent.isEmpty {
                        newContent += "\n\n" + existingContent
                    }
                    
                    // Create new message with combined content
                    modifiedMessages[index] = ChatCompletionParameters.Message(
                        role: .user,
                        content: .text(newContent)
                    )
                    
                    Logger.debug("🔄 Moved system message content to first user message for o1 model")
                    break
                }
            }
            
            // If no user message was found, create one with the system content
            if modifiedMessages.allSatisfy({ message in
                let roleString = String(describing: message.role)
                return !roleString.hasSuffix(".user")
            }) {
                var userContent = systemContent
                
                // Add structured output instructions if needed
                if let responseType = desiredResponseType {
                    let typeName = String(describing: responseType).components(separatedBy: ".").last ?? "Object"
                    let structuredInstructions = "\n\nIMPORTANT: Your response MUST be valid JSON conforming to the \(typeName) schema. Output ONLY the JSON object with no additional text, comments, or explanation."
                    userContent += structuredInstructions
                }
                
                let userMessage = ChatCompletionParameters.Message(
                    role: .user,
                    content: .text(userContent)
                )
                modifiedMessages.insert(userMessage, at: 0)
                Logger.debug("🔄 Created new user message with system content for o1 model")
            }
        }
        
        // If no system content but we need structured output, add instructions to first user message
        if systemContent.isEmpty && desiredResponseType != nil && !modifiedMessages.isEmpty {
            for (index, message) in modifiedMessages.enumerated() {
                let roleString = String(describing: message.role)
                if roleString.hasSuffix(".user") {
                    // Extract existing user content
                    var existingContent = ""
                    if case let .text(text) = message.content {
                        existingContent = text
                    }
                    
                    // Add structured output instructions
                    let typeName = String(describing: desiredResponseType!).components(separatedBy: ".").last ?? "Object"
                    let structuredInstructions = "IMPORTANT: Your response MUST be valid JSON conforming to the \(typeName) schema. Output ONLY the JSON object with no additional text, comments, or explanation."
                    
                    let newContent = structuredInstructions + (existingContent.isEmpty ? "" : "\n\n" + existingContent)
                    
                    modifiedMessages[index] = ChatCompletionParameters.Message(
                        role: .user,
                        content: .text(newContent)
                    )
                    
                    Logger.debug("🔄 Added structured output instructions to first user message for o1 model")
                    break
                }
            }
        }
        
        return modifiedMessages
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
        } else if modelLower.contains("gpt") || modelLower.contains("o1") || modelLower.contains("o3") || modelLower.contains("o4") {
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
                
                // Check for rate limit error
                if statusCode == 429 {
                    // Try to parse retry-after header if available
                    // For now, we'll use a default retry time
                    return AppLLMError.rateLimited(retryAfter: 60) // Default to 60 seconds
                }
                
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
