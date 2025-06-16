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

// MARK: - Streaming Response Types

/// Represents a chunk of streamed content from the LLM
public struct LLMStreamChunk {
    /// Regular content from the response
    public let content: String?
    /// Reasoning content (thinking tokens) if available
    public let reasoningContent: String?
    /// Whether this is the final chunk
    public let isFinished: Bool
    /// The finish reason if applicable
    public let finishReason: String?
    
    init(content: String? = nil, reasoningContent: String? = nil, isFinished: Bool = false, finishReason: String? = nil) {
        self.content = content
        self.reasoningContent = reasoningContent
        self.isFinished = isFinished
        self.finishReason = finishReason
    }
}

// MARK: - LLM Error Types

enum LLMError: LocalizedError {
    case clientError(String)
    case decodingFailed(Error)
    case unexpectedResponseFormat
    case rateLimited(retryAfter: TimeInterval?)
    case timeout
    case unauthorized(String)
    
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
        case .unauthorized(let modelId):
            return "Access denied for model '\(modelId)'. This model may require special authorization or billing setup."
        }
    }
}

/// Unified LLM service that acts as a facade/coordinator for all LLM operations
/// Supports text-only, multimodal, structured output, and conversational requests
/// Uses OpenRouter as the provider but designed for easy migration to other providers
@MainActor
@Observable
class LLMService {
    static let shared = LLMService()
    
    // Dependencies
    private var appState: AppState?
    private var conversationManager: ConversationManager?
    private var enabledLLMStore: EnabledLLMStore?
    
    // Components
    private let requestExecutor = LLMRequestExecutor()
    
    // Configuration
    private let defaultTemperature: Double = 1.0
    
    private init() {}
    
    // MARK: - Initialization
    
    /// Initialize the service with AppState and conversation manager
    func initialize(appState: AppState, modelContext: ModelContext? = nil) {
        self.appState = appState
        self.conversationManager = ConversationManager(modelContext: modelContext)
        self.enabledLLMStore = appState.enabledLLMStore
        
        // Configure request executor with current API key
        reconfigureClient()
        
        Logger.info("🔄 LLMService initialized with OpenRouter client")
    }
    
    /// Reconfigure the OpenRouter client with the current API key from UserDefaults
    func reconfigureClient() {
        requestExecutor.configureClient()
        Logger.info("🔄 LLMService reconfigured OpenRouter client")
    }
    
    private func ensureInitialized() throws {
        guard appState != nil else {
            throw LLMError.clientError("LLMService not initialized - call initialize() first")
        }
        
        // Ensure client is configured with current API key
        if !requestExecutor.isConfigured() {
            reconfigureClient()
        }
        
        guard requestExecutor.isConfigured() else {
            throw LLMError.clientError("OpenRouter API key not configured")
        }
        
        if conversationManager == nil {
            conversationManager = ConversationManager(modelContext: nil)
        }
    }
    
    // MARK: - Core Operations
    
    /// Simple text-only request
    func execute(
        prompt: String,
        modelId: String,
        temperature: Double? = nil
    ) async throws -> String {
        try ensureInitialized()
        
        // Validate model
        try validateModel(modelId: modelId, for: [])
        
        // 1. Build
        let parameters = LLMRequestBuilder.buildTextRequest(
            prompt: prompt,
            modelId: modelId,
            temperature: temperature ?? defaultTemperature
        )
        
        // 2. Execute
        let response = try await requestExecutor.execute(parameters: parameters)
        
        // 3. Parse
        guard let content = response.choices?.first?.message?.content else {
            throw LLMError.unexpectedResponseFormat
        }
        
        return content
    }
    
    /// Request with image inputs
    func executeWithImages(
        prompt: String,
        modelId: String,
        images: [Data],
        temperature: Double? = nil
    ) async throws -> String {
        try ensureInitialized()
        
        // Validate model supports vision
        try validateModel(modelId: modelId, for: [.vision])
        
        // 1. Build
        let parameters = LLMRequestBuilder.buildVisionRequest(
            prompt: prompt,
            modelId: modelId,
            images: images,
            temperature: temperature ?? defaultTemperature
        )
        
        // 2. Execute
        let response = try await requestExecutor.execute(parameters: parameters)
        
        // 3. Parse
        guard let content = response.choices?.first?.message?.content else {
            throw LLMError.unexpectedResponseFormat
        }
        
        return content
    }
    
    /// Request with structured JSON output
    func executeStructured<T: Codable>(
        prompt: String,
        modelId: String,
        responseType: T.Type,
        temperature: Double? = nil,
        jsonSchema: JSONSchema? = nil
    ) async throws -> T {
        try ensureInitialized()
        
        // Validate model
        try validateModel(modelId: modelId, for: [])
        
        // 1. Build
        let parameters = LLMRequestBuilder.buildStructuredRequest(
            prompt: prompt,
            modelId: modelId,
            responseType: responseType,
            temperature: temperature ?? defaultTemperature,
            jsonSchema: jsonSchema
        )
        
        // 2. Execute
        let response = try await requestExecutor.execute(parameters: parameters)
        
        // 3. Parse
        return try JSONResponseParser.parseStructured(response, as: responseType)
    }
    
    /// Request with both image inputs and structured output
    func executeStructuredWithImages<T: Codable>(
        prompt: String,
        modelId: String,
        images: [Data],
        responseType: T.Type,
        temperature: Double? = nil
    ) async throws -> T {
        try ensureInitialized()
        
        // Validate model supports vision
        try validateModel(modelId: modelId, for: [.vision])
        
        // 1. Build
        let parameters = LLMRequestBuilder.buildStructuredVisionRequest(
            prompt: prompt,
            modelId: modelId,
            images: images,
            responseType: responseType,
            temperature: temperature ?? defaultTemperature
        )
        
        // 2. Execute
        let response = try await requestExecutor.execute(parameters: parameters)
        
        // 3. Parse
        return try JSONResponseParser.parseStructured(response, as: responseType)
    }
    
    // MARK: - Streaming Operations
    
    /// Execute a streaming request with optional reasoning
    func executeStreaming(
        prompt: String,
        modelId: String,
        temperature: Double? = nil,
        reasoning: OpenRouterReasoning? = nil
    ) -> AsyncThrowingStream<LLMStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try ensureInitialized()
                    
                    // Validate model
                    try validateModel(modelId: modelId, for: [])
                    
                    // Build parameters with reasoning if provided
                    var parameters = LLMRequestBuilder.buildTextRequest(
                        prompt: prompt,
                        modelId: modelId,
                        temperature: temperature ?? defaultTemperature
                    )
                    
                    // Add reasoning parameters if provided
                    if let reasoning = reasoning {
                        var reasoningDict: [String: Any] = [:]
                        if let effort = reasoning.effort {
                            reasoningDict["effort"] = effort
                        }
                        if let maxTokens = reasoning.maxTokens {
                            reasoningDict["max_tokens"] = maxTokens
                        }
                        if let exclude = reasoning.exclude {
                            reasoningDict["exclude"] = exclude
                        }
                        if let enabled = reasoning.enabled {
                            reasoningDict["enabled"] = enabled
                        }
                        parameters.reasoning = reasoningDict
                    }
                    
                    // Enable streaming
                    parameters.stream = true
                    parameters.streamOptions = StreamOptions(includeUsage: true)
                    
                    // Execute streaming request
                    let stream = try await requestExecutor.executeStreaming(parameters: parameters)
                    
                    // Process stream chunks
                    for try await chunk in stream {
                        if let firstChoice = chunk.choices?.first {
                            let streamChunk = LLMStreamChunk(
                                content: firstChoice.delta?.content,
                                reasoningContent: firstChoice.delta?.reasoningContent,
                                isFinished: firstChoice.finishReason != nil,
                                finishReason: firstChoice.finishReason?.value as? String
                            )
                            continuation.yield(streamChunk)
                        }
                    }
                    
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    /// Execute a structured streaming request with optional reasoning
    func executeStructuredStreaming<T: Codable>(
        prompt: String,
        modelId: String,
        responseType: T.Type,
        temperature: Double? = nil,
        reasoning: OpenRouterReasoning? = nil,
        jsonSchema: JSONSchema? = nil
    ) -> AsyncThrowingStream<LLMStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try ensureInitialized()
                    
                    // Validate model
                    try validateModel(modelId: modelId, for: [])
                    
