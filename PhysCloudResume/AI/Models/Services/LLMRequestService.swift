//
//  LLMRequestService.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 5/20/25.
//

import Foundation
import SwiftUI
import SwiftData

/// Service responsible for handling LLM API requests via OpenRouter
class LLMRequestService: @unchecked Sendable {
    /// Shared instance of the service
    static let shared = LLMRequestService()
    
    private var baseLLMProvider: BaseLLMProvider?
    private var currentRequestID: UUID?
    private let apiQueue = DispatchQueue(label: "com.physcloudresume.apirequest", qos: .userInitiated)
    private var appState: AppState?
    
    // Private initializer for singleton pattern
    private init() {}
    
    /// Initializes the LLM provider with OpenRouter
    @MainActor
    func initialize() {
        updateClientForCurrentModel()
    }
    
    /// Updates the provider for the current model - call this whenever the preferred model changes
    @MainActor
    func updateClientForCurrentModel() {
        let currentModel = OpenAIModelFetcher.getPreferredModelString()
        
        Logger.debug("🔄 Updating OpenRouter provider for model: \(currentModel)")
        
        // Initialize AppState if needed
        if appState == nil {
            appState = AppState()
        }
        
        // Create BaseLLMProvider with OpenRouter
        if let state = appState {
            baseLLMProvider = BaseLLMProvider(appState: state)
            Logger.debug("✅ Initialized OpenRouter provider for model: \(currentModel)")
        } else {
            Logger.error("❌ Failed to initialize OpenRouter provider")
        }
    }
    
    /// Checks if the currently selected model supports images
    @MainActor
    func checkIfModelSupportsImages() -> Bool {
        guard let state = appState else { return false }
        
        let modelId = OpenAIModelFetcher.getPreferredModelString()
        if let model = state.openRouterService.findModel(id: modelId) {
            return model.supportsImages
        }
        
        // Fallback to legacy logic if model not found in OpenRouter
        let model = modelId.lowercased()
        let provider = AIModels.providerForModel(model)

        // For OpenAI models – all of the filtered models support images
        let openAIVisionModelsSubstrings = ["gpt-4o", "gpt-4-turbo", "gpt-4-vision", "gpt-4.1", "gpt-4.5", "gpt-image", "o4", "cua"]

        // Claude 3 family supports vision natively
        let claudeVisionSubstrings = ["claude-3", "claude-3-opus", "claude-3-sonnet", "claude-3-haiku", "claude-3.5"]

        // Gemini models exposed by the picker all support vision
        let geminiVisionSubstrings = ["gemini-pro-vision", "gemini-1.5"]

        // Grok – currently *only* the dedicated vision model supports image input
        let grokVisionSubstrings = ["grok-2-vision"]

        switch provider {
        case AIModels.Provider.openai:
            return openAIVisionModelsSubstrings.contains { model.contains($0) }
        case AIModels.Provider.claude:
            return claudeVisionSubstrings.contains { model.contains($0) }
        case AIModels.Provider.grok:
            return grokVisionSubstrings.contains { model.contains($0) } || model.contains("-vision")
        case AIModels.Provider.gemini:
            return geminiVisionSubstrings.contains { model.contains($0) }
        default:
            return false
        }
    }

    /// Chooses the correct model for an image request.  If the selected model cannot accept image
    /// input we transparently substitute a compatible model from the same provider.
    /// - Parameters:
    ///   - model: The user-selected model string.
    ///   - wantsImage: Boolean indicating whether the request includes an image.
    /// - Returns: A model string that is safe for the request.
    private static func modelForImageRequest(selectedModel model: String, wantsImage: Bool) -> String {
        guard wantsImage else { return model }

        let provider = AIModels.providerForModel(model)

        if provider == AIModels.Provider.grok {
            // Grok vision models are unreliable, use o4-mini instead for image analysis
            return "o4-mini"
        }

        return model
    }

