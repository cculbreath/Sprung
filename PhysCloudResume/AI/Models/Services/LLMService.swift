//
//  LLMService.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 6/4/25.
//

import Foundation
import SwiftUI
import SwiftData

/// Unified LLM service that provides a clean abstraction layer for all LLM operations
/// Supports text-only, multimodal, structured output, and conversational requests
/// Uses OpenRouter as the provider but designed for easy migration to other providers
@MainActor
@Observable
class LLMService {
    static let shared = LLMService()
    
    // Dependencies
    private var appState: AppState?
    private var baseLLMProvider: BaseLLMProvider?
    private var conversationManager: ConversationManager?
    
    // Request management
    private var currentRequestIDs: Set<UUID> = []
    private let requestQueue = DispatchQueue(label: "com.physcloudresume.llmservice", qos: .userInitiated)
    
    // Configuration
    private let defaultTemperature: Double = 1.0
    private let defaultMaxRetries: Int = 3
    private let baseRetryDelay: TimeInterval = 1.0
    
    private init() {}
    
    // MARK: - Initialization
    
    /// Initialize the service with AppState and conversation manager
    func initialize(appState: AppState, modelContext: ModelContext? = nil) {
        self.appState = appState
        self.baseLLMProvider = BaseLLMProvider(appState: appState)
        self.conversationManager = ConversationManager(modelContext: modelContext)
        
        Logger.debug("🔄 LLMService initialized with OpenRouter provider")
    }
    
