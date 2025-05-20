// PhysCloudResume/AI/Models/Services/LLMRequestService.swift

import Foundation
import SwiftUI
import SwiftData

/// Service responsible for handling LLM API requests
class LLMRequestService: @unchecked Sendable {
    /// Shared instance of the service
    static let shared = LLMRequestService()
    
    private var openAIClient: OpenAIClientProtocol?
    private var currentRequestID: UUID?
    private let apiQueue = DispatchQueue(label: "com.physcloudresume.apirequest", qos: .userInitiated)
    
    // Private initializer for singleton pattern
    private init() {}
    
    /// Initializes the LLM client with the appropriate provider for the current model
    @MainActor
    func initialize() {
        // Simply call our updateClientForCurrentModel method
        updateClientForCurrentModel()
    }
    
    /// Updates the client for the current model - call this whenever the preferred model changes
    @MainActor
    func updateClientForCurrentModel() {
        // Get all API keys
        let openAIKey = UserDefaults.standard.string(forKey: "openAiApiKey") ?? "none"
        let claudeKey = UserDefaults.standard.string(forKey: "claudeApiKey") ?? "none"
        let grokKey = UserDefaults.standard.string(forKey: "grokApiKey") ?? "none"
        let geminiKey = UserDefaults.standard.string(forKey: "geminiApiKey") ?? "none"
        
        // Validate API keys
        let validatedOpenAIKey = ModelFilters.validateAPIKey(openAIKey, for: AIModels.Provider.openai)
        let validatedClaudeKey = ModelFilters.validateAPIKey(claudeKey, for: AIModels.Provider.claude)
        let validatedGrokKey = ModelFilters.validateAPIKey(grokKey, for: AIModels.Provider.grok)
        let validatedGeminiKey = ModelFilters.validateAPIKey(geminiKey, for: AIModels.Provider.gemini)
        
        // Create a dictionary of validated API keys by provider
        let apiKeys = [
            AIModels.Provider.openai: validatedOpenAIKey ?? "none",
            AIModels.Provider.claude: validatedClaudeKey ?? "none",
            AIModels.Provider.grok: validatedGrokKey ?? "none",
            AIModels.Provider.gemini: validatedGeminiKey ?? "none"
        ]
        
        // Get current model string
        let currentModel = OpenAIModelFetcher.getPreferredModelString()
        
        let provider = AIModels.providerForModel(currentModel)
        Logger.debug("🔄 Updating client for model: \(currentModel) (Provider: \(provider))")
        
        // Create client for the current model
        if let client = OpenAIClientFactory.createClientForModel(model: currentModel, apiKeys: apiKeys) {
            openAIClient = client
            Logger.debug("✅ Initialized client for model: \(currentModel)")
        } else if let validOpenAIKey = validatedOpenAIKey, let client = OpenAIClientFactory.createClient(apiKey: validOpenAIKey) {
            // Fallback to standard OpenAI client if we couldn't create one for the current model
            openAIClient = client
            Logger.debug("⚠️ Falling back to standard OpenAI client")
        } else {
            Logger.error("❌ Failed to initialize LLM client: No valid API keys available")
            openAIClient = nil
        }
    }
    
    /// Checks if the currently selected model supports images
    func checkIfModelSupportsImages() -> Bool {
        let model = OpenAIModelFetcher.getPreferredModelString().lowercased()
        
        let provider = AIModels.providerForModel(model)

        // For OpenAI models – all of the filtered models support images
        let openAIVisionModelsSubstrings = ["gpt-4o", "gpt-4-turbo", "gpt-4-vision", "gpt-4.1", "gpt-image", "o4", "cua"]

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
    /// input we transparently substitute a compatible model from the same provider.  This is
    /// currently only required for Grok where the dedicated vision model must be used.
    /// - Parameters:
    ///   - model: The user-selected model string.
    ///   - wantsImage: Boolean indicating whether the request includes an image.
    /// - Returns: A model string that is safe for the request.
    private static func modelForImageRequest(selectedModel model: String, wantsImage: Bool) -> String {
        guard wantsImage else { return model }

        let provider = AIModels.providerForModel(model)

        if provider == AIModels.Provider.grok {
            // If the chosen Grok model is not the vision capable one, switch to it.
            if !model.lowercased().contains("-vision") {
                return "grok-2-vision-1212"
            }
        }

        return model
    }

    /// Sends a standard LLM request with text-only content (migrated to ChatCompletions)
    @MainActor
    func sendTextRequest(
        promptText: String,
        model: String? = nil, // Make model parameter optional so we can use the default
        onProgress: @escaping (String) -> Void,
        onComplete: @escaping (Result<ResponsesAPIResponse, Error>) -> Void
    ) {
        // Use provided model or fall back to preferred model
        let modelToUse = model ?? OpenAIModelFetcher.getPreferredModelString()
        
        // Get all API keys
        let openAIKey = UserDefaults.standard.string(forKey: "openAiApiKey") ?? "none"
        let claudeKey = UserDefaults.standard.string(forKey: "claudeApiKey") ?? "none"
        let grokKey = UserDefaults.standard.string(forKey: "grokApiKey") ?? "none"
        let geminiKey = UserDefaults.standard.string(forKey: "geminiApiKey") ?? "none"
        
        // Create a dictionary of API keys by provider
        let apiKeys = [
            AIModels.Provider.openai: openAIKey,
            AIModels.Provider.claude: claudeKey,
            AIModels.Provider.grok: grokKey,
            AIModels.Provider.gemini: geminiKey
        ]
        
        // Create or update client for the specific model
        let client = OpenAIClientFactory.createClientForModel(model: modelToUse, apiKeys: apiKeys) ?? openAIClient
        
        guard let client = client else {
            onComplete(.failure(NSError(domain: "LLMRequestService", code: 1000, userInfo: [NSLocalizedDescriptionKey: "No LLM client available for model: \(modelToUse)"])))
            return
        }
        
        let requestID = UUID(); currentRequestID = requestID
        
        Task {
            do {
                // Convert single text prompt to ChatCompletions format
                let messages = [ChatMessage(role: .user, content: promptText)]
                
                let response = try await client.sendChatCompletionAsync(
                    messages: messages,
                    model: modelToUse,
                    responseFormat: nil,
                    temperature: nil
                )
                
                // Ensure request is still current
                guard self.currentRequestID == requestID else { return }
                
                onProgress(response.content)
                
                // Convert ChatCompletion response to ResponsesAPI format for backward compatibility
                let compatResponse = ResponsesAPIResponse(
                    id: response.id ?? UUID().uuidString,
                    content: response.content,
                    model: response.model
                )
                onComplete(.success(compatResponse))
            } catch {
                Logger.debug("Error in sendTextRequest: \(error.localizedDescription)")
                
                // Create user-friendly error message
                var userErrorMessage = "Error processing your request. "
                
                if let nsError = error as NSError? {
                    Logger.debug("Error domain: \(nsError.domain), code: \(nsError.code), userInfo: \(nsError.userInfo)")
                    
                    if nsError.domain == "OpenAIAPI" {
                        userErrorMessage += "API issue: \(nsError.localizedDescription)"
                    } else if nsError.domain.contains("URLError") && nsError.code == -1001 {
                        userErrorMessage += "Request timed out. Please check your network connection and try again."
                    } else if let errorInfo = nsError.userInfo[NSLocalizedDescriptionKey] as? String {
                        if errorInfo.contains("temperature") || errorInfo.contains("parameter") {
                            userErrorMessage = "Model compatibility issue: \(errorInfo). Please try a different model in Settings."
                        } else {
                            userErrorMessage += errorInfo
                        }
                    }
                }
                
                guard self.currentRequestID == requestID else { return }
                onComplete(.failure(NSError(
                    domain: "LLMRequestService",
                    code: 1100,
                    userInfo: [NSLocalizedDescriptionKey: userErrorMessage]
                )))
            }
        }
    }
    
    /// Sends a request that can include an image and/or JSON schema (migrated to ChatCompletions)
    func sendMixedRequest(
        promptText: String,
        base64Image: String?,
        schema: (name: String, jsonString: String)?,
        requestID: UUID = UUID(),
        onComplete: @escaping (Result<ResponsesAPIResponse, Error>) -> Void
    ) {
        currentRequestID = requestID
        
        Task {
            do {
                // Get all API keys
                let openAIKey = UserDefaults.standard.string(forKey: "openAiApiKey") ?? "none"
                let claudeKey = UserDefaults.standard.string(forKey: "claudeApiKey") ?? "none"
                let grokKey = UserDefaults.standard.string(forKey: "grokApiKey") ?? "none"
                let geminiKey = UserDefaults.standard.string(forKey: "geminiApiKey") ?? "none"
                
                // Validate API keys before using them
                let validatedOpenAIKey = ModelFilters.validateAPIKey(openAIKey, for: AIModels.Provider.openai)
                let validatedClaudeKey = ModelFilters.validateAPIKey(claudeKey, for: AIModels.Provider.claude)
                let validatedGrokKey = ModelFilters.validateAPIKey(grokKey, for: AIModels.Provider.grok)
                let validatedGeminiKey = ModelFilters.validateAPIKey(geminiKey, for: AIModels.Provider.gemini)
                
                // Create a dictionary of validated API keys by provider
                let apiKeys = [
                    AIModels.Provider.openai: validatedOpenAIKey ?? "none",
                    AIModels.Provider.claude: validatedClaudeKey ?? "none",
                    AIModels.Provider.grok: validatedGrokKey ?? "none",
                    AIModels.Provider.gemini: validatedGeminiKey ?? "none"
                ]
                
                // Log available keys (without revealing the entire keys)
                Logger.debug("🔑 Available API keys:")
                if let key = validatedOpenAIKey {
                    Logger.debug("✅ OpenAI: \(key.prefix(4))... (\(key.count) chars)")
                } else {
                    Logger.debug("❌ OpenAI: No valid key")
                }
                if let key = validatedClaudeKey {
                    Logger.debug("✅ Claude: \(key.prefix(4))... (\(key.count) chars)")
                } else {
                    Logger.debug("❌ Claude: No valid key")
                }
                if let key = validatedGeminiKey {
                    Logger.debug("✅ Gemini: \(key.prefix(4))... (\(key.count) chars)")
                } else {
                    Logger.debug("❌ Gemini: No valid key")
                }
                
                // Determine which model we will actually use for the request – we may need to
                // substitute a vision-capable variant if the selected model does not support
                // images.
                let selectedModel = OpenAIModelFetcher.getPreferredModelString()
                let currentModel = LLMRequestService.modelForImageRequest(selectedModel: selectedModel,
                                                                          wantsImage: base64Image != nil)
                
                // Create or update client for the selected model
                let client: OpenAIClientProtocol?
                if let modelClient = OpenAIClientFactory.createClientForModel(model: currentModel, apiKeys: apiKeys) {
                    client = modelClient
                } else if let existingClient = openAIClient {
                    client = existingClient
                } else {
                    // Initialize on MainActor and then get the client
                    await MainActor.run {
                        initialize()
                    }
                    // Now get the client after initialization (no mutation in concurrent code)
                    client = await MainActor.run { 
                        return self.openAIClient
                    }
                }
                
                guard let client = client else {
                    await MainActor.run {
                        onComplete(.failure(NSError(domain: "LLMRequestService", code: 1000, userInfo: [NSLocalizedDescriptionKey: "LLM client not initialized"])))
                    }
                    return
                }
                
                // Build messages array for ChatCompletions
                var messages: [ChatMessage] = []
                
                // For image requests, we need to properly include the image in the message
                if let image = base64Image {
                    // Add user message with both text and image
                    let userMessage = ChatMessage(role: .user, content: promptText, imageData: image)
                    messages.append(userMessage)
                } else {
                    // Text-only request
                    messages.append(ChatMessage(role: .user, content: promptText))
                }
                
                // Use structured output if schema provided
                if schema != nil {
                    // For structured output with ChatCompletions, we need to parse the schema
                    // and use sendChatCompletionWithStructuredOutput if the type is known
                    
                    // For now, we'll use regular chat completion and let the client handle JSON parsing
                    // This maintains backward compatibility while using ChatCompletions
                    Logger.debug("Schema provided but using regular chat completion for backward compatibility")
                    let response = try await client.sendChatCompletionAsync(
                        messages: messages,
                        model: currentModel,
                        responseFormat: nil,
                        temperature: nil
                    )
                    
                    // Note: For full structured output support, we would need to:
                    // 1. Determine the structured output type from the schema name
                    // 2. Call sendChatCompletionWithStructuredOutput with the proper type
                    // 3. Convert the structured response back to ResponsesAPIResponse format
                    
                    // Convert response for backward compatibility
                    let compatResponse = ResponsesAPIResponse(
                        id: response.id ?? UUID().uuidString,
                        content: response.content,
                        model: response.model
                    )
                    
                    await MainActor.run {
                        onComplete(.success(compatResponse))
                    }
                } else {
                    // Regular chat completion
                    let response = try await client.sendChatCompletionAsync(
                        messages: messages,
                        model: currentModel,
                        responseFormat: nil,
                        temperature: nil
                    )
                    
                    // Convert response for backward compatibility
                    let compatResponse = ResponsesAPIResponse(
                        id: response.id ?? UUID().uuidString,
                        content: response.content,
                        model: response.model
                    )
                    
                    await MainActor.run {
                        onComplete(.success(compatResponse))
                    }
                }
            } catch {
                await MainActor.run {
                    Logger.debug("Error in sendMixedRequest: \(error.localizedDescription)")
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
        // Get all API keys
        let openAIKey = UserDefaults.standard.string(forKey: "openAiApiKey") ?? "none"
        let claudeKey = UserDefaults.standard.string(forKey: "claudeApiKey") ?? "none"
        let grokKey = UserDefaults.standard.string(forKey: "grokApiKey") ?? "none"
        let geminiKey = UserDefaults.standard.string(forKey: "geminiApiKey") ?? "none"
        
        // Create a dictionary of API keys by provider
        let apiKeys = [
            AIModels.Provider.openai: openAIKey,
            AIModels.Provider.claude: claudeKey,
            AIModels.Provider.grok: grokKey,
            AIModels.Provider.gemini: geminiKey
        ]
        
        // Get current model string
        let currentModel = OpenAIModelFetcher.getPreferredModelString()
        
        // Create or update client for the selected model
        if let client = OpenAIClientFactory.createClientForModel(model: currentModel, apiKeys: apiKeys) {
            // Use the model-specific client
            openAIClient = client
        } else if openAIClient == nil {
            // Fallback to initializing standard OpenAI client
            initialize()
        }
        
        guard let client = openAIClient else {
            onComplete(.failure(NSError(domain: "LLMRequestService", code: 1000, userInfo: [NSLocalizedDescriptionKey: "LLM client not initialized"])))
            return
        }
        
        // Clear context if starting new conversation
        if isNewConversation {
            ConversationContextManager.shared.clearContext(for: resume.id, type: .resume)
        }
        
        // Get or create context
        let context = ConversationContextManager.shared.getOrCreateContext(for: resume.id, type: .resume)
        
        // Build messages array
        var messages = ConversationContextManager.shared.getMessages(for: context)
        
        // Add system prompt if this is first message or no system message exists
        if messages.isEmpty || messages.first?.role != .system {
            if let systemPrompt = systemPrompt {
                let systemMessage = ChatMessage(role: .system, content: systemPrompt)
                ConversationContextManager.shared.addMessage(systemMessage, to: context)
                messages.insert(systemMessage, at: 0)
            }
        }
        
        // Add user message with optional image
        let userChatMessage = LLMRequestService.createMessage(
            role: .user, 
            text: userMessage, 
            base64Image: base64Image
        )
        ConversationContextManager.shared.addMessage(userChatMessage, to: context)
        messages.append(userChatMessage)
        
        let requestID = UUID(); currentRequestID = requestID
        
        Task {
            do {
                let response = try await client.sendChatCompletionAsync(
                    messages: messages,
                    model: currentModel,
                    responseFormat: nil,
                    temperature: nil
                )
                
                guard self.currentRequestID == requestID else { return }
                
                // Save assistant response to context
                let assistantMessage = ChatMessage(role: .assistant, content: response.content)
                await MainActor.run {
                    ConversationContextManager.shared.addMessage(assistantMessage, to: context)
                }
                
                onProgress(response.content)
                onComplete(.success(response.content))
            } catch {
                guard self.currentRequestID == requestID else { return }
                Logger.debug("Error in sendResumeConversationRequest: \(error.localizedDescription)")
                onComplete(.failure(error))
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
        // Get all API keys
        let openAIKey = UserDefaults.standard.string(forKey: "openAiApiKey") ?? "none"
        let claudeKey = UserDefaults.standard.string(forKey: "claudeApiKey") ?? "none"
        let grokKey = UserDefaults.standard.string(forKey: "grokApiKey") ?? "none"
        let geminiKey = UserDefaults.standard.string(forKey: "geminiApiKey") ?? "none"
        
        // Create a dictionary of API keys by provider
        let apiKeys = [
            AIModels.Provider.openai: openAIKey,
            AIModels.Provider.claude: claudeKey,
            AIModels.Provider.grok: grokKey,
            AIModels.Provider.gemini: geminiKey
        ]
        
        // Get current model string
        let currentModel = OpenAIModelFetcher.getPreferredModelString()
        
        // Create or update client for the selected model
        if let client = OpenAIClientFactory.createClientForModel(model: currentModel, apiKeys: apiKeys) {
            // Use the model-specific client
            openAIClient = client
        } else if openAIClient == nil {
            // Fallback to initializing standard OpenAI client
            initialize()
        }
        
        guard let client = openAIClient else {
            onComplete(.failure(NSError(domain: "LLMRequestService", code: 1000, userInfo: [NSLocalizedDescriptionKey: "LLM client not initialized"])))
            return
        }
        
        // Clear context if starting new conversation
        if isNewConversation {
            ConversationContextManager.shared.clearContext(for: coverLetter.id, type: .coverLetter)
        }
        
        // Get or create context
        let context = ConversationContextManager.shared.getOrCreateContext(for: coverLetter.id, type: .coverLetter)
        
        // Build messages array
        var messages = ConversationContextManager.shared.getMessages(for: context)
        
        // Add system prompt if needed
        if messages.isEmpty || messages.first?.role != .system {
            if let systemPrompt = systemPrompt {
                let systemMessage = ChatMessage(role: .system, content: systemPrompt)
                ConversationContextManager.shared.addMessage(systemMessage, to: context)
                messages.insert(systemMessage, at: 0)
            }
        }
        
        // Add user message with optional image
        let userChatMessage = LLMRequestService.createMessage(
            role: .user, 
            text: userMessage, 
            base64Image: base64Image
        )
        ConversationContextManager.shared.addMessage(userChatMessage, to: context)
        messages.append(userChatMessage)
        
        let requestID = UUID(); currentRequestID = requestID
        
        Task {
            do {
                let response = try await client.sendChatCompletionAsync(
                    messages: messages,
                    model: currentModel,
                    responseFormat: nil,
                    temperature: nil
                )
                
                guard self.currentRequestID == requestID else { return }
                
                // Save assistant response to context
                let assistantMessage = ChatMessage(role: .assistant, content: response.content)
                await MainActor.run {
                    ConversationContextManager.shared.addMessage(assistantMessage, to: context)
                }
                
                onProgress(response.content)
                onComplete(.success(response.content))
            } catch {
                guard self.currentRequestID == requestID else { return }
                Logger.debug("Error in sendCoverLetterConversationRequest: \(error.localizedDescription)")
                onComplete(.failure(error))
            }
        }
    }
    
    // MARK: - Image Support Helpers
    
    /// Creates a ChatMessage with image support
    /// - Parameters:
    ///   - role: The message role
    ///   - text: The text content
    ///   - base64Image: Optional base64-encoded image
    /// - Returns: ChatMessage with image support
    static func createMessage(role: ChatMessage.ChatRole, text: String, base64Image: String? = nil) -> ChatMessage {
        if let imageData = base64Image {
            return ChatMessage(role: role, content: text, imageData: imageData)
        } else {
            return ChatMessage(role: role, content: text)
        }
    }
    
    /// Cancels the current request
    func cancelRequest() {
        currentRequestID = nil // This will cause ongoing callbacks to be ignored
    }
}