    /// Sends a standard LLM request with text-only content
    @MainActor
    func sendTextRequest(
        promptText: String,
        model: String? = nil,
        onProgress: @escaping (String) -> Void,
        onComplete: @escaping (Result<ResponsesAPIResponse, Error>) -> Void
    ) {
        // Initialize provider if needed
        if baseLLMProvider == nil {
            initialize()
        }
        
        // Use provided model or fall back to preferred model
        let modelToUse = model ?? OpenAIModelFetcher.getPreferredModelString()
        
        let requestID = UUID()
        currentRequestID = requestID
        
        Task {
            do {
                // Ensure we have a provider
                guard let provider = baseLLMProvider else {
                    throw NSError(domain: "LLMRequestService", code: 1000,
                                userInfo: [NSLocalizedDescriptionKey: "OpenRouter provider not initialized"])
                }
                
                // Convert single text prompt to AppLLMMessage format
                let messages = [AppLLMMessage(role: .user, text: promptText)]
                
                // Create query
                let query = AppLLMQuery(
                    messages: messages,
                    modelIdentifier: modelToUse,
                    temperature: 1.0
                )

                // Execute query
                let response = try await provider.executeQuery(query)
                
                // Ensure request is still current
                guard self.currentRequestID == requestID else { return }
                
                // Extract response content
                let responseText: String
                switch response {
                case .text(let text):
                    responseText = text
                case .structured(let data):
                    responseText = String(data: data, encoding: .utf8) ?? ""
                }
                
                // Provide progress update
                await MainActor.run {
                    onProgress(responseText)
                }
                
                // Convert to legacy ResponsesAPIResponse format for backward compatibility
                let compatResponse = ResponsesAPIResponse(
                    id: UUID().uuidString,
                    content: responseText,
                    model: modelToUse
                )
                
                await MainActor.run {
                    onComplete(.success(compatResponse))
                }
            } catch {
                Logger.debug("Error in sendTextRequest: \(error.localizedDescription)")
                
                // Create user-friendly error message
                var userErrorMessage = "Error processing your request. "
                
                if let appError = error as? AppLLMError {
                    switch appError {
                    case .clientError(let message):
                        userErrorMessage += message
                    case .decodingFailed:
                        userErrorMessage += "Failed to process the model's response."
                    case .unexpectedResponseFormat:
                        userErrorMessage += "The model returned an unexpected response format."
                    case .decodingError(let message):
                        userErrorMessage += message
                    case .timeout(let message):
                        userErrorMessage += message
                    case .rateLimited(let retryAfter):
                        if let retryAfter = retryAfter {
                            userErrorMessage = "Rate limit exceeded. Please try again in \(Int(retryAfter)) seconds."
                        } else {
                            userErrorMessage = "Rate limit exceeded. Please try again later."
                        }
                    }
                } else {
                    let nsError = error as NSError
                    if nsError.domain.contains("URLError") && nsError.code == -1001 {
                        userErrorMessage += "Request timed out. Please check your network connection and try again."
                    } else {
                        userErrorMessage += error.localizedDescription
                    }
                }
                
                // Ensure request is still current
                guard self.currentRequestID == requestID else { return }
                
                await MainActor.run {
                    onComplete(.failure(NSError(
                        domain: "LLMRequestService",
                        code: 1100,
                        userInfo: [NSLocalizedDescriptionKey: userErrorMessage]
                    )))
                }
            }
        }
    }
    
