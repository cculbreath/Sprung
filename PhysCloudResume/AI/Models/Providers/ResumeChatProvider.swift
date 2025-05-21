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
        let providerType = appState.settings.preferredLLMProvider
        self.appLLMClient = AppLLMClientFactory.createClient(for: providerType, appState: appState)
    }
    
    /// Initialize with a specific app LLM client
    /// - Parameter client: A client conforming to AppLLMClientProtocol
    init(client: AppLLMClientProtocol) {
        self.appLLMClient = client
    }
    
    /// Direct initializer with OpenAI client (adapted to the AppLLMClientProtocol interface)
    /// - Parameter client: An OpenAI client conforming to OpenAIClientProtocol
    init(client: OpenAIClientProtocol) {
        // Create a direct adapter that implements the AppLLMClientProtocol interface
        self.appLLMClient = DirectOpenAIAdapter(client: client)
    }
    
    /// Direct adapter for OpenAIClientProtocol that implements AppLLMClientProtocol
    /// This eliminates the need for the LegacyOpenAIAdapterWrapper
    private class DirectOpenAIAdapter: AppLLMClientProtocol {
        private let openAIClient: OpenAIClientProtocol
        
        init(client: OpenAIClientProtocol) {
            self.openAIClient = client
        }
        
        func executeQuery(_ query: AppLLMQuery) async throws -> AppLLMResponse {
            // Convert AppLLMMessages to ChatMessages
            let chatMessages = query.messages.toChatMessages()
            
            // Check if we need to handle structured output
            if let responseType = query.desiredResponseType {
                if responseType == RevisionsContainer.self {
                    do {
                        // First try with structured output - this might fail with newer models
                        Logger.debug("🔄 Attempting structured output with \(query.modelIdentifier)")
                        
                        let response = try await openAIClient.sendChatCompletionWithStructuredOutput(
                            messages: chatMessages,
                            model: query.modelIdentifier,
                            temperature: query.temperature,
                            structuredOutputType: RevisionsContainer.self
                        )
                        
                        // Convert to JSON data
                        let encoder = JSONEncoder()
                        let data = try encoder.encode(response)
                        Logger.debug("✅ Structured output successful")
                        return .structured(data)
                    } catch {
                        // If structured output fails, try regular completion with JSON mode
                        Logger.error("❌ Structured output failed: \(error.localizedDescription). Falling back to regular completion with JSON mode.")
                        
                        // Add a specific instruction about the expected format to help the model
                        var messagesWithInstruction = chatMessages
                        let lastUserMessageIndex = messagesWithInstruction.lastIndex { $0.role == .user }
                        
                        if let lastIndex = lastUserMessageIndex {
                            // Append instructions to the user message
                            let originalContent = messagesWithInstruction[lastIndex].content
                            let enhancedContent = """
                            \(originalContent)
                            
                            IMPORTANT: Return a JSON object with this exact structure:
                            {
                              "revArray": [
                                {
                                  "id": "string",
                                  "oldValue": "string",
                                  "newValue": "string",
                                  "valueChanged": boolean,
                                  "why": "string",
                                  "isTitleNode": boolean,
                                  "treePath": "string"
                                }
                              ]
                            }
                            """
                            messagesWithInstruction[lastIndex] = ChatMessage(role: .user, content: enhancedContent)
                        }
                        
                        // Try with explicit JSON response format
                        Logger.debug("🔄 Attempting with explicit JSON format")
                        let response = try await openAIClient.sendChatCompletionAsync(
                            messages: messagesWithInstruction,
                            model: query.modelIdentifier,
                            responseFormat: .jsonObject,
                            temperature: query.temperature
                        )
                        
                        Logger.debug("📊 Received JSON response: \(response.content.prefix(100))...")
                        
                        // Try to extract JSON from the response content
                        let content = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                        
                        // Check if content starts with a JSON object
                        if content.starts(with: "{") && content.contains("revArray") {
                            if let data = content.data(using: .utf8) {
                                // Attempt to decode it directly
                                do {
                                    Logger.debug("🔄 Attempting to directly decode JSON response")
                                    // Try parsing as RevisionsContainer first
                                    let decoder = JSONDecoder()
                                    let _ = try decoder.decode(RevisionsContainer.self, from: data)
                                    
                                    Logger.debug("✅ Successfully decoded JSON response")
                                    return .structured(data)
                                } catch {
                                    Logger.error("⚠️ Decoding error: \(error.localizedDescription)")
                                    // Return raw JSON data (structuring will be attempted again in processResumeInteraction)
                                    return .structured(data)
                                }
                            } else {
                                Logger.error("⚠️ Failed to convert response to data")
                                return .text(content)
                            }
                        } else {
                            Logger.error("⚠️ Response not in expected JSON format")
                            return .text(content)
                        }
                    }
                } else if responseType == BestCoverLetterResponse.self {
                    // Handle BestCoverLetterResponse in a similar way
                    do {
                        let response = try await openAIClient.sendChatCompletionWithStructuredOutput(
                            messages: chatMessages,
                            model: query.modelIdentifier,
                            temperature: query.temperature,
                            structuredOutputType: BestCoverLetterResponse.self
                        )
                        
                        let encoder = JSONEncoder()
                        let data = try encoder.encode(response)
                        return .structured(data)
                    } catch {
                        // Fallback to regular completion
                        Logger.error("❌ Structured output failed for BestCoverLetterResponse: \(error.localizedDescription)")
                        
                        let response = try await openAIClient.sendChatCompletionAsync(
                            messages: chatMessages,
                            model: query.modelIdentifier,
                            responseFormat: .jsonObject,
                            temperature: query.temperature
                        )
                        
                        if let data = response.content.data(using: .utf8) {
                            return .structured(data)
                        } else {
                            return .text(response.content)
                        }
                    }
                } else {
                    // For other types, use regular completion with JSON mode
                    let response = try await openAIClient.sendChatCompletionAsync(
                        messages: chatMessages,
                        model: query.modelIdentifier,
                        responseFormat: .jsonObject,
                        temperature: query.temperature
                    )
                    
                    if let data = response.content.data(using: .utf8) {
                        return .structured(data)
                    } else {
                        return .text(response.content)
                    }
                }
            } else {
                // For regular text output, use standard completion
                let response = try await openAIClient.sendChatCompletionAsync(
                    messages: chatMessages,
                    model: query.modelIdentifier,
                    responseFormat: nil,
                    temperature: query.temperature
                )
                
                return .text(response.content)
            }
        }
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
                                Logger.debug("🔄 Attempting to decode structured data of length: \(data.count)")
                                if let debugString = String(data: data, encoding: .utf8) {
                                    Logger.debug("📝 JSON content preview: \(String(debugString.prefix(200)))...")
                                }
                                
                                // Save debug JSON for investigation if enabled
                                if UserDefaults.standard.bool(forKey: "saveDebugPrompts") {
                                    saveMessageToDebugFile(String(data: data, encoding: .utf8) ?? "", fileName: "structured_response_debug.json")
                                }
                                
                                let decoder = JSONDecoder()
                                
                                // First try to parse directly as RevisionsContainer
                                let decodedObject: RevisionsContainer
                                do {
                                    decodedObject = try decoder.decode(RevisionsContainer.self, from: data)
                                    Logger.debug("✅ Successfully decoded RevisionsContainer with \(decodedObject.revArray.count) revision nodes")
                                } catch let containerError {
                                    Logger.debug("⚠️ Failed to decode as RevisionsContainer: \(containerError.localizedDescription)")
                                    
                                    // Try to extract revArray from a wrapper object in case API wrapped the response
                                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                                        // Log available keys for debugging
                                        Logger.debug("🔍 JSON keys found: \(json.keys.joined(separator: ", "))")
                                        
                                        // Check if there's a choices array with content (OpenAI format)
                                        if let choices = json["choices"] as? [[String: Any]], 
                                           let firstChoice = choices.first,
                                           let message = firstChoice["message"] as? [String: Any],
                                           let content = message["content"] as? String,
                                           let contentData = content.data(using: .utf8) {
                                            
                                            Logger.debug("🔄 Found 'choices' array with content, attempting to parse")
                                            // Try to parse the content as JSON
                                            if let contentJson = try? JSONSerialization.jsonObject(with: contentData) as? [String: Any],
                                               let revArray = contentJson["revArray"] as? [[String: Any]] {
                                                
                                                // We found revArray in the content, convert to data and decode
                                                let revArrayData = try JSONSerialization.data(withJSONObject: ["revArray": revArray])
                                                decodedObject = try decoder.decode(RevisionsContainer.self, from: revArrayData)
                                                Logger.debug("✅ Successfully extracted and decoded revArray from choices content")
                                            } else {
                                                // Try to decode the entire content string as RevisionsContainer
                                                decodedObject = try decoder.decode(RevisionsContainer.self, from: contentData)
                                                Logger.debug("✅ Successfully decoded content string as RevisionsContainer")
                                            }
                                        } else {
                                            // Try to check for a top-level revArray directly
                                            if let revArray = json["revArray"] as? [[String: Any]] {
                                                let recreatedData = try JSONSerialization.data(withJSONObject: ["revArray": revArray])
                                                decodedObject = try decoder.decode(RevisionsContainer.self, from: recreatedData)
                                                Logger.debug("✅ Successfully extracted revArray from top level")
                                            } else {
                                                throw containerError // Original error if nothing worked
                                            }
                                        }
                                    } else {
                                        throw containerError // Rethrow if we couldn't parse as JSON
                                    }
                                }
                                
                                await coordinator.resumeWithValue(decodedObject, continuation: continuation)
                            } catch {
                                Logger.error("❌ Final decoding error: \(error.localizedDescription)")
                                await coordinator.resumeWithError(AppLLMError.decodingFailed(error), continuation: continuation)
                            }
                        case .text(let text):
                            // Try to decode the text as JSON
                            Logger.debug("🔄 Attempting to decode text response: \(String(text.prefix(100)))...")
                            
                            // Save debug text for investigation if enabled
                            if UserDefaults.standard.bool(forKey: "saveDebugPrompts") {
                                saveMessageToDebugFile(text, fileName: "text_response_debug.txt")
                            }
                            
                            if let data = text.data(using: .utf8) {
                                do {
                                    // First try to parse as is
                                    let decodedObject = try JSONDecoder().decode(RevisionsContainer.self, from: data)
                                    Logger.debug("✅ Successfully decoded text as RevisionsContainer")
                                    await coordinator.resumeWithValue(decodedObject, continuation: continuation)
                                } catch {
                                    Logger.debug("⚠️ Failed direct text decoding: \(error.localizedDescription)")
                                    
                                    // Try to extract JSON from the text with a more lenient approach
                                    let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if let jsonStart = trimmedText.range(of: "{"),
                                       let jsonEnd = trimmedText.range(of: "}", options: .backwards) {
                                        let jsonRange = jsonStart.lowerBound..<jsonEnd.upperBound
                                        let jsonString = String(trimmedText[jsonRange])
                                        
                                        if let jsonData = jsonString.data(using: .utf8) {
                                            do {
                                                // Try to parse extracted JSON
                                                let decodedObject = try JSONDecoder().decode(RevisionsContainer.self, from: jsonData)
                                                Logger.debug("✅ Successfully decoded extracted JSON")
                                                await coordinator.resumeWithValue(decodedObject, continuation: continuation)
                                            } catch {
                                                // If that fails, create an empty response to prevent app crash
                                                Logger.debug("⚠️ Creating empty fallback response")
                                                let fallbackContainer = RevisionsContainer(revArray: [])
                                                await coordinator.resumeWithValue(fallbackContainer, continuation: continuation)
                                            }
                                        } else {
                                            Logger.debug("⚠️ Creating empty fallback response after JSON extraction failed")
                                            let fallbackContainer = RevisionsContainer(revArray: [])
                                            await coordinator.resumeWithValue(fallbackContainer, continuation: continuation)
                                        }
                                    } else {
                                        Logger.debug("⚠️ Creating empty fallback response after JSON extraction failed")
                                        let fallbackContainer = RevisionsContainer(revArray: [])
                                        await coordinator.resumeWithValue(fallbackContainer, continuation: continuation)
                                    }
                                }
                            } else {
                                Logger.debug("⚠️ Creating empty fallback response after text->data conversion failed")
                                let fallbackContainer = RevisionsContainer(revArray: [])
                                await coordinator.resumeWithValue(fallbackContainer, continuation: continuation) 
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