    private func ensureInitialized() throws {
        guard let appState = appState else {
            throw AppLLMError.clientError("LLMService not initialized - call initialize() first")
        }
        
        if baseLLMProvider == nil {
            baseLLMProvider = BaseLLMProvider(appState: appState)
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
        let message = AppLLMMessage(role: .user, text: prompt)
        
        // Create query
        let query = AppLLMQuery(
            messages: [message],
            modelIdentifier: modelId,
            temperature: temperature ?? defaultTemperature
        )
        
        // Execute with retry logic
        return try await executeWithRetry(query: query, requestId: requestId) { response in
            switch response {
            case .text(let text):
                return text
            case .structured(let data):
                return String(data: data, encoding: .utf8) ?? ""
            }
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
        var contentParts: [AppLLMMessageContentPart] = [.text(prompt)]
        
        // Add images
        for imageData in images {
            let base64Image = imageData.base64EncodedString()
            contentParts.append(.imageUrl(base64Data: base64Image, mimeType: "image/png"))
        }
        
        // Create message
        let message = AppLLMMessage(role: .user, contentParts: contentParts)
        
        // Create query
        let query = AppLLMQuery(
            messages: [message],
            modelIdentifier: modelId,
            temperature: temperature ?? defaultTemperature
        )
        
        // Execute with retry logic
        return try await executeWithRetry(query: query, requestId: requestId) { response in
            switch response {
            case .text(let text):
                return text
            case .structured(let data):
                return String(data: data, encoding: .utf8) ?? ""
            }
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
        let message = AppLLMMessage(role: .user, text: prompt)
        
        // Create structured query
        let query = AppLLMQuery(
            messages: [message],
            modelIdentifier: modelId,
            temperature: temperature ?? defaultTemperature,
            responseType: responseType
        )
        
        // Execute with retry logic
        return try await executeWithRetry(query: query, requestId: requestId) { response in
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
        var contentParts: [AppLLMMessageContentPart] = [.text(prompt)]
        
        // Add images
        for imageData in images {
            let base64Image = imageData.base64EncodedString()
            contentParts.append(.imageUrl(base64Data: base64Image, mimeType: "image/png"))
        }
        
        // Create message
        let message = AppLLMMessage(role: .user, contentParts: contentParts)
        
        // Create structured query
        let query = AppLLMQuery(
            messages: [message],
            modelIdentifier: modelId,
            temperature: temperature ?? defaultTemperature,
            responseType: responseType
        )
        
        // Execute with retry logic
        return try await executeWithRetry(query: query, requestId: requestId) { response in
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
            throw AppLLMError.clientError("Conversation manager not available")
        }
        
        let requestId = UUID()
        currentRequestIDs.insert(requestId)
        defer { currentRequestIDs.remove(requestId) }
        
        // Validate model
        try validateModel(modelId: modelId, for: [])
        
        // Create conversation
        let conversationId = UUID()
        
        // Build messages
        var messages: [AppLLMMessage] = []
        
        // Add system prompt if provided
        if let systemPrompt = systemPrompt {
            messages.append(AppLLMMessage(role: .system, text: systemPrompt))
        }
        
        // Add user message
        messages.append(AppLLMMessage(role: .user, text: userMessage))
        
        // Create query
        let query = AppLLMQuery(
            messages: messages,
            modelIdentifier: modelId,
            temperature: temperature ?? defaultTemperature
        )
        
        // Execute request
        let responseText = try await executeWithRetry(query: query, requestId: requestId) { response in
            switch response {
            case .text(let text):
                return text
            case .structured(let data):
                return String(data: data, encoding: .utf8) ?? ""
            }
        }
        
        // Add assistant response to messages
        messages.append(AppLLMMessage(role: .assistant, text: responseText))
        
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
            throw AppLLMError.clientError("Conversation manager not available")
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
        var contentParts: [AppLLMMessageContentPart] = [.text(userMessage)]
        
        // Add images if provided
        for imageData in images {
            let base64Image = imageData.base64EncodedString()
            contentParts.append(.imageUrl(base64Data: base64Image, mimeType: "image/png"))
        }
        
        // Add user message
        let userAppMessage = AppLLMMessage(role: .user, contentParts: contentParts)
        messages.append(userAppMessage)
        
        // Create query
        let query = AppLLMQuery(
            messages: messages,
            modelIdentifier: modelId,
            temperature: temperature ?? defaultTemperature
        )
        
        // Execute request
        let responseText = try await executeWithRetry(query: query, requestId: requestId) { response in
            switch response {
            case .text(let text):
                return text
            case .structured(let data):
                return String(data: data, encoding: .utf8) ?? ""
            }
        }
        
        // Add assistant response
        messages.append(AppLLMMessage(role: .assistant, text: responseText))
        
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
            throw AppLLMError.clientError("Conversation manager not available")
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
        var contentParts: [AppLLMMessageContentPart] = [.text(userMessage)]
        
        // Add images if provided
        for imageData in images {
            let base64Image = imageData.base64EncodedString()
            contentParts.append(.imageUrl(base64Data: base64Image, mimeType: "image/png"))
        }
        
        // Add user message
        let userAppMessage = AppLLMMessage(role: .user, contentParts: contentParts)
        messages.append(userAppMessage)
        
        // Create structured query
        let query = AppLLMQuery(
            messages: messages,
            modelIdentifier: modelId,
            temperature: temperature ?? defaultTemperature,
            responseType: responseType
        )
        
        // Execute request
        let result = try await executeWithRetry(query: query, requestId: requestId) { response in
            try self.parseStructuredResponse(response, as: responseType)
        }
        
        // Add assistant response (convert result back to text for conversation history)
        let responseText: String
        if let data = try? JSONEncoder().encode(result) {
            responseText = String(data: data, encoding: .utf8) ?? "Structured response"
        } else {
            responseText = "Structured response"
        }
        messages.append(AppLLMMessage(role: .assistant, text: responseText))
        
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
    
    /// Get available models with optional capability filtering
    /// - Parameter capability: Optional capability to filter by
    /// - Returns: Array of model IDs
    func getAvailableModels(capability: ModelCapability? = nil) -> [String] {
        guard let appState = appState else { return [] }
        
        // Start with user-selected models
        let selectedModels = Array(appState.selectedOpenRouterModels)
        
        // Filter by capability if specified
        if let capability = capability {
            let capableModels = appState.openRouterService.getModelsWithCapability(capability)
            let capableModelIds = Set(capableModels.map { $0.id })
            return selectedModels.filter { capableModelIds.contains($0) }
        }
        
        return selectedModels
    }
    
    /// Validate that a model exists and has required capabilities
    /// - Parameters:
    ///   - modelId: The model ID to validate
    ///   - capabilities: Required capabilities
    /// - Throws: AppLLMError if model is invalid or lacks capabilities
    func validateModel(modelId: String, for capabilities: [ModelCapability]) throws {
        guard let appState = appState else {
            throw AppLLMError.clientError("LLMService not properly initialized")
        }
        
        // Check if model exists in available models
        guard let model = appState.openRouterService.findModel(id: modelId) else {
            throw AppLLMError.clientError("Model '\(modelId)' not found")
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
                throw AppLLMError.clientError("Model '\(modelId)' does not support \(capability.displayName)")
            }
        }
    }
    
    // MARK: - Conversation Management
    
    /// Clear a conversation
    /// - Parameter conversationId: The conversation ID to clear
    func clearConversation(id conversationId: UUID) {
        conversationManager?.clearConversation(id: conversationId)
    }
    
    /// Get conversation messages
    /// - Parameter conversationId: The conversation ID
    /// - Returns: Array of messages in the conversation
    func getConversationMessages(id conversationId: UUID) -> [AppLLMMessage] {
        return conversationManager?.getConversation(id: conversationId) ?? []
    }
    
    // MARK: - Private Helpers
    
    /// Execute query with retry logic and exponential backoff
    private func executeWithRetry<T>(
        query: AppLLMQuery,
        requestId: UUID,
        maxRetries: Int? = nil,
        transform: @escaping (AppLLMResponse) throws -> T
    ) async throws -> T {
        guard let provider = baseLLMProvider else {
            throw AppLLMError.clientError("LLM provider not available")
        }
        
        let retries = maxRetries ?? defaultMaxRetries
        var lastError: Error?
        
        for attempt in 0...retries {
            // Check if request was cancelled
            guard currentRequestIDs.contains(requestId) else {
                throw AppLLMError.clientError("Request was cancelled")
            }
            
            do {
                let response = try await provider.executeQuery(query)
                return try transform(response)
            } catch {
                lastError = error
                
                // Don't retry on certain errors
                if let appError = error as? AppLLMError {
                    switch appError {
                    case .decodingFailed, .unexpectedResponseFormat, .clientError, .decodingError:
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
        throw lastError ?? AppLLMError.clientError("Maximum retries exceeded")
    }
    
    /// Parse structured response with fallback strategies
    private func parseStructuredResponse<T: Codable>(_ response: AppLLMResponse, as type: T.Type) throws -> T {
        switch response {
        case .structured(let data):
            // Primary: Try direct decoding of structured data
            do {
                return try JSONDecoder().decode(type, from: data)
            } catch {
                Logger.debug("⚠️ Structured data decoding failed, trying text extraction")
                // Fallback: Try extracting JSON from text
                if let textResponse = String(data: data, encoding: .utf8) {
                    return try parseJSONFromText(textResponse, as: type)
                }
                throw AppLLMError.decodingFailed(error)
            }
            
        case .text(let text):
            // Fallback: Extract JSON from text response
            return try parseJSONFromText(text, as: type)
        }
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
        
        throw AppLLMError.unexpectedResponseFormat
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
    private var conversations: [UUID: [AppLLMMessage]] = [:]
    private var modelContext: ModelContext?
    
    init(modelContext: ModelContext?) {
        self.modelContext = modelContext
    }
    
    func storeConversation(id: UUID, messages: [AppLLMMessage]) {
        conversations[id] = messages
        // TODO: Implement SwiftData persistence if needed
    }
    
    func getConversation(id: UUID) -> [AppLLMMessage] {
        return conversations[id] ?? []
    }
    
    func clearConversation(id: UUID) {
        conversations.removeValue(forKey: id)
    }
}