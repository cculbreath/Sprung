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
    
    /// Initializes the LLM client for OpenAI
    @MainActor
    func initialize() {
        // Use OpenAI API key for all models
        let apiKey = UserDefaults.standard.string(forKey: "openAiApiKey") ?? "none"
        guard apiKey != "none" else { return }
        // Create a standard OpenAI client
        openAIClient = OpenAIClientFactory.createClient(apiKey: apiKey)
    }
    
    /// Checks if the currently selected model supports images
    func checkIfModelSupportsImages() -> Bool {
        let model = OpenAIModelFetcher.getPreferredModelString().lowercased()
        
        // For OpenAI models
        let openAIVisionModelsSubstrings = ["gpt-4o", "gpt-4-turbo", "gpt-4-vision", "gpt-4.1", "gpt-image", "o4", "cua"]
        return openAIVisionModelsSubstrings.contains { model.contains($0) }
    }

    /// Sends a standard LLM request with text-only content (migrated to ChatCompletions)
    @MainActor
    func sendTextRequest(
        promptText: String,
        model: String,
        onProgress: @escaping (String) -> Void,
        onComplete: @escaping (Result<ResponsesAPIResponse, Error>) -> Void
    ) {
        if openAIClient == nil { initialize() }
        guard let client = openAIClient else {
            onComplete(.failure(NSError(domain: "LLMRequestService", code: 1000, userInfo: [NSLocalizedDescriptionKey: "LLM client not initialized"])))
            return
        }
        
        let requestID = UUID(); currentRequestID = requestID
        
        Task {
            do {
                // Convert single text prompt to ChatCompletions format
                let messages = [ChatMessage(role: .user, content: promptText)]
                
                let response = try await client.sendChatCompletionAsync(
                    messages: messages,
                    model: model,
                    temperature: 1.0
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
                if openAIClient == nil {
                    await initialize()
                }
                guard let client = openAIClient else {
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
                
                let modelString = OpenAIModelFetcher.getPreferredModelString()
                
                // Use structured output if schema provided
                if schema != nil {
                    // For structured output with ChatCompletions, we need to parse the schema
                    // and use sendChatCompletionWithStructuredOutput if the type is known
                    
                    // For now, we'll use regular chat completion and let the client handle JSON parsing
                    // This maintains backward compatibility while using ChatCompletions
                    Logger.debug("Schema provided but using regular chat completion for backward compatibility")
                    let response = try await client.sendChatCompletionAsync(
                        messages: messages,
                        model: modelString,
                        temperature: 1.0
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
                        model: modelString,
                        temperature: 1.0
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
        if openAIClient == nil { initialize() }
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
                    model: OpenAIModelFetcher.getPreferredModelString(),
                    temperature: 1.0
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
        if openAIClient == nil { initialize() }
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
                    model: OpenAIModelFetcher.getPreferredModelString(),
                    temperature: 1.0
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