    /// Sends a request with image support but no structured output
    func sendMixedRequest(
        promptText: String,
        base64Image: String?,
        requestID: UUID = UUID(),
        onComplete: @escaping (Result<ResponsesAPIResponse, Error>) -> Void
    ) {
        currentRequestID = requestID
        
        Task {
            do {
                // Initialize provider if needed
                if baseLLMProvider == nil {
                    await MainActor.run {
                        initialize()
                    }
                }
                
                guard let provider = baseLLMProvider else {
                    throw AppLLMError.clientError("OpenRouter provider not initialized")
                }
                
                let selectedModel = OpenAIModelFetcher.getPreferredModelString()
                let currentModel = LLMRequestService.modelForImageRequest(
                    selectedModel: selectedModel,
                    wantsImage: base64Image != nil
                )
                
                // Build message content
                var contentParts: [AppLLMMessageContentPart] = []
                
                // Add text part
                contentParts.append(.text(promptText))
                
                // Add image part if provided
                if let image = base64Image {
                    contentParts.append(.imageUrl(base64Data: image, mimeType: "image/png"))
                }
                
                // Create message
                let message = AppLLMMessage(role: .user, contentParts: contentParts)
                
                // Create simple text query (no structured output)
                let query = AppLLMQuery(
                    messages: [message],
                    modelIdentifier: currentModel,
                    temperature: 1.0
                )
                
                // Execute query
                let response = try await provider.executeQuery(query)
                
                // Extract response content
                let responseText: String
                switch response {
                case .text(let text):
                    responseText = text
                case .structured(let data):
                    responseText = String(data: data, encoding: .utf8) ?? ""
                }
                
                // Convert to legacy ResponsesAPIResponse format
                let compatResponse = ResponsesAPIResponse(
                    id: UUID().uuidString,
                    content: responseText,
                    model: currentModel
                )
                
                await MainActor.run {
                    onComplete(.success(compatResponse))
                }
            } catch {
                await MainActor.run {
                    Logger.debug("Error in sendMixedRequest: \(error.localizedDescription)")
                    onComplete(.failure(error))
                }
            }
        }
    }
    
    /// Sends a request with image support and structured output enforced by schema
    func sendStructuredMixedRequest<T: Decodable>(
        promptText: String,
        base64Image: String?,
        responseType: T.Type,
        jsonSchema: String? = nil,
        requestID: UUID = UUID(),
        onComplete: @escaping (Result<ResponsesAPIResponse, Error>) -> Void
    ) {
        currentRequestID = requestID
        
        Task {
            do {
                // Initialize provider if needed
                if baseLLMProvider == nil {
                    await MainActor.run {
                        initialize()
                    }
                }
                
                guard let provider = baseLLMProvider else {
                    throw AppLLMError.clientError("OpenRouter provider not initialized")
                }
                
                let selectedModel = OpenAIModelFetcher.getPreferredModelString()
                let currentModel = LLMRequestService.modelForImageRequest(
                    selectedModel: selectedModel,
                    wantsImage: base64Image != nil
                )
                
                // Build message content
                var contentParts: [AppLLMMessageContentPart] = []
                
                // Add text part
                contentParts.append(.text(promptText))
                
                // Add image part if provided
                if let image = base64Image {
                    contentParts.append(.imageUrl(base64Data: image, mimeType: "image/png"))
                }
                
                // Create message
                let message = AppLLMMessage(role: .user, contentParts: contentParts)
                
                // Create structured query with response format enforcement
                let query = AppLLMQuery(
                    messages: [message],
                    modelIdentifier: currentModel,
                    temperature: 1.0,
                    responseType: responseType,
                    jsonSchema: jsonSchema
                )
                
                // Execute query
                let response = try await provider.executeQuery(query)
                
                // Extract response content
                let responseText: String
                switch response {
                case .text(let text):
                    responseText = text
                case .structured(let data):
                    responseText = String(data: data, encoding: .utf8) ?? ""
                }
                
                // Convert to legacy ResponsesAPIResponse format
                let compatResponse = ResponsesAPIResponse(
                    id: UUID().uuidString,
                    content: responseText,
                    model: currentModel
                )
                
                await MainActor.run {
                    onComplete(.success(compatResponse))
                }
            } catch {
                await MainActor.run {
                    Logger.debug("Error in sendStructuredMixedRequest: \(error.localizedDescription)")
                    onComplete(.failure(error))
                }
            }
        }
    }
    
    // MARK: - Conversational AI Methods
    