                    // Build structured parameters
                    var parameters = LLMRequestBuilder.buildStructuredRequest(
                        prompt: prompt,
                        modelId: modelId,
                        responseType: responseType,
                        temperature: temperature ?? defaultTemperature,
                        jsonSchema: jsonSchema
                    )
                    
                    // Add reasoning parameters if provided
                    if let reasoning = reasoning {
                        var reasoningDict: [String: Any] = [:]
                        if let effort = reasoning.effort {
                            reasoningDict["effort"] = effort
                        }
                        if let maxTokens = reasoning.maxTokens {
                            reasoningDict["max_tokens"] = maxTokens
                        }
                        if let exclude = reasoning.exclude {
                            reasoningDict["exclude"] = exclude
                        }
                        if let enabled = reasoning.enabled {
                            reasoningDict["enabled"] = enabled
                        }
                        parameters.reasoning = reasoningDict
                    }
                    
                    // Enable streaming
                    parameters.stream = true
                    parameters.streamOptions = StreamOptions(includeUsage: true)
                    
                    // Execute streaming request
                    let stream = try await requestExecutor.executeStreaming(parameters: parameters)
                    
                    // Process stream chunks
                    for try await chunk in stream {
                        if let firstChoice = chunk.choices?.first {
                            let streamChunk = LLMStreamChunk(
                                content: firstChoice.delta?.content,
                                reasoningContent: firstChoice.delta?.reasoningContent,
                                isFinished: firstChoice.finishReason != nil,
                                finishReason: firstChoice.finishReason?.value as? String
                            )
                            continuation.yield(streamChunk)
                        }
                    }
                    
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    /// Continue conversation with streaming response
    func continueConversationStreaming(
        userMessage: String,
        modelId: String,
        conversationId: UUID,
        images: [Data] = [],
        temperature: Double? = nil,
        reasoning: OpenRouterReasoning? = nil
    ) -> AsyncThrowingStream<LLMStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try ensureInitialized()
                    
                    guard let conversationManager = conversationManager else {
                        throw LLMError.clientError("Conversation manager not available")
                    }
                    
                    // Validate model (require vision if images provided)
                    let requiredCapabilities: [ModelCapability] = images.isEmpty ? [] : [.vision]
                    try validateModel(modelId: modelId, for: requiredCapabilities)
                    
                    // Get conversation history
                    var messages = conversationManager.getConversation(id: conversationId)
                    Logger.info("🗣️ Continuing streaming conversation: \(conversationId) with model: \(modelId)")
                    
                    // Build user message content
                    if images.isEmpty {
                        messages.append(LLMMessage.text(role: .user, content: userMessage))
                    } else {
                        var contentParts: [ChatCompletionParameters.Message.ContentType.MessageContent] = [
                            .text(userMessage)
                        ]
                        
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
                    
                    // Build parameters
                    var parameters = LLMRequestBuilder.buildConversationRequest(
                        messages: messages,
                        modelId: modelId,
                        temperature: temperature ?? defaultTemperature
                    )
                    
                    // Add reasoning parameters if provided
                    if let reasoning = reasoning {
                        var reasoningDict: [String: Any] = [:]
                        if let effort = reasoning.effort {
                            reasoningDict["effort"] = effort
                        }
                        if let maxTokens = reasoning.maxTokens {
                            reasoningDict["max_tokens"] = maxTokens
                        }
                        if let exclude = reasoning.exclude {
                            reasoningDict["exclude"] = exclude
                        }
                        if let enabled = reasoning.enabled {
                            reasoningDict["enabled"] = enabled
                        }
                        parameters.reasoning = reasoningDict
                    }
                    
                    // Enable streaming
                    parameters.stream = true
                    parameters.streamOptions = StreamOptions(includeUsage: true)
                    
                    // Execute streaming request
                    let stream = try await requestExecutor.executeStreaming(parameters: parameters)
                    
                    // Accumulate response for conversation history
                    var fullResponse = ""
                    
                    // Process stream chunks
                    for try await chunk in stream {
                        if let firstChoice = chunk.choices?.first {
                            // Accumulate content
                            if let content = firstChoice.delta?.content {
                                fullResponse += content
                            }
                            
                            let streamChunk = LLMStreamChunk(
                                content: firstChoice.delta?.content,
                                reasoningContent: firstChoice.delta?.reasoningContent,
                                isFinished: firstChoice.finishReason != nil,
                                finishReason: firstChoice.finishReason?.value as? String
                            )
                            continuation.yield(streamChunk)
                            
                            // When finished, update conversation history
                            if firstChoice.finishReason != nil {
                                messages.append(LLMMessage.text(role: .assistant, content: fullResponse))
                                conversationManager.storeConversation(id: conversationId, messages: messages)
                                Logger.info("✅ Streaming conversation updated: \(conversationId)")
                            }
                        }
                    }
                    
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Conversation Operations
    
    /// Start a new conversation
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
        
        // Validate model
        try validateModel(modelId: modelId, for: [])
        
        // Create conversation
        let conversationId = UUID()
        Logger.info("🗣️ Starting new conversation: \(conversationId) with model: \(modelId)")
        
        // Build messages
        var messages: [LLMMessage] = []
        
        // Add system prompt if provided
        if let systemPrompt = systemPrompt {
            messages.append(LLMMessage.text(role: .system, content: systemPrompt))
        }
        
        // Add user message
        messages.append(LLMMessage.text(role: .user, content: userMessage))
        
        // 1. Build
        let parameters = LLMRequestBuilder.buildConversationRequest(
            messages: messages,
            modelId: modelId,
            temperature: temperature ?? defaultTemperature
        )
        
        // 2. Execute
        let response = try await requestExecutor.execute(parameters: parameters)
        
        // 3. Parse
        guard let responseText = response.choices?.first?.message?.content else {
            throw LLMError.unexpectedResponseFormat
        }
        
        // Add assistant response to messages
        messages.append(LLMMessage.text(role: .assistant, content: responseText))
        
        // Store conversation
        conversationManager.storeConversation(id: conversationId, messages: messages)
        
        Logger.info("✅ Conversation started successfully: \(conversationId)")
        return (conversationId: conversationId, response: responseText)
    }
    
    /// Continue an existing conversation
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
        
        // Validate model (require vision if images provided)
        let requiredCapabilities: [ModelCapability] = images.isEmpty ? [] : [.vision]
        try validateModel(modelId: modelId, for: requiredCapabilities)
        
        // Get conversation history
        var messages = conversationManager.getConversation(id: conversationId)
        Logger.info("🗣️ Continuing conversation: \(conversationId) with model: \(modelId)")
        
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
        
        // 1. Build
        let parameters = LLMRequestBuilder.buildConversationRequest(
            messages: messages,
            modelId: modelId,
            temperature: temperature ?? defaultTemperature
        )
        
        // 2. Execute
        let response = try await requestExecutor.execute(parameters: parameters)
        
        // 3. Parse
        guard let responseText = response.choices?.first?.message?.content else {
            throw LLMError.unexpectedResponseFormat
        }
        
        // Add assistant response
        messages.append(LLMMessage.text(role: .assistant, content: responseText))
        
        // Update conversation
        conversationManager.storeConversation(id: conversationId, messages: messages)
        
        Logger.info("✅ Conversation continued successfully: \(conversationId)")
        return responseText
    }
    
    /// Continue conversation with structured output
    func continueConversationStructured<T: Codable>(
        userMessage: String,
        modelId: String,
        conversationId: UUID,
        responseType: T.Type,
        images: [Data] = [],
        temperature: Double? = nil,
        jsonSchema: JSONSchema? = nil
    ) async throws -> T {
        try ensureInitialized()
        
        guard let conversationManager = conversationManager else {
            throw LLMError.clientError("Conversation manager not available")
        }
        
        // Validate model (require vision if images provided)
        let requiredCapabilities: [ModelCapability] = images.isEmpty ? [] : [.vision]
        try validateModel(modelId: modelId, for: requiredCapabilities)
        
        // Get conversation history
        var messages = conversationManager.getConversation(id: conversationId)
        Logger.info("🗣️ Continuing structured conversation: \(conversationId) with model: \(modelId)")
        
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
        
        // 1. Build
        let parameters = LLMRequestBuilder.buildStructuredConversationRequest(
            messages: messages,
            modelId: modelId,
            responseType: responseType,
            temperature: temperature ?? defaultTemperature,
            jsonSchema: jsonSchema
        )
        
        // 2. Execute
        let response = try await requestExecutor.execute(parameters: parameters)
        
        // 3. Parse
        let result = try JSONResponseParser.parseStructured(response, as: responseType)
        
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
        
        Logger.info("✅ Structured conversation continued successfully: \(conversationId)")
        return result
    }
    
    // MARK: - Multi-Model Operations
    
    /// Execute request across multiple models in parallel
    func executeParallelStructured<T: Codable & Sendable>(
        prompt: String,
        modelIds: [String],
        responseType: T.Type,
        temperature: Double? = nil
    ) async throws -> [String: T] {
        try ensureInitialized()
        
        Logger.info("🚀 Starting parallel execution across \(modelIds.count) models")
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
        
        Logger.info("✅ Parallel execution completed: \(results.count)/\(modelIds.count) models succeeded")
        return results
    }
    
    /// Result containing both successful and failed model results
    struct ParallelExecutionResult<T: Codable & Sendable> {
        let successes: [String: T]
        let failures: [String: String]
        
        var hasSuccesses: Bool { !successes.isEmpty }
        var hasFailures: Bool { !failures.isEmpty }
        var totalModels: Int { successes.count + failures.count }
    }
    
    /// Execute request across multiple models in parallel with flexible JSON handling
    func executeParallelFlexibleJSONWithFailures<T: Codable & Sendable>(
        prompt: String,
        modelIds: [String],
        responseType: T.Type,
        temperature: Double? = nil,
        jsonSchema: JSONSchema? = nil
    ) async throws -> ParallelExecutionResult<T> {
        try ensureInitialized()
        
        Logger.info("🚀 Starting flexible parallel execution across \(modelIds.count) models")
        var results: [String: T] = [:]
        var failures: [String: String] = [:]
        
        // Execute in parallel using TaskGroup, collecting both successes and failures
        await withTaskGroup(of: (String, Result<T, Error>).self) { group in
            for modelId in modelIds {
                group.addTask {
                    do {
                        let result = try await self.executeFlexibleJSON(
                            prompt: prompt,
                            modelId: modelId,
                            responseType: responseType,
                            temperature: temperature,
                            jsonSchema: jsonSchema
                        )
                        return (modelId, .success(result))
                    } catch {
                        Logger.debug("❌ Model \(modelId) failed: \(error.localizedDescription)")
                        return (modelId, .failure(error))
                    }
                }
            }
            
            // Collect results
            for await (modelId, result) in group {
                switch result {
                case .success(let value):
                    results[modelId] = value
                case .failure(let error):
                    failures[modelId] = error.localizedDescription
                }
            }
        }
        
        // Log failure summary
        if !failures.isEmpty {
            Logger.debug("⚠️ \(failures.count) of \(modelIds.count) models failed:")
            for (modelId, error) in failures {
                Logger.debug("  - \(modelId): \(error)")
            }
        }
        
        Logger.info("✅ Flexible parallel execution completed: \(results.count)/\(modelIds.count) models succeeded, \(failures.count) failed")
        return ParallelExecutionResult(successes: results, failures: failures)
    }
    
    /// Execute request across multiple models in parallel with flexible JSON handling and progress reporting
    func executeParallelFlexibleJSONWithProgress<T: Codable & Sendable>(
        prompt: String,
        modelIds: [String],
        responseType: T.Type,
        temperature: Double? = nil,
        jsonSchema: JSONSchema? = nil,
        onProgress: @MainActor @escaping (Int, Int) -> Void
    ) async throws -> ParallelExecutionResult<T> {
        try ensureInitialized()
        
        Logger.info("🚀 Starting flexible parallel execution with progress across \(modelIds.count) models")
        var results: [String: T] = [:]
        var failures: [String: String] = [:]
        var completedCount = 0
        let totalCount = modelIds.count
        
        // Execute in parallel using TaskGroup, collecting both successes and failures
        await withTaskGroup(of: (String, Result<T, Error>).self) { group in
            for modelId in modelIds {
                group.addTask {
                    do {
                        let result = try await self.executeFlexibleJSON(
                            prompt: prompt,
                            modelId: modelId,
                            responseType: responseType,
                            temperature: temperature,
                            jsonSchema: jsonSchema
                        )
                        return (modelId, .success(result))
                    } catch {
                        Logger.debug("❌ Model \(modelId) failed: \(error.localizedDescription)")
                        return (modelId, .failure(error))
                    }
                }
            }
            
            // Collect results and report progress
            for await (modelId, result) in group {
                switch result {
                case .success(let value):
                    results[modelId] = value
                case .failure(let error):
                    failures[modelId] = error.localizedDescription
                }
                
                completedCount += 1
                onProgress(completedCount, totalCount)
            }
        }
        
        // Log failure summary
        if !failures.isEmpty {
            Logger.debug("⚠️ \(failures.count) of \(modelIds.count) models failed:")
            for (modelId, error) in failures {
                Logger.debug("  - \(modelId): \(error)")
            }
        }
        
        Logger.info("✅ Flexible parallel execution completed: \(results.count)/\(modelIds.count) models succeeded, \(failures.count) failed")
        return ParallelExecutionResult(successes: results, failures: failures)
    }
    
    /// Execute request across multiple models in parallel with flexible JSON handling (legacy method)
    func executeParallelFlexibleJSON<T: Codable & Sendable>(
        prompt: String,
        modelIds: [String],
        responseType: T.Type,
        temperature: Double? = nil,
        jsonSchema: JSONSchema? = nil
    ) async throws -> [String: T] {
        let result = try await executeParallelFlexibleJSONWithFailures(
            prompt: prompt,
            modelIds: modelIds,
            responseType: responseType,
            temperature: temperature,
            jsonSchema: jsonSchema
        )
        return result.successes
    }
    
    /// Request with flexible JSON output - uses structured output when available, basic JSON mode otherwise
    func executeFlexibleJSON<T: Codable>(
        prompt: String,
        modelId: String,
        responseType: T.Type,
        temperature: Double? = nil,
        jsonSchema: JSONSchema? = nil
    ) async throws -> T {
        try ensureInitialized()
        
        // Validate model exists
        try validateModel(modelId: modelId, for: [])
        
        // Check if model supports structured output and should use JSON schema
        let model = appState?.openRouterService.findModel(id: modelId)
        let supportsStructuredOutput = model?.supportsStructuredOutput ?? false
        let shouldAvoidJSONSchema = enabledLLMStore?.shouldAvoidJSONSchema(modelId: modelId) ?? false
        
        // 1. Build
        let parameters = LLMRequestBuilder.buildFlexibleJSONRequest(
            prompt: prompt,
            modelId: modelId,
            responseType: responseType,
            temperature: temperature ?? defaultTemperature,
            jsonSchema: jsonSchema,
            supportsStructuredOutput: supportsStructuredOutput,
            shouldAvoidJSONSchema: shouldAvoidJSONSchema
        )
        
        // 2. Execute and parse with flexible strategies
        do {
            let response = try await requestExecutor.execute(parameters: parameters)
            let result = try JSONResponseParser.parseFlexible(from: response, as: responseType)
            
            // Record success if we used JSON schema
            if supportsStructuredOutput && !shouldAvoidJSONSchema && jsonSchema != nil {
                enabledLLMStore?.recordJSONSchemaSuccess(modelId: modelId)
                Logger.info("✅ JSON schema validation successful for model: \(modelId)")
            }
            
            return result
        } catch {
            // Record failure if it was related to JSON schema
            if let apiError = error as? SwiftOpenAI.APIError,
               apiError.displayDescription.contains("response_format") ||
               apiError.displayDescription.contains("json_schema") {
                enabledLLMStore?.recordJSONSchemaFailure(modelId: modelId, reason: apiError.displayDescription)
                Logger.debug("🚫 Recorded JSON schema failure for \(modelId): \(apiError.displayDescription)")
            }
            throw error
        }
    }
    
    // MARK: - Model Management
    
    /// Validate that a model exists and has required capabilities
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
    func clearConversation(id conversationId: UUID) {
        conversationManager?.clearConversation(id: conversationId)
    }
    
    /// Cancel all current requests
    func cancelAllRequests() {
        requestExecutor.cancelAllRequests()
        Logger.info("🛑 Cancelled all LLM requests")
    }
}