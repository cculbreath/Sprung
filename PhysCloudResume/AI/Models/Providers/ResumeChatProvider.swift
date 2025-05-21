//
//  ResumeChatProvider.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 9/1/24.
//  Updated by Christopher Culbreath on 5/20/25.
//

import Foundation
import PDFKit
import AppKit
import SwiftData
import SwiftUI

/// Helper for handling resume chat functionality

@Observable
final class ResumeChatProvider {
    // The LLM client that will be used for API calls
    private let appLLMClient: AppLLMClientProtocol
    
    // Message tracking properties
    private var streamTask: Task<Void, Never>?
    var message: String = ""
    var messages: [String] = []
    
    // Conversation history
    var conversationHistory: [AppLLMMessage] = []
    
    // Legacy conversation tracking (for compatibility)
    var genericMessages: [ChatMessage] = []
    
    // Error handling and state
    var errorMessage: String = ""
    var lastRevNodeArray: [ProposedRevisionNode] = []
    
    // Track the last model used to know when to switch clients
    var lastModelUsed: String = ""

    // MARK: - Initializers

    /// Initialize with an app state to create the appropriate LLM client
    /// - Parameter appState: The application state
    init(appState: AppState) {
        let providerType = AIModels.Provider.openai // Default to OpenAI initially
        self.appLLMClient = AppLLMClientFactory.createClient(for: providerType, appState: appState)
    }
    
    /// Initialize with a specific app LLM client
    /// - Parameter client: A client conforming to AppLLMClientProtocol
    init(client: AppLLMClientProtocol) {
        self.appLLMClient = client
    }
    
    /// Legacy initializer with OpenAI client (for backward compatibility)
    /// - Parameter client: An OpenAI client conforming to OpenAIClientProtocol
    init(client: OpenAIClientProtocol) {
        // Create an adapter that wraps the legacy client
        let adapter = LegacyOpenAIAdapterWrapper(client: client)
        self.appLLMClient = adapter
    }

    // MARK: - Public Methods

    // Actor to safely coordinate continuations and prevent multiple resumes
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

    /// Process a resume interaction using the unified AppLLMClientProtocol
    /// - Parameters:
    ///   - newUserInput: Optional new user input (if not an initial query)
    ///   - isInitialQuery: Whether this is the first query in a conversation
    ///   - resumeDataForPrompt: The resume data for the prompt (required for initial query)
    /// - Returns: The revisions container with suggested changes
    func processResumeInteraction(
        newUserInput: String?,
        isInitialQuery: Bool,
        resumeDataForPrompt: String
    ) async throws -> RevisionsContainer {
        // Clear previous error message before starting
        errorMessage = ""
        
        // Initialize or update conversation history
        if isInitialQuery {
            // Start a new conversation with system and user messages
            conversationHistory = [
                AppLLMMessage(role: .system, text: "You are a helpful resume assistant..."),
                AppLLMMessage(role: .user, text: resumeDataForPrompt)
            ]
        } else if let userInput = newUserInput {
            // Add new user message to existing conversation
            conversationHistory.append(AppLLMMessage(role: .user, text: userInput))
        }
        
        // Get model identifier
        let modelIdentifier = OpenAIModelFetcher.getPreferredModelString()
        
        // Create query for structured output
        let query = AppLLMQuery(
            messages: conversationHistory,
            modelIdentifier: modelIdentifier,
            temperature: 0.5,
            responseType: RevisionsContainer.self
        )
        
        // Create coordinator for safe continuation resumption
        let coordinator = ContinuationCoordinator()
        
        // Timeout error for long-running requests
        let timeoutError = NSError(
            domain: "ResumeChatProviderError",
            code: -1001,
            userInfo: [NSLocalizedDescriptionKey: "API request timed out. Please try again."]
        )
        
        do {
            // Execute the LLM query using our unified interface
            let response = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<RevisionsContainer, Error>) in
                let apiTask = Task {
                    do {
                        let result = try await appLLMClient.executeQuery(query)
                        
                        // Handle the structured output
                        switch result {
                        case .structured(let data):
                            do {
                                let decodedObject = try JSONDecoder().decode(RevisionsContainer.self, from: data)
                                await coordinator.resumeWithValue(decodedObject, continuation: continuation)
                            } catch {
                                await coordinator.resumeWithError(AppLLMError.decodingFailed(error), continuation: continuation)
                            }
                        case .text(let text):
                            // Try to decode the text as JSON
                            if let data = text.data(using: .utf8) {
                                do {
                                    let decodedObject = try JSONDecoder().decode(RevisionsContainer.self, from: data)
                                    await coordinator.resumeWithValue(decodedObject, continuation: continuation)
                                } catch {
                                    await coordinator.resumeWithError(AppLLMError.decodingFailed(error), continuation: continuation)
                                }
                            } else {
                                await coordinator.resumeWithError(AppLLMError.unexpectedResponseFormat, continuation: continuation)
                            }
                        }
                    } catch {
                        await coordinator.resumeWithError(error, continuation: continuation)
                    }
                }
                
                // Set up a timeout task
                Task {
                    try? await Task.sleep(nanoseconds: 500_000_000_000) // 500s timeout
                    if !apiTask.isCancelled {
                        apiTask.cancel()
                        await coordinator.resumeWithError(timeoutError, continuation: continuation)
                    }
                }
            }
            
            // Convert structured response to JSON for compatibility with existing code
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonData = try encoder.encode(response)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "{\"revArray\": []}"
            
            // Store the JSON string in messages array
            self.messages = [jsonString]
            
            if self.messages.isEmpty {
                throw NSError(
                    domain: "ResumeChatProviderError",
                    code: 1002,
                    userInfo: [NSLocalizedDescriptionKey: "No response content received from AI service."]
                )
            }
            
            // Get the revision nodes directly from the structured response
            lastRevNodeArray = response.revArray
            
            // Update conversation history with assistant response
            conversationHistory.append(AppLLMMessage(role: .assistant, text: jsonString))
            
            // Update legacy genericMessages for backward compatibility
            genericMessages = conversationHistory.toChatMessages()
            
            return response
            
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }
    
    /// Legacy method for backwards compatibility
    /// Redirects to the new processResumeInteraction method
    func startChat(
        messages: [ChatMessage],
        resume: Resume? = nil,
        continueConversation: Bool = false
    ) async throws {
        // Convert legacy ChatMessages to AppLLMMessages
        conversationHistory = Array<AppLLMMessage>.fromChatMessages(messages)
        
        // Extract resume data from user message if this is an initial query
        let isInitialQuery = !continueConversation && conversationHistory.count <= 2
        let resumeData = isInitialQuery ? 
            conversationHistory.first(where: { $0.role == .user })?.contentParts.first.flatMap { 
                if case let .text(content) = $0 { return content } else { return nil }
            } ?? "" : ""
        
        // Process the interaction using our new method
        _ = try await processResumeInteraction(
            newUserInput: nil,
            isInitialQuery: isInitialQuery,
            resumeDataForPrompt: resumeData
        )
    }

    // MARK: - Conversational Methods (ChatCompletions API)
    
    /// Starts a new conversation for resume analysis with ChatCompletions API
    /// - Parameters:
    ///   - resume: The resume to analyze
    ///   - customInstructions: Optional custom instructions for the analysis
    ///   - onProgress: Progress callback for streaming responses
    ///   - onComplete: Completion callback with result
    @MainActor
    func startNewResumeConversation(
        resume: Resume,
        customInstructions: String = "",
        onProgress: @escaping (String) -> Void = { _ in },
        onComplete: @escaping (Result<String, Error>) -> Void = { _ in }
    ) {
        // Create a query to get the system prompt and context
        let query = ResumeApiQuery(resume: resume)
        
        // Build system prompt from the query
        var systemPrompt = query.genericSystemMessage.content
        if !customInstructions.isEmpty {
            systemPrompt += "\n\nAdditional Instructions: \(customInstructions)"
        }
        
        let userMessage = "Please analyze this resume and provide detailed feedback for improvement."
        
        LLMRequestService.shared.sendResumeConversationRequest(
            resume: resume,
            userMessage: userMessage,
            systemPrompt: systemPrompt,
            isNewConversation: true,
            onProgress: onProgress,
            onComplete: onComplete
        )
    }
    
    /// Continues an existing conversation for the resume
    /// - Parameters:
    ///   - resume: The resume being discussed
    ///   - userMessage: The user's message to continue the conversation
    ///   - onProgress: Progress callback for streaming responses
    ///   - onComplete: Completion callback with result
    @MainActor
    func continueResumeConversation(
        resume: Resume,
        userMessage: String,
        onProgress: @escaping (String) -> Void = { _ in },
        onComplete: @escaping (Result<String, Error>) -> Void = { _ in }
    ) {
        LLMRequestService.shared.sendResumeConversationRequest(
            resume: resume,
            userMessage: userMessage,
            systemPrompt: nil, // System prompt already in context
            isNewConversation: false,
            onProgress: onProgress,
            onComplete: onComplete
        )
    }

    /// Helper method to save message content to debug file
    private func saveMessageToDebugFile(_ content: String, fileName: String) {
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