    /// Sends a conversational request with context management for Resume chat
    @MainActor
    func sendResumeConversationRequest(
        resume: Resume,
        userMessage: String,
        systemPrompt: String?,
        base64Image: String? = nil,
        isNewConversation: Bool = false,
        onProgress: @escaping (String) -> Void,
        onComplete: @escaping (Result<String, Error>) -> Void
    ) {
        // Initialize provider if needed
        if baseLLMProvider == nil {
            initialize()
        }
        
        guard let provider = baseLLMProvider else {
            onComplete(.failure(NSError(domain: "LLMRequestService", code: 1000, 
                                      userInfo: [NSLocalizedDescriptionKey: "OpenRouter provider not initialized"])))
            return
        }
        
        // Get current model
        let currentModel = OpenAIModelFetcher.getPreferredModelString()
        
        // Clear context if starting new conversation
        if isNewConversation {
            ConversationContextManager.shared.clearContext(for: resume.id, type: .resume)
        }
        
        // Get or create context
        let context = ConversationContextManager.shared.getOrCreateContext(for: resume.id, type: .resume)
        
        // Get existing messages and convert to AppLLMMessage format
        let existingMessages = ConversationContextManager.shared.getMessages(for: context)
        var appMessages = Array<AppLLMMessage>.fromChatMessages(existingMessages)
        
        // Add system prompt if this is first message or no system message exists
        if appMessages.isEmpty || appMessages.first?.role != .system {
            if let systemPrompt = systemPrompt {
                let systemMessage = AppLLMMessage(role: .system, text: systemPrompt)
                // Add to context
                ConversationContextManager.shared.addMessage(systemMessage.toChatMessage(), to: context)
                // Add to app messages
                appMessages.insert(systemMessage, at: 0)
            }
        }
        
        // Create user message with optional image
        let userMessageContent: [AppLLMMessageContentPart]
        if let image = base64Image {
            userMessageContent = [
                .text(userMessage),
                .imageUrl(base64Data: image, mimeType: "image/png")
            ]
        } else {
            userMessageContent = [.text(userMessage)]
        }
        
        // Create user message
        let userAppMessage = AppLLMMessage(role: .user, contentParts: userMessageContent)
        
        // Add to context
        ConversationContextManager.shared.addMessage(userAppMessage.toChatMessage(), to: context)
        
        // Add to app messages
        appMessages.append(userAppMessage)
        
        // Create query
        let query = AppLLMQuery(
            messages: appMessages,
            modelIdentifier: currentModel,
            temperature: 1.0
        )
        
        let requestID = UUID()
        currentRequestID = requestID
        
        Task {
            do {
                // Execute query
                let response = try await provider.executeQuery(query)
                
                guard self.currentRequestID == requestID else { return }
                
                // Extract response content
                let responseText: String
                switch response {
                case .text(let text):
                    responseText = text
                case .structured(let data):
                    responseText = String(data: data, encoding: .utf8) ?? ""
                }
                
                // Create assistant message
                let assistantMessage = AppLLMMessage(role: .assistant, text: responseText)
                
                // Save assistant response to context
                await MainActor.run {
                    ConversationContextManager.shared.addMessage(assistantMessage.toChatMessage(), to: context)
                    onProgress(responseText)
                    onComplete(.success(responseText))
                }
            } catch {
                guard self.currentRequestID == requestID else { return }
                await MainActor.run {
                    Logger.debug("Error in sendResumeConversationRequest: \(error.localizedDescription)")
                    onComplete(.failure(error))
                }
            }
        }
    }
    
    /// Sends a conversational request with context management for Cover Letter chat
    @MainActor
    func sendCoverLetterConversationRequest(
        coverLetter: CoverLetter,
        userMessage: String,
        systemPrompt: String?,
        base64Image: String? = nil,
        isNewConversation: Bool = false,
        onProgress: @escaping (String) -> Void,
        onComplete: @escaping (Result<String, Error>) -> Void
    ) {
        // Initialize provider if needed
        if baseLLMProvider == nil {
            initialize()
        }
        
        guard let provider = baseLLMProvider else {
            onComplete(.failure(NSError(domain: "LLMRequestService", code: 1000, 
                                      userInfo: [NSLocalizedDescriptionKey: "OpenRouter provider not initialized"])))
            return
        }
        
        // Get current model
        let currentModel = OpenAIModelFetcher.getPreferredModelString()
        
        // Clear context if starting new conversation
        if isNewConversation {
            ConversationContextManager.shared.clearContext(for: coverLetter.id, type: .coverLetter)
        }
        
        // Get or create context
        let context = ConversationContextManager.shared.getOrCreateContext(for: coverLetter.id, type: .coverLetter)
        
        // Get existing messages and convert to AppLLMMessage format
        let existingMessages = ConversationContextManager.shared.getMessages(for: context)
        var appMessages = Array<AppLLMMessage>.fromChatMessages(existingMessages)
        
        // Add system prompt if needed
        if appMessages.isEmpty || appMessages.first?.role != .system {
            if let systemPrompt = systemPrompt {
                let systemMessage = AppLLMMessage(role: .system, text: systemPrompt)
                // Add to context
                ConversationContextManager.shared.addMessage(systemMessage.toChatMessage(), to: context)
                // Add to app messages
                appMessages.insert(systemMessage, at: 0)
            }
        }
        
        // Create user message with optional image
        let userMessageContent: [AppLLMMessageContentPart]
        if let image = base64Image {
            userMessageContent = [
                .text(userMessage),
                .imageUrl(base64Data: image, mimeType: "image/png")
            ]
        } else {
            userMessageContent = [.text(userMessage)]
        }
        
        // Create user message
        let userAppMessage = AppLLMMessage(role: .user, contentParts: userMessageContent)
        
        // Add to context
        ConversationContextManager.shared.addMessage(userAppMessage.toChatMessage(), to: context)
        
        // Add to app messages
        appMessages.append(userAppMessage)
        
        // Create query
        let query = AppLLMQuery(
            messages: appMessages,
            modelIdentifier: currentModel,
            temperature: 1.0
        )
        
        let requestID = UUID()
        currentRequestID = requestID
        
        Task {
            do {
                // Execute query
                let response = try await provider.executeQuery(query)
                
                guard self.currentRequestID == requestID else { return }
                
                // Extract response content
                let responseText: String
                switch response {
                case .text(let text):
                    responseText = text
                case .structured(let data):
                    responseText = String(data: data, encoding: .utf8) ?? ""
                }
                
                // Create assistant message
                let assistantMessage = AppLLMMessage(role: .assistant, text: responseText)
                
                // Save assistant response to context
                await MainActor.run {
                    ConversationContextManager.shared.addMessage(assistantMessage.toChatMessage(), to: context)
                    onProgress(responseText)
                    onComplete(.success(responseText))
                }
            } catch {
                guard self.currentRequestID == requestID else { return }
                await MainActor.run {
                    Logger.debug("Error in sendCoverLetterConversationRequest: \(error.localizedDescription)")
                    onComplete(.failure(error))
                }
            }
        }
    }
    
    // MARK: - Image Support Helpers
    
    /// Creates an AppLLMMessage with image support
    /// - Parameters:
    ///   - role: The message role
    ///   - text: The text content
    ///   - base64Image: Optional base64-encoded image
    /// - Returns: AppLLMMessage with image support
    static func createMessage(role: AppLLMMessage.Role, text: String, base64Image: String? = nil) -> AppLLMMessage {
        if let imageData = base64Image {
            return AppLLMMessage(role: role, contentParts: [
                .text(text),
                .imageUrl(base64Data: imageData, mimeType: "image/png")
            ])
        } else {
            return AppLLMMessage(role: role, text: text)
        }
    }
    
    /// Cancels the current request
    func cancelRequest() {
        currentRequestID = nil // This will cause ongoing callbacks to be ignored
    }
}