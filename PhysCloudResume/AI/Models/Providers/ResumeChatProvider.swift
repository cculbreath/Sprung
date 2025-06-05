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
    
    // Resume-specific state
    var lastRevNodeArray: [ProposedRevisionNode] = []
    
    // Stores generic chat messages for the abstraction layer (legacy)
    var genericMessages: [ChatMessage] = []
    
    // Clarifying questions state
    var lastClarifyingQuestions: [ClarifyingQuestion] = []

    // MARK: - Initializers


    // MARK: - Resume-specific Methods
    
    /// Resets the provider state for a fresh conversation
    /// This should be called when starting a new revision workflow to prevent stale state
    func resetForNewConversation() {
        Logger.debug("Resetting ResumeChatProvider state for new conversation")
        lastRevNodeArray = []
        lastClarifyingQuestions = []
        conversationHistory = []
        genericMessages = []
        errorMessage = ""
    }
    
    /// System prompt for clarifying questions mode
    private let clarifyingQuestionsSystemPrompt = """
    You are a helpful resume assistant. The user has requested an enhanced revision process where you may ask clarifying questions before proposing modifications.

    Review the resume and selected nodes carefully. You have two options:

    1. If you have specific questions that would help you provide better, more targeted revisions, you may ask up to 3 clarifying questions.

    2. If you have sufficient information to provide excellent revisions without additional context, you may proceed directly to generating revisions.

    Respond with a JSON object in this format:
    {
        "questions": [
            {
                "id": "q1",
                "question": "Your specific question here",
                "context": "Optional explanation of why this information would be helpful"
            }
            // ... up to 3 questions
        ],
        "proceedWithRevisions": false  // or true if no questions needed
    }

    If proceedWithRevisions is true, the questions array should be empty.
    """

    /// Process a resume interaction using the unified AppLLMClientProtocol
    /// - Parameters:
    ///   - newUserInput: Optional new user input (if not an initial query)
    ///   - isInitialQuery: Whether this is the first query in a conversation
    ///   - resumeDataForPrompt: The resume data for the prompt (required for initial query)
    ///   - modelId: The specific model ID to use for the interaction
    /// - Returns: The revisions container with suggested changes
    func processResumeInteraction(
        newUserInput: String?,
        isInitialQuery: Bool,
        resumeDataForPrompt: String,
        modelId: String
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
        
        // Use the specified model identifier
        let modelIdentifier = modelId
        
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
                       let jsonEnd = text.range(of: "}", options: .backwards),
                       jsonStart.lowerBound <= jsonEnd.lowerBound {
                        
                        // Use index(after:) to include the closing brace
                        let endIndex = text.index(after: jsonEnd.lowerBound)
                        guard endIndex <= text.endIndex else {
                            Logger.error("JSON end index out of bounds")
                            throw NSError(
                                domain: "ResumeChatProviderError",
                                code: 1003,
                                userInfo: [NSLocalizedDescriptionKey: "JSON extraction failed: end index out of bounds"]
                            )
                        }
                        
                        let jsonString = String(text[jsonStart.lowerBound..<endIndex])
                        
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
        _ = resume // Unused parameter kept for backwards compatibility
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
            resumeDataForPrompt: resumeData,
            modelId: "gpt-4o" // TODO: Remove this when migrating to ResumeReviseService
        )
    }

    // MARK: - Conversational Methods
    
    /// Starts a new conversation for resume analysis
    /// - Parameters:
    ///   - resume: The resume to analyze
    ///   - modelId: The specific model ID to use for the analysis
    ///   - customInstructions: Optional custom instructions for the analysis
    ///   - onProgress: Progress callback for streaming responses
    ///   - onComplete: Completion callback with result
    @MainActor
    func startNewResumeConversation(
        resume: Resume,
        modelId: String,
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
        
        // Use the specified model
        let modelString = modelId
        
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
    ///   - modelId: The specific model ID to use for the conversation
    ///   - onProgress: Progress callback for streaming responses
    ///   - onComplete: Completion callback with result
    @MainActor
    func continueResumeConversation(
        resume: Resume,
        userMessage: String,
        modelId: String,
        onProgress: @escaping (String) -> Void = { _ in },
        onComplete: @escaping (Result<String, Error>) -> Void = { _ in }
    ) {
        // Add user message to conversation history
        _ = addUserMessage(userMessage)
        
        // Use the specified model
        let modelString = modelId
        
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
    
    // MARK: - Clarifying Questions Methods
    
    /// Starts the clarifying questions workflow from the toolbar
    /// - Parameters:
    ///   - resume: The resume to customize
    ///   - jobApp: The job application context
    ///   - modelId: The specific model ID to use
    /// - Returns: The clarifying questions to show the user
    func startClarifyingQuestionsWorkflow(resume: Resume, jobApp: JobApp, modelId: String) async throws -> [ClarifyingQuestion] {
        // Create a resume query for the clarifying questions
        let resumeQuery = ResumeApiQuery(resume: resume)
        resumeQuery.queryMode = .withClarifyingQuestions
        
        // Request clarifying questions
        if let questionsRequest = try await requestClarifyingQuestions(resumeQuery: resumeQuery, modelId: modelId) {
            if questionsRequest.proceedWithRevisions || questionsRequest.questions.isEmpty {
                // LLM decided no questions needed - could return empty array or throw specific error
                return []
            } else {
                return questionsRequest.questions
            }
        }
        
        return []
    }
    
    /// Request clarifying questions from the LLM
    /// - Parameter resumeQuery: The resume query containing the context
    /// - Parameter modelId: The specific model ID to use for generating questions
    /// - Returns: The clarifying questions request or nil if proceeding without questions
    func requestClarifyingQuestions(resumeQuery: ResumeApiQuery, modelId: String) async throws -> ClarifyingQuestionsRequest? {
        // Clear previous error message
        errorMessage = ""
        
        // Build the prompt for clarifying questions
        let userPrompt = await buildClarifyingQuestionsPrompt(resumeQuery: resumeQuery)
        
        // Initialize conversation with clarifying questions system prompt
        conversationHistory = [
            AppLLMMessage(role: .system, text: clarifyingQuestionsSystemPrompt),
            AppLLMMessage(role: .user, text: userPrompt)
        ]
        
        // Use the specified model identifier
        let modelIdentifier = modelId
        
        // Create query for structured output
        let query = AppLLMQuery(
            messages: conversationHistory,
            modelIdentifier: modelIdentifier,
            responseType: ClarifyingQuestionsRequest.self
        )
        
        do {
            // Execute the query
            let response = try await executeQueryWithTimeout(query)
            
            // Process the structured response
            let questionsRequest = try processStructuredResponse(response, as: ClarifyingQuestionsRequest.self)
            
            // Store the questions for later reference
            lastClarifyingQuestions = questionsRequest.questions
            
            // Add assistant response to conversation history
            let jsonData = try JSONEncoder().encode(questionsRequest)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
            conversationHistory.append(AppLLMMessage(role: .assistant, text: jsonString))
            
            // Return the request (caller will check if proceedWithRevisions is true)
            return questionsRequest
            
        } catch {
            Logger.error("Failed to get clarifying questions: \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Build the prompt for requesting clarifying questions
    private func buildClarifyingQuestionsPrompt(resumeQuery: ResumeApiQuery) async -> String {
        // Get the resume data
        let resumeText = await resumeQuery.wholeResumeQueryString()
        
        return """
        The user has requested resume modifications with the option to ask clarifying questions first.
        
        Here is the context:
        
        \(resumeText)
        
        Review this information and decide:
        1. If you need additional information to provide excellent revisions, ask up to 3 specific questions
        2. If you have sufficient information, set proceedWithRevisions to true and provide an empty questions array
        
        Focus on questions that would help you:
        - Better tailor the resume to the specific job
        - Highlight relevant achievements or experiences
        - Use appropriate industry terminology
        - Quantify accomplishments where possible
        """
    }
    
    /// Process answers to clarifying questions and continue with revisions using existing conversation flow
    /// - Parameters:
    ///   - answers: The user's answers to the clarifying questions  
    ///   - resume: The resume being worked on
    ///   - modelId: The specific model ID to use for generating revisions
    func processAnswersAndContinueConversation(
        answers: [QuestionAnswer],
        resume: Resume,
        modelId: String
    ) async {
        // Build a summary of Q&A for the conversation
        var answersText = "Here are the answers to your clarifying questions:\n\n"
        
        for answer in answers {
            if let question = lastClarifyingQuestions.first(where: { $0.id == answer.questionId }) {
                answersText += "Q: \(question.question)\n"
                answersText += "A: \(answer.answer ?? "User declined to answer")\n\n"
            }
        }
        
        answersText += "\nNow please provide your resume revision suggestions based on all the information provided."
        
        // Use existing conversation continuation method (DRY principle)
        await continueResumeConversation(
            resume: resume,
            userMessage: answersText,
            modelId: modelId
        )
    }
}