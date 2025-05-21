//
//  BaseLLMProvider.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 5/20/25.
//

import Foundation
import SwiftUI

/// Base provider class for LLM interactions
/// Provides common functionality for all LLM provider implementations
@Observable
class BaseLLMProvider {
    // MARK: - Properties
    
    /// The LLM client that will be used for API calls
    private(set) var appLLMClient: AppLLMClientProtocol
    
    // Message tracking properties
    private var streamTask: Task<Void, Never>?
    var message: String = ""
    var messages: [String] = []
    
    // Conversation history
    var conversationHistory: [AppLLMMessage] = []
    
    // Error handling
    var errorMessage: String = ""
    
    // Track the last model used to know when to switch clients
    var lastModelUsed: String = ""
    
    // MARK: - Actor to safely coordinate continuations
    
    /// Actor to safely coordinate continuations and prevent multiple resumes
    private actor ContinuationCoordinator {
        private var hasResumed = false

        func resumeWithValue<T, E: Error>(_ value: T, continuation: CheckedContinuation<T, E>) {
            guard !hasResumed else { return }
            hasResumed = true
            continuation.resume(returning: value)
        }

        func resumeWithError<T, E: Error>(_ error: E, continuation: CheckedContinuation<T, E>) {
            guard !hasResumed else { return }
            hasResumed = true
            continuation.resume(throwing: error)
        }
    }
    
    // MARK: - Initializers
    
    /// Initialize with an app state to create the appropriate LLM client
    /// - Parameter appState: The application state
    init(appState: AppState) {
        let providerType = appState.settings.preferredLLMProvider
        self.appLLMClient = AppLLMClientFactory.createClient(for: providerType, appState: appState)
    }
    
    /// Initialize with a specific app LLM client
    /// - Parameter client: A client conforming to AppLLMClientProtocol
    init(client: AppLLMClientProtocol) {
        self.appLLMClient = client
    }
    
    // MARK: - Client Management
    
    /// Updates the LLM client based on the current model
    /// - Parameter appState: The application state
    func updateClientIfNeeded(appState: AppState) {
        let currentModel = OpenAIModelFetcher.getPreferredModelString()
        
        // Only update if the model has changed
        if lastModelUsed != currentModel {
            lastModelUsed = currentModel
            let providerType = AIModels.providerForModel(currentModel)
            appLLMClient = AppLLMClientFactory.createClient(for: providerType, appState: appState)
        }
    }
    
    // MARK: - Conversation Management
    
    /// Initializes a new conversation with system and user messages
    /// - Parameters:
    ///   - systemPrompt: The system prompt to use
    ///   - userPrompt: The initial user message
    /// - Returns: The updated conversation history
    func initializeConversation(systemPrompt: String, userPrompt: String) -> [AppLLMMessage] {
        // Start a new conversation with system and user messages
        conversationHistory = [
            AppLLMMessage(role: .system, text: systemPrompt),
            AppLLMMessage(role: .user, text: userPrompt)
        ]
        return conversationHistory
    }
    
    /// Adds a user message to the conversation
    /// - Parameter userInput: The user message to add
    /// - Returns: The updated conversation history
    func addUserMessage(_ userInput: String) -> [AppLLMMessage] {
        // Add new user message to existing conversation
        conversationHistory.append(AppLLMMessage(role: .user, text: userInput))
        return conversationHistory
    }
    
    /// Adds an assistant message to the conversation
    /// - Parameter assistantResponse: The assistant response to add
    /// - Returns: The updated conversation history
    func addAssistantMessage(_ assistantResponse: String) -> [AppLLMMessage] {
        // Add assistant response to existing conversation
        conversationHistory.append(AppLLMMessage(role: .assistant, text: assistantResponse))
        return conversationHistory
    }
    
    // MARK: - Query Execution
    
    /// Executes a query using the current LLM client
    /// - Parameter query: The query to execute
    /// - Returns: The response from the LLM
    func executeQuery(_ query: AppLLMQuery) async throws -> AppLLMResponse {
        do {
            return try await appLLMClient.executeQuery(query)
        } catch {
            // Log and rethrow the error
            errorMessage = error.localizedDescription
            Logger.error("Error executing query: \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Executes a query with timeout
    /// - Parameters:
    ///   - query: The query to execute
    ///   - timeoutSeconds: The timeout in seconds
    /// - Returns: The response from the LLM
    func executeQueryWithTimeout(_ query: AppLLMQuery, timeoutSeconds: Double = 120.0) async throws -> AppLLMResponse {
        // Create coordinator for safe continuation resumption
        let coordinator = ContinuationCoordinator()
        
        // Timeout error for long-running requests
        let timeoutError = NSError(
            domain: "BaseLLMProviderError",
            code: -1001,
            userInfo: [NSLocalizedDescriptionKey: "API request timed out. Please try again."]
        )
        
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<AppLLMResponse, Error>) in
            let apiTask = Task {
                do {
                    let result = try await appLLMClient.executeQuery(query)
                    await coordinator.resumeWithValue(result, continuation: continuation)
                } catch {
                    errorMessage = error.localizedDescription
                    await coordinator.resumeWithError(error, continuation: continuation)
                }
            }
            
            // Set up a timeout task
            let timeoutNanos = UInt64(timeoutSeconds * 1_000_000_000)
            Task {
                try? await Task.sleep(nanoseconds: timeoutNanos)
                if !apiTask.isCancelled {
                    apiTask.cancel()
                    errorMessage = timeoutError.localizedDescription
                    await coordinator.resumeWithError(timeoutError, continuation: continuation)
                }
            }
        }
    }
    
    // MARK: - Structured Output Handling
    
    /// Processes a structured response and extracts the decoded object
    /// - Parameters:
    ///   - response: The LLM response
    ///   - type: The expected type to decode
    /// - Returns: The decoded object
    func processStructuredResponse<T: Decodable>(_ response: AppLLMResponse, as type: T.Type) throws -> T {
        switch response {
        case .structured(let data):
            do {
                Logger.debug("🔄 Attempting to decode structured data of length: \(data.count)")
                if let debugString = String(data: data, encoding: .utf8) {
                    Logger.debug("📝 JSON content preview: \(String(debugString.prefix(200)))...")
                }
                
                // Try to decode the data
                let decoder = JSONDecoder()
                return try decoder.decode(T.self, from: data)
            } catch {
                Logger.error("❌ Decoding error: \(error.localizedDescription)")
                throw AppLLMError.decodingFailed(error)
            }
            
        case .text(let text):
            // Try to decode the text as JSON
            Logger.debug("🔄 Attempting to decode text response: \(String(text.prefix(100)))...")
            
            guard let data = text.data(using: .utf8) else {
                throw AppLLMError.unexpectedResponseFormat
            }
            
            do {
                // Try to decode the data
                let decoder = JSONDecoder()
                return try decoder.decode(T.self, from: data)
            } catch {
                Logger.error("❌ Text decoding error: \(error.localizedDescription)")
                throw AppLLMError.decodingFailed(error)
            }
        }
    }
    
    // MARK: - Utilities
    
    /// Saves message content to a debug file
    /// - Parameters:
    ///   - content: The content to save
    ///   - fileName: The name of the file
    func saveMessageToDebugFile(_ content: String, fileName: String) {
        // Check if debug prompt saving is enabled
        let saveDebugPrompts = UserDefaults.standard.bool(forKey: "saveDebugPrompts")
        
        // Only save if debug is enabled
        if saveDebugPrompts {
            let fileManager = FileManager.default
            let homeDirectoryURL = fileManager.homeDirectoryForCurrentUser
            let downloadsURL = homeDirectoryURL.appendingPathComponent("Downloads")
            let fileURL = downloadsURL.appendingPathComponent(fileName)
            
            do {
                try content.write(to: fileURL, atomically: true, encoding: .utf8)
                Logger.debug("Debug message content saved to: \(fileURL.path)")
            } catch {
                Logger.debug("Error saving debug message: \(error.localizedDescription)")
            }
        } else {
            // Log that we would have saved a debug file, but it's disabled
            Logger.debug("Debug message NOT saved (saveDebugPrompts disabled)")
        }
    }
}
