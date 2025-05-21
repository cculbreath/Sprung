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
final class ResumeChatProvider: BaseLLMProvider {
    // Legacy conversation tracking (for compatibility)
    var genericMessages: [ChatMessage] = []
    
    // Resume-specific state
    var lastRevNodeArray: [ProposedRevisionNode] = []

    // MARK: - Initializers

    /// Override initializer to include compatibility with older code
    /// - Parameter client: An OpenAI client conforming to OpenAIClientProtocol
    convenience init(client: OpenAIClientProtocol) {
        // Create an AppState for initialization
        let appState = AppState()
        
        // Initialize with the AppState - this will create the appropriate client
        self.init(appState: appState)
        
        // No explicit adapter needed - just keep self.appLLMClient as is
    }

    // MARK: - Resume-specific Methods

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
        
        do {
            // Execute the query with timeout using base class method
            let response = try await executeQueryWithTimeout(query)
            
            do {
                // Process the structured response using base class method
                let revisions = try processStructuredResponse(response, as: RevisionsContainer.self)
                
                // Convert structured response to JSON for compatibility with existing code
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let jsonData = try encoder.encode(revisions)
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
                lastRevNodeArray = revisions.revArray
                
                // Update conversation history with assistant response
                conversationHistory.append(AppLLMMessage(role: .assistant, text: jsonString))
                
                // Update legacy genericMessages for backward compatibility
                genericMessages = conversationHistory.map { MessageConverter.chatMessageFrom(appMessage: $0) }
                
                return revisions
            } catch {
                // If we couldn't decode the response, try a more lenient approach
                switch response {
                case .structured(let data):
                    if let jsonStr = String(data: data, encoding: .utf8) {
                        saveMessageToDebugFile(jsonStr, fileName: "failed_structured_response_debug.json")
                    }
                    
                    // Try to extract the revArray from the raw JSON
                    do {
                        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let revArray = json["revArray"] as? [[String: Any]] {
                            
                            // Create a minimal valid container with just the revArray
                            var container = RevisionsContainer(revArray: [])
                            
                            // Convert each rev dict to a ProposedRevisionNode
                            var nodes: [ProposedRevisionNode] = []
                            for rev in revArray {
                                if let id = rev["id"] as? String,
                                   let oldValue = rev["oldValue"] as? String,
                                   let newValue = rev["newValue"] as? String,
                                   let valueChanged = rev["valueChanged"] as? Bool,
                                   let why = rev["why"] as? String,
                                   let isTitleNode = rev["isTitleNode"] as? Bool,
                                   let treePath = rev["treePath"] as? String {
                                    
                                    // Create a dictionary representation of the node
                                    let nodeDict: [String: Any] = [
                                        "id": id,
                                        "oldValue": oldValue,
                                        "newValue": newValue,
                                        "valueChanged": valueChanged,
                                        "why": why,
                                        "isTitleNode": isTitleNode,
                                        "treePath": treePath
                                    ]
                                    
                                    // Convert to JSON
                                    let jsonData = try! JSONSerialization.data(withJSONObject: nodeDict)
                                    
                                    // Decode as ProposedRevisionNode
                                    let node = try! JSONDecoder().decode(ProposedRevisionNode.self, from: jsonData)
                                    
                                    nodes.append(node)
                                    nodes.append(node)
                                }
                            }
                            
                            // Update the container with the parsed nodes
                            container.revArray = nodes
                            lastRevNodeArray = nodes
                            
                            // Convert back to JSON for the conversation history
                            let encoder = JSONEncoder()
                            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                            let jsonData = try encoder.encode(container)
                            let jsonString = String(data: jsonData, encoding: .utf8) ?? "{\"revArray\": []}"
                            
                            // Store the JSON string in messages array
                            self.messages = [jsonString]
                            
                            // Update conversation history with assistant response
                            conversationHistory.append(AppLLMMessage(role: .assistant, text: jsonString))
                            
                            // Update legacy genericMessages
                            genericMessages = conversationHistory.map { MessageConverter.chatMessageFrom(appMessage: $0) }
                            
                            return container
                        }
                    } catch {
                        Logger.error("Failed to extract revArray from raw JSON: \(error.localizedDescription)")
                    }
                    
                case .text(let text):
                    saveMessageToDebugFile(text, fileName: "failed_text_response_debug.txt")
                    
                    // Try to find JSON in the text response
                    if let jsonStart = text.range(of: "{"),
                       let jsonEnd = text.range(of: "}", options: .backwards) {
                        
                        let jsonRange = jsonStart.lowerBound..<jsonEnd.upperBound
                        let jsonString = String(text[jsonRange])
                        
                        if let jsonData = jsonString.data(using: .utf8) {
                            do {
                                let container = try JSONDecoder().decode(RevisionsContainer.self, from: jsonData)
                                
                                // Store the JSON string in messages array
                                self.messages = [jsonString]
                                
                                // Update conversation history with assistant response
                                conversationHistory.append(AppLLMMessage(role: .assistant, text: jsonString))
                                
                                // Update legacy genericMessages
                                genericMessages = conversationHistory.map { MessageConverter.chatMessageFrom(appMessage: $0) }
                                
                                return container
                            } catch {
                                Logger.error("Failed to decode extracted JSON: \(error.localizedDescription)")
                            }
                        }
                    }
                }
                
                // Create a fallback empty response if all else fails
                Logger.debug("⚠️ Creating empty fallback response after all parsing attempts failed")
                let fallbackContainer = RevisionsContainer(revArray: [])
                
                // Update state with empty response
                lastRevNodeArray = []
                
                // Add as assistant response to maintain conversation flow
                let fallbackJson = "{\"revArray\": []}"
                messages = [fallbackJson]
                conversationHistory.append(AppLLMMessage(role: .assistant, text: fallbackJson))
                genericMessages = conversationHistory.map { MessageConverter.chatMessageFrom(appMessage: $0) }
                
                return fallbackContainer
            }
            
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
        // Convert legacy ChatMessages to AppLLMMessages if needed
        if conversationHistory.isEmpty {
            conversationHistory = MessageConverter.appLLMMessagesFrom(chatMessages: messages)
        }
        
        // Extract resume data from user message if this is an initial query
        let isInitialQuery = !continueConversation && conversationHistory.count <= 2
        let resumeData = isInitialQuery ? 
            conversationHistory.first(where: { $0.role == .user })?.contentParts.first.flatMap { 
                if case let .text(content) = $0 { return content } else { return nil }
            } ?? "" : ""
        
        // Extract user input if this is a continuation
        let userInput = !isInitialQuery && messages.count > 0 ? 
            messages.last(where: { $0.role == .user })?.content : nil
        
        // Process the interaction using our new method
        _ = try await processResumeInteraction(
            newUserInput: userInput,
            isInitialQuery: isInitialQuery,
            resumeDataForPrompt: resumeData
        )
    }

    // MARK: - Conversational Methods
    
    /// Starts a new conversation for resume analysis
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
        
        // Clear previous conversation
        conversationHistory = []
        
        // Initialize conversation
        _ = initializeConversation(systemPrompt: systemPrompt, userPrompt: userMessage)
        
        // Get current model
        let modelString = OpenAIModelFetcher.getPreferredModelString()
        
        // Update client if needed
        updateClientIfNeeded(appState: AppState())
        
        // Execute query
        Task {
            do {
                // Create query
                let query = AppLLMQuery(
                    messages: conversationHistory,
                    modelIdentifier: modelString,
                    temperature: 1.0
                )
                
                // Execute query
                let response = try await executeQuery(query)
                
                // Process response
                let responseText: String
                switch response {
                case .text(let text):
                    responseText = text
                    onProgress(text)
                case .structured(let data):
                    responseText = String(data: data, encoding: .utf8) ?? ""
                    onProgress(responseText)
                }
                
                // Add to conversation history
                _ = addAssistantMessage(responseText)
                
                onComplete(.success(responseText))
            } catch {
                errorMessage = error.localizedDescription
                onComplete(.failure(error))
            }
        }
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
        // Add user message to conversation history
        _ = addUserMessage(userMessage)
        
        // Get current model
        let modelString = OpenAIModelFetcher.getPreferredModelString()
        
        // Update client if needed
        updateClientIfNeeded(appState: AppState())
        
        // Execute query
        Task {
            do {
                // Create query
                let query = AppLLMQuery(
                    messages: conversationHistory,
                    modelIdentifier: modelString,
                    temperature: 1.0
                )
                
                // Execute query
                let response = try await executeQuery(query)
                
                // Process response
                let responseText: String
                switch response {
                case .text(let text):
                    responseText = text
                    onProgress(text)
                case .structured(let data):
                    responseText = String(data: data, encoding: .utf8) ?? ""
                    onProgress(responseText)
                }
                
                // Add to conversation history
                _ = addAssistantMessage(responseText)
                
                onComplete(.success(responseText))
            } catch {
                errorMessage = error.localizedDescription
                onComplete(.failure(error))
            }
        }
    }
}