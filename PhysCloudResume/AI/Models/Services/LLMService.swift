//
//  LLMService.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 6/4/25.
//

import Foundation
import SwiftUI
import SwiftData
import SwiftOpenAI

// MARK: - LLM Error Types

enum LLMError: LocalizedError {
    case clientError(String)
    case decodingFailed(Error)
    case unexpectedResponseFormat
    case rateLimited(retryAfter: TimeInterval?)
    case timeout
    
    var errorDescription: String? {
        switch self {
        case .clientError(let message):
            return message
        case .decodingFailed(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .unexpectedResponseFormat:
            return "Unexpected response format from LLM"
        case .rateLimited(let retryAfter):
            if let retryAfter = retryAfter {
                return "Rate limited. Retry after \(retryAfter) seconds"
            } else {
                return "Rate limited"
            }
        case .timeout:
            return "Request timed out"
        }
    }
}

/// Unified LLM service that provides a clean abstraction layer for all LLM operations
/// Supports text-only, multimodal, structured output, and conversational requests
/// Uses OpenRouter as the provider but designed for easy migration to other providers
@MainActor
@Observable
class LLMService {
    static let shared = LLMService()
    
    // Dependencies
    private var appState: AppState?
    private var openRouterClient: OpenAIService?
    private var conversationManager: ConversationManager?
    
    // Request management
    private var currentRequestIDs: Set<UUID> = []
    
    // Configuration
    private let defaultTemperature: Double = 1.0
    private let defaultMaxRetries: Int = 3
    private let baseRetryDelay: TimeInterval = 1.0
    
    private init() {}
    
    // MARK: - Initialization
    
    /// Initialize the service with AppState and conversation manager
    func initialize(appState: AppState, modelContext: ModelContext? = nil) {
        self.appState = appState
        self.conversationManager = ConversationManager(modelContext: modelContext)
        
        // Configure client with current API key
        reconfigureClient()
        
        Logger.debug("🔄 LLMService initialized with OpenRouter client")
    }
    
    /// Reconfigure the OpenRouter client with the current API key from UserDefaults
    func reconfigureClient() {
        let apiKey = UserDefaults.standard.string(forKey: "openRouterApiKey") ?? ""
        Logger.debug("🔑 LLMService API key length: \(apiKey.count) chars")
        if !apiKey.isEmpty {
            // Log first/last 4 chars for debugging (same as SettingsView does)
            let maskedKey = apiKey.count > 8 ? 
                "\(apiKey.prefix(4))...\(apiKey.suffix(4))" : 
                "***masked***"
            Logger.debug("🔑 Using API key: \(maskedKey)")
            
            Logger.debug("🔧 Creating OpenRouter client with baseURL: https://openrouter.ai")
            self.openRouterClient = OpenAIServiceFactory.service(
                apiKey: apiKey,
                overrideBaseURL: "https://openrouter.ai",
                proxyPath: "api",
                overrideVersion: "v1",
                extraHeaders: [
                    "HTTP-Referer": "https://github.com/cculbreath/PhysCloudResume",
                    "X-Title": "Physics Cloud Resume"
                ],
                debugEnabled: true
            )
            Logger.debug("🔄 LLMService reconfigured OpenRouter client with key")
            Logger.debug("🌐 Expected URL: https://openrouter.ai/api/v1/chat/completions")
            
            // Debug the actual client configuration
            if let client = self.openRouterClient {
                Logger.debug("✅ OpenRouter client created: \(type(of: client))")
            }
        } else {
            self.openRouterClient = nil
            Logger.debug("🔴 No OpenRouter API key available, client cleared")
        }
    }
    
    private func ensureInitialized() throws {
        guard appState != nil else {
            throw LLMError.clientError("LLMService not initialized - call initialize() first")
        }
        
        // Ensure client is configured with current API key
        if openRouterClient == nil {
            reconfigureClient()
        }
        
        guard openRouterClient != nil else {
            throw LLMError.clientError("OpenRouter API key not configured")
        }
        
        if conversationManager == nil {
            conversationManager = ConversationManager(modelContext: nil)
        }
    }
    
    // MARK: - Core Operations
    
    /// Simple text-only request
    /// - Parameters:
    ///   - prompt: The text prompt to send
    ///   - modelId: The model identifier to use
    ///   - temperature: Optional temperature setting (defaults to 1.0)
    /// - Returns: The text response from the model
    func execute(
        prompt: String,
        modelId: String,
        temperature: Double? = nil
    ) async throws -> String {
        try ensureInitialized()
        
        let requestId = UUID()
        currentRequestIDs.insert(requestId)
        defer { currentRequestIDs.remove(requestId) }
        
        // Validate model
        try validateModel(modelId: modelId, for: [])
        
        // Create message
        let message = LLMMessage.text(role: .user, content: prompt)
        
        // Create parameters
        let parameters = ChatCompletionParameters(
            messages: [message],
            model: .custom(modelId),
            temperature: temperature ?? defaultTemperature
        )
        
        // Execute with retry logic
        return try await executeWithRetry(parameters: parameters, requestId: requestId) { response in
            guard let content = response.choices?.first?.message?.content else {
                throw LLMError.unexpectedResponseFormat
            }
            return content
        }
    }
    
    /// Request with image inputs
    /// - Parameters:
    ///   - prompt: The text prompt
    ///   - modelId: The model identifier (must support vision)
    ///   - images: Array of image data to include
    ///   - temperature: Optional temperature setting
    /// - Returns: The text response from the model
    func executeWithImages(
        prompt: String,
        modelId: String,
        images: [Data],
        temperature: Double? = nil
    ) async throws -> String {
        try ensureInitialized()
        
        let requestId = UUID()
        currentRequestIDs.insert(requestId)
        defer { currentRequestIDs.remove(requestId) }
        
        // Validate model supports vision
        try validateModel(modelId: modelId, for: [.vision])
        
        // Build content parts
        var contentParts: [ChatCompletionParameters.Message.ContentType.MessageContent] = [
            .text(prompt)
        ]
        
        // Add images
        for imageData in images {
            let base64Image = imageData.base64EncodedString()
            let imageURL = URL(string: "data:image/png;base64,\(base64Image)")!
            let imageDetail = ChatCompletionParameters.Message.ContentType.MessageContent.ImageDetail(url: imageURL)
            contentParts.append(.imageUrl(imageDetail))
        }
        
        // Create message
        let message = ChatCompletionParameters.Message(
            role: .user,
            content: .contentArray(contentParts)
        )
        
        // Create parameters
        let parameters = ChatCompletionParameters(
            messages: [message],
            model: .custom(modelId),
            temperature: temperature ?? defaultTemperature
        )
        
        // Execute with retry logic
        return try await executeWithRetry(parameters: parameters, requestId: requestId) { response in
            guard let content = response.choices?.first?.message?.content else {
                throw LLMError.unexpectedResponseFormat
            }
            return content
        }
    }
    
    /// Request with structured JSON output
    /// - Parameters:
    ///   - prompt: The text prompt
    ///   - modelId: The model identifier (should support structured output)
    ///   - responseType: The expected response type
    ///   - temperature: Optional temperature setting
    /// - Returns: The parsed structured response
    func executeStructured<T: Codable>(
        prompt: String,
        modelId: String,
        responseType: T.Type,
        temperature: Double? = nil
    ) async throws -> T {
        try ensureInitialized()
        
        let requestId = UUID()
        currentRequestIDs.insert(requestId)
        defer { currentRequestIDs.remove(requestId) }
        
        // Validate model (prefer structured output capability but don't require)
        try validateModel(modelId: modelId, for: [])
        
        // Create message
        let message = LLMMessage.text(role: .user, content: prompt)
        
        // Create parameters with response format
        let parameters = ChatCompletionParameters(
            messages: [message],
            model: .custom(modelId),
            responseFormat: .jsonObject,
            temperature: temperature ?? defaultTemperature
        )
        
        // Execute with retry logic
        return try await executeWithRetry(parameters: parameters, requestId: requestId) { response in
            try self.parseStructuredResponse(response, as: responseType)
        }
    }
    
    /// Request with both image inputs and structured output
    /// - Parameters:
    ///   - prompt: The text prompt
    ///   - modelId: The model identifier (must support vision, should support structured output)
    ///   - images: Array of image data to include
    ///   - responseType: The expected response type
    ///   - temperature: Optional temperature setting
    /// - Returns: The parsed structured response
    func executeStructuredWithImages<T: Codable>(
        prompt: String,
        modelId: String,
        images: [Data],
        responseType: T.Type,
        temperature: Double? = nil
    ) async throws -> T {
        try ensureInitialized()
        
        let requestId = UUID()
        currentRequestIDs.insert(requestId)
        defer { currentRequestIDs.remove(requestId) }
        
        // Validate model supports vision
        try validateModel(modelId: modelId, for: [.vision])
        
        // Build content parts
        var contentParts: [ChatCompletionParameters.Message.ContentType.MessageContent] = [
            .text(prompt)
        ]
        
        // Add images
        for imageData in images {
            let base64Image = imageData.base64EncodedString()
            let imageURL = URL(string: "data:image/png;base64,\(base64Image)")!
            let imageDetail = ChatCompletionParameters.Message.ContentType.MessageContent.ImageDetail(url: imageURL)
            contentParts.append(.imageUrl(imageDetail))
        }
        
        // Create message
        let message = ChatCompletionParameters.Message(
            role: .user,
            content: .contentArray(contentParts)
        )
        
        // Create parameters with response format
        let parameters = ChatCompletionParameters(
            messages: [message],
            model: .custom(modelId),
            responseFormat: .jsonObject,
            temperature: temperature ?? defaultTemperature
        )
        
        // Execute with retry logic
        return try await executeWithRetry(parameters: parameters, requestId: requestId) { response in
            try self.parseStructuredResponse(response, as: responseType)
        }
    }
    
    // MARK: - Conversation Operations
    
    /// Start a new conversation
    /// - Parameters:
    ///   - systemPrompt: Optional system prompt to initialize the conversation
    ///   - userMessage: The first user message
    ///   - modelId: The model identifier to use
    ///   - temperature: Optional temperature setting
    /// - Returns: Tuple containing the conversation ID and assistant response
    func startConversation(
        systemPrompt: String? = nil,
        userMessage: String,
        modelId: String,
        temperature: Double? = nil
    ) async throws -> (conversationId: UUID, response: String) {
        try ensureInitialized()
        
        guard let conversationManager = conversationManager else {
            throw LLMError.clientError("Conversation manager not available")
        }
        
        let requestId = UUID()
        currentRequestIDs.insert(requestId)
        defer { currentRequestIDs.remove(requestId) }
        
        // Validate model
        try validateModel(modelId: modelId, for: [])
        
        // Create conversation
        let conversationId = UUID()
        
        // Build messages
        var messages: [LLMMessage] = []
        
        // Add system prompt if provided
        if let systemPrompt = systemPrompt {
            messages.append(LLMMessage.text(role: .system, content: systemPrompt))
        }
        
        // Add user message
        messages.append(LLMMessage.text(role: .user, content: userMessage))
        
        // Create parameters
        let parameters = ChatCompletionParameters(
            messages: messages,
            model: .custom(modelId),
            temperature: temperature ?? defaultTemperature
        )
        
        // Execute request
        let responseText = try await executeWithRetry(parameters: parameters, requestId: requestId) { response in
            guard let content = response.choices?.first?.message?.content else {
                throw LLMError.unexpectedResponseFormat
            }
            return content
        }
        
        // Add assistant response to messages
        messages.append(LLMMessage.text(role: .assistant, content: responseText))
        
        // Store conversation
        conversationManager.storeConversation(id: conversationId, messages: messages)
        
        return (conversationId: conversationId, response: responseText)
    }
    
    /// Continue an existing conversation
    /// - Parameters:
    ///   - userMessage: The user's message
    ///   - modelId: The model identifier to use
    ///   - conversationId: The conversation ID to continue
    ///   - images: Optional images to include
    ///   - temperature: Optional temperature setting
    /// - Returns: The assistant's response
    func continueConversation(
        userMessage: String,
        modelId: String,
        conversationId: UUID,
        images: [Data] = [],
        temperature: Double? = nil
    ) async throws -> String {
        try ensureInitialized()
        
        guard let conversationManager = conversationManager else {
            throw LLMError.clientError("Conversation manager not available")
        }
        
        let requestId = UUID()
        currentRequestIDs.insert(requestId)
        defer { currentRequestIDs.remove(requestId) }
        
        // Validate model (require vision if images provided)
        let requiredCapabilities: [ModelCapability] = images.isEmpty ? [] : [.vision]
        try validateModel(modelId: modelId, for: requiredCapabilities)
        
        // Get conversation history
        var messages = conversationManager.getConversation(id: conversationId)
        
        // Build user message content
        if images.isEmpty {
            // Simple text message
            messages.append(LLMMessage.text(role: .user, content: userMessage))
        } else {
            // Message with images
            var contentParts: [ChatCompletionParameters.Message.ContentType.MessageContent] = [
                .text(userMessage)
            ]
            
            // Add images
            for imageData in images {
                let base64Image = imageData.base64EncodedString()
                let imageURL = URL(string: "data:image/png;base64,\(base64Image)")!
                let imageDetail = ChatCompletionParameters.Message.ContentType.MessageContent.ImageDetail(url: imageURL)
                contentParts.append(.imageUrl(imageDetail))
            }
            
            let userMessage = ChatCompletionParameters.Message(
                role: .user,
                content: .contentArray(contentParts)
            )
            messages.append(userMessage)
        }
        
        // Create parameters
        let parameters = ChatCompletionParameters(
            messages: messages,
            model: .custom(modelId),
            temperature: temperature ?? defaultTemperature
        )
        
        // Execute request
        let responseText = try await executeWithRetry(parameters: parameters, requestId: requestId) { response in
            guard let content = response.choices?.first?.message?.content else {
                throw LLMError.unexpectedResponseFormat
            }
            return content
        }
        
        // Add assistant response
        messages.append(LLMMessage.text(role: .assistant, content: responseText))
        
        // Update conversation
        conversationManager.storeConversation(id: conversationId, messages: messages)
        
        return responseText
    }
    
    /// Continue conversation with structured output
    /// - Parameters:
    ///   - userMessage: The user's message
    ///   - modelId: The model identifier to use
    ///   - conversationId: The conversation ID to continue
    ///   - responseType: The expected response type
    ///   - images: Optional images to include
    ///   - temperature: Optional temperature setting
    /// - Returns: The parsed structured response
    func continueConversationStructured<T: Codable>(
        userMessage: String,
        modelId: String,
        conversationId: UUID,
        responseType: T.Type,
        images: [Data] = [],
        temperature: Double? = nil
    ) async throws -> T {
        try ensureInitialized()
        
        guard let conversationManager = conversationManager else {
            throw LLMError.clientError("Conversation manager not available")
        }
        
        let requestId = UUID()
        currentRequestIDs.insert(requestId)
        defer { currentRequestIDs.remove(requestId) }
        
        // Validate model (require vision if images provided)
        let requiredCapabilities: [ModelCapability] = images.isEmpty ? [] : [.vision]
        try validateModel(modelId: modelId, for: requiredCapabilities)
        
        // Get conversation history
        var messages = conversationManager.getConversation(id: conversationId)
        
        // Build user message content
        if images.isEmpty {
            // Simple text message
            messages.append(LLMMessage.text(role: .user, content: userMessage))
        } else {
            // Message with images
            var contentParts: [ChatCompletionParameters.Message.ContentType.MessageContent] = [
                .text(userMessage)
            ]
            
            // Add images
            for imageData in images {
                let base64Image = imageData.base64EncodedString()
                let imageURL = URL(string: "data:image/png;base64,\(base64Image)")!
                let imageDetail = ChatCompletionParameters.Message.ContentType.MessageContent.ImageDetail(url: imageURL)
                contentParts.append(.imageUrl(imageDetail))
            }
            
            let userMessage = ChatCompletionParameters.Message(
                role: .user,
                content: .contentArray(contentParts)
            )
            messages.append(userMessage)
        }
        
        // Create parameters with response format
        let parameters = ChatCompletionParameters(
            messages: messages,
            model: .custom(modelId),
            responseFormat: .jsonObject,
            temperature: temperature ?? defaultTemperature
        )
        
        // Execute request
        let result = try await executeWithRetry(parameters: parameters, requestId: requestId) { response in
            try self.parseStructuredResponse(response, as: responseType)
        }
        
        // Add assistant response (convert result back to text for conversation history)
        let responseText: String
        if let data = try? JSONEncoder().encode(result) {
            responseText = String(data: data, encoding: .utf8) ?? "Structured response"
        } else {
            responseText = "Structured response"
        }
        messages.append(LLMMessage.text(role: .assistant, content: responseText))
        
        // Update conversation
        conversationManager.storeConversation(id: conversationId, messages: messages)
        
        return result
    }
    
    // MARK: - Multi-Model Operations
    
    /// Execute request across multiple models in parallel
    /// - Parameters:
    ///   - prompt: The text prompt
    ///   - modelIds: Array of model identifiers to use
    ///   - responseType: The expected response type
    ///   - temperature: Optional temperature setting
    /// - Returns: Dictionary mapping model IDs to their responses
    func executeParallelStructured<T: Codable>(
        prompt: String,
        modelIds: [String],
        responseType: T.Type,
        temperature: Double? = nil
    ) async throws -> [String: T] {
        try ensureInitialized()
        
        var results: [String: T] = [:]
        
        // Execute in parallel using TaskGroup
        try await withThrowingTaskGroup(of: (String, T).self) { group in
            for modelId in modelIds {
                group.addTask {
                    let result = try await self.executeStructured(
                        prompt: prompt,
                        modelId: modelId,
                        responseType: responseType,
                        temperature: temperature
                    )
                    return (modelId, result)
                }
            }
            
            // Collect results
            for try await (modelId, result) in group {
                results[modelId] = result
            }
        }
        
        return results
    }
    
    // MARK: - Model Management
    
    /// Validate that a model exists and has required capabilities
    /// - Parameters:
    ///   - modelId: The model ID to validate
    ///   - capabilities: Required capabilities
    /// - Throws: LLMError if model is invalid or lacks capabilities
    func validateModel(modelId: String, for capabilities: [ModelCapability]) throws {
        guard let appState = appState else {
            throw LLMError.clientError("LLMService not properly initialized")
        }
        
        // Check if model exists in available models
        guard let model = appState.openRouterService.findModel(id: modelId) else {
            throw LLMError.clientError("Model '\(modelId)' not found")
        }
        
        // Check required capabilities
        for capability in capabilities {
            let hasCapability: Bool
            switch capability {
            case .vision:
                hasCapability = model.supportsImages
            case .structuredOutput:
                hasCapability = model.supportsStructuredOutput
            case .reasoning:
                hasCapability = model.supportsReasoning
            case .textOnly:
                hasCapability = model.isTextToText && !model.supportsImages
            }
            
            if !hasCapability {
                throw LLMError.clientError("Model '\(modelId)' does not support \(capability.displayName)")
            }
        }
    }
    
    // MARK: - Conversation Management
    
    /// Clear a conversation
    /// - Parameter conversationId: The conversation ID to clear
    func clearConversation(id conversationId: UUID) {
        conversationManager?.clearConversation(id: conversationId)
    }
    
    // MARK: - Private Helpers
    
    /// Execute query with retry logic and exponential backoff
    private func executeWithRetry<T>(
        parameters: ChatCompletionParameters,
        requestId: UUID,
        maxRetries: Int? = nil,
        transform: @escaping (LLMResponse) throws -> T
    ) async throws -> T {
        guard let client = openRouterClient else {
            throw LLMError.clientError("OpenRouter client not available")
        }
        
        let retries = maxRetries ?? defaultMaxRetries
        var lastError: Error?
        
        for attempt in 0...retries {
            // Check if request was cancelled
            guard currentRequestIDs.contains(requestId) else {
                throw LLMError.clientError("Request was cancelled")
            }
            
            do {
                Logger.debug("🌐 Making request with model: \(parameters.model)")
                let response = try await client.startChat(parameters: parameters)
                return try transform(response)
            } catch {
                lastError = error
                Logger.debug("❌ Request failed with error: \(error)")
                
                // Log more details for SwiftOpenAI APIErrors
                if let apiError = error as? SwiftOpenAI.APIError {
                    Logger.debug("🔍 SwiftOpenAI APIError details: \(apiError.displayDescription)")
                }
                
                // Don't retry on certain errors
                if let appError = error as? LLMError {
                    switch appError {
                    case .decodingFailed, .unexpectedResponseFormat, .clientError:
                        throw appError
                    case .rateLimited(let retryAfter):
                        if let delay = retryAfter, attempt < retries {
                            Logger.debug("🔄 Rate limited, waiting \(delay)s before retry")
                            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                            continue
                        } else {
                            throw appError
                        }
                    case .timeout:
                        if attempt < retries {
                            let delay = baseRetryDelay * pow(2.0, Double(attempt))
                            Logger.debug("🔄 Request timeout, retrying in \(delay)s (attempt \(attempt + 1)/\(retries + 1))")
                            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                            continue
                        } else {
                            throw appError
                        }
                    }
                }
                
                // Retry for network errors
                if attempt < retries {
                    let delay = baseRetryDelay * pow(2.0, Double(attempt))
                    Logger.debug("🔄 Network error, retrying in \(delay)s (attempt \(attempt + 1)/\(retries + 1))")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                }
            }
        }
        
        // All retries exhausted
        throw lastError ?? LLMError.clientError("Maximum retries exceeded")
    }
    
    /// Parse structured response with fallback strategies
    private func parseStructuredResponse<T: Codable>(_ response: LLMResponse, as type: T.Type) throws -> T {
        guard let content = response.choices?.first?.message?.content else {
            throw LLMError.unexpectedResponseFormat
        }
        
        // Try to parse JSON from the response content
        return try parseJSONFromText(content, as: type)
    }
    
    /// Extract and parse JSON from text response
    private func parseJSONFromText<T: Codable>(_ text: String, as type: T.Type) throws -> T {
        // Try to find JSON in the text
        let jsonPatterns = [
            #"\{[\s\S]*\}"#,  // Object
            #"\[[\s\S]*\]"#   // Array
        ]
        
        for pattern in jsonPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let jsonRange = Range(match.range, in: text) {
                
                let jsonString = String(text[jsonRange])
                if let jsonData = jsonString.data(using: .utf8) {
                    do {
                        return try JSONDecoder().decode(type, from: jsonData)
                    } catch {
                        Logger.debug("⚠️ JSON parsing failed for pattern: \(pattern)")
                        continue
                    }
                }
            }
        }
        
        throw LLMError.unexpectedResponseFormat
    }
    
    /// Cancel all current requests
    func cancelAllRequests() {
        currentRequestIDs.removeAll()
        Logger.debug("🛑 Cancelled all LLM requests")
    }
}

// MARK: - Conversation Manager

/// Simple conversation manager for maintaining conversation state
@MainActor
private class ConversationManager {
    private var conversations: [UUID: [LLMMessage]] = [:]
    private var modelContext: ModelContext?
    
    init(modelContext: ModelContext?) {
        self.modelContext = modelContext
    }
    
    func storeConversation(id: UUID, messages: [LLMMessage]) {
        conversations[id] = messages
        // TODO: Implement SwiftData persistence if needed
    }
    
    func getConversation(id: UUID) -> [LLMMessage] {
        return conversations[id] ?? []
    }
    
    func clearConversation(id: UUID) {
        conversations.removeValue(forKey: id)
    }
}