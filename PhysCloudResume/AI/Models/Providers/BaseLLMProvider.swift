import Foundation
import SwiftUI
import SwiftOpenAI

/// Clean adapter layer for LLM provider interactions
/// Provides provider-agnostic interface using SwiftOpenAI types
@Observable
class BaseLLMProvider {
    // MARK: - Properties
    
    /// The OpenRouter client for API calls
    private(set) var openRouterClient: OpenAIService?
    
    /// The app state for accessing configuration
    internal var appState: AppState?
    
    // Conversation history
    var conversationHistory: [LLMMessage] = []
    
    // Error handling
    var errorMessage: String = ""
    
    // MARK: - Initializers
    
    /// Initialize with AppState to create the OpenRouter client
    /// - Parameter appState: The application state
    init(appState: AppState) {
        self.appState = appState
        
        // Create OpenRouter client if API key is available
        let apiKey = UserDefaults.standard.string(forKey: "openRouterApiKey") ?? ""
        if !apiKey.isEmpty {
            self.openRouterClient = OpenAIServiceFactory.service(
                apiKey: apiKey,
                overrideBaseURL: "https://openrouter.ai/api/v1"
            )
            Logger.debug("🔄 BaseLLMProvider initialized with OpenRouter client")
        } else {
            Logger.warning("⚠️ BaseLLMProvider initialized without API key")
        }
    }
    
    // MARK: - Core Methods
    
    /// Initialize a new conversation with system and user messages
    /// - Parameters:
    ///   - systemPrompt: The system prompt to use
    ///   - userPrompt: The initial user prompt
    /// - Returns: The conversation history after initialization
    func initializeConversation(systemPrompt: String, userPrompt: String) -> [LLMMessage] {
        // Clear existing conversation history
        conversationHistory = []
        
        // Add system message
        conversationHistory.append(LLMMessage.text(role: .system, content: systemPrompt))
        
        // Add user message
        conversationHistory.append(LLMMessage.text(role: .user, content: userPrompt))
        
        return conversationHistory
    }
    
    /// Execute a query using the OpenRouter client
    /// - Parameter parameters: The ChatCompletionParameters to execute
    /// - Returns: The response from the LLM
    func executeQuery(_ parameters: ChatCompletionParameters) async throws -> LLMResponse {
        guard let client = openRouterClient else {
            errorMessage = "OpenRouter client not configured"
            throw NSError(domain: "BaseLLMProvider", code: 1, userInfo: [NSLocalizedDescriptionKey: errorMessage])
        }
        
        do {
            let response = try await client.startChat(parameters: parameters)
            return response
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }
}