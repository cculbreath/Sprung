//
//  ClarifyingQuestionsViewModel.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 6/4/25.
//

import Foundation
import SwiftUI

/// ViewModel for managing the clarifying questions workflow
/// Handles the flow: Generate Questions → User Answers → Generate Revisions → Show ReviewView
@MainActor
@Observable
class ClarifyingQuestionsViewModel {
    
    // MARK: - Dependencies
    private let llmService: LLMService
    private let appState: AppState
    
    // MARK: - UI State
    var isGeneratingQuestions: Bool = false
    var questions: [ClarifyingQuestion] = []
    var currentConversationId: UUID?
    var currentModelId: String? // Track the model used for conversation continuity
    
    // MARK: - Reasoning Stream State (now uses global manager)
    // reasoningStreamManager is accessed via appState.globalReasoningStreamManager
    
    // MARK: - Error Handling
    var lastError: String?
    var showError: Bool = false
    
    init(llmService: LLMService, appState: AppState) {
        self.llmService = llmService
        self.appState = appState
    }
    
    // MARK: - Public Interface
    
    /// Start the clarifying questions workflow
    /// - Parameters:
    ///   - resume: The resume to analyze
    ///   - jobApp: The job application context
    ///   - modelId: The model to use for question generation
    func startClarifyingQuestionsWorkflow(
        resume: Resume,
        jobApp: JobApp,
        modelId: String
    ) async throws {
        
        isGeneratingQuestions = true
        lastError = nil
        
        do {
            // Store the model for conversation continuity
            currentModelId = modelId
            
            // Check if model supports reasoning
            let model = appState.openRouterService.findModel(id: modelId)
            let supportsReasoning = model?.supportsReasoning ?? false
            
            // Create the query for clarifying questions
            let query = ResumeApiQuery(resume: resume, saveDebugPrompt: UserDefaults.standard.bool(forKey: "saveDebugPrompts"))
            
            // Start a new conversation with background docs and clarifying questions request
            let systemPrompt = query.genericSystemMessage.textContent
            let userPrompt = await query.clarifyingQuestionsPrompt()
            
            if supportsReasoning {
                // Use streaming with reasoning for supported models from the start
                Logger.info("🧠 Using streaming with reasoning for model: \(modelId)")
                
                // Configure reasoning parameters
                let reasoning = OpenRouterReasoning(
                    effort: "high",
                    includeReasoning: true // We want to see the reasoning
                )
                
                // Start streaming conversation with reasoning
                let (conversationId, stream) = try await llmService.startConversationStreaming(
                    systemPrompt: systemPrompt,
                    userMessage: userPrompt,
                    modelId: modelId,
                    reasoning: reasoning,
                    jsonSchema: ResumeApiQuery.clarifyingQuestionsSchema
                )
                
                // Store the conversation ID
                currentConversationId = conversationId
                
                // Process stream and collect full response
                appState.globalReasoningStreamManager.startReasoning(modelName: modelId)
                var fullResponse = ""
                var collectingJSON = false
                var jsonResponse = ""
                
                for try await chunk in stream {
                    // Handle reasoning content
                    if let reasoningContent = chunk.reasoningContent {
                        Logger.debug("🧠 [ClarifyingQuestionsViewModel] Adding reasoning content: \(reasoningContent.prefix(100))...")
                        appState.globalReasoningStreamManager.reasoningText += reasoningContent
                    }
                    
                    // Collect regular content
                    if let content = chunk.content {
                        fullResponse += content
                        
                        // Try to extract JSON from the response
                        if content.contains("{") || collectingJSON {
                            collectingJSON = true
                            jsonResponse += content
                        }
                    }
                    
                    // Handle completion
                    if chunk.isFinished {
                        appState.globalReasoningStreamManager.isStreaming = false
                    }
                }
                
                // Parse the JSON response
                let responseText = jsonResponse.isEmpty ? fullResponse : jsonResponse
                let questionsRequest = try parseJSONFromText(responseText, as: ClarifyingQuestionsRequest.self)
                
                // Continue with the parsed questions
                await handleClarifyingQuestionsResponse(questionsRequest, resume: resume, query: query, modelId: modelId)
                
            } else {
                // Use non-streaming for models without reasoning support
                // Start conversation
                let (conversationId, _) = try await llmService.startConversation(
                    systemPrompt: systemPrompt,
                    userMessage: userPrompt,
                    modelId: modelId
                )
                
                // Store the conversation ID
                currentConversationId = conversationId
                
                let questionsRequest = try await llmService.continueConversationStructured(
                    userMessage: "Please provide clarifying questions in the specified JSON format.",
                    modelId: modelId,
                    conversationId: conversationId,
                    responseType: ClarifyingQuestionsRequest.self,
                    jsonSchema: ResumeApiQuery.clarifyingQuestionsSchema
                )
                
                await handleClarifyingQuestionsResponse(questionsRequest, resume: resume, query: query, modelId: modelId)
            }
            
            isGeneratingQuestions = false
            
        } catch {
            Logger.error("Error generating clarifying questions: \(error.localizedDescription)")
            lastError = error.localizedDescription
            showError = true
            isGeneratingQuestions = false
            throw error
        }
    }
    
    /// Process user answers and hand off conversation to ResumeReviseViewModel
    /// - Parameters:
    ///   - answers: User answers to the clarifying questions
    ///   - resume: The resume being revised
    ///   - resumeReviseViewModel: The ViewModel to receive the conversation handoff
    func processAnswersAndHandoffConversation(
        answers: [QuestionAnswer],
        resume: Resume,
        resumeReviseViewModel: ResumeReviseViewModel
    ) async throws {
        
        guard let conversationId = currentConversationId else {
            throw ClarifyingQuestionsError.noActiveConversation
        }
        
        // Add the user's answers to the conversation without generating revisions yet
        let answerPrompt = createAnswerPrompt(answers: answers)
        
        // Just add the answers to the conversation - don't generate revisions here
        let _ = try await llmService.continueConversation(
            userMessage: answerPrompt,
            modelId: currentModelId ?? "gpt-4o", // Use the model from the original workflow
            conversationId: conversationId
        )
        
        Logger.debug("✅ User answers added to conversation \(conversationId)")
        
        // Hand off the conversation to ResumeReviseViewModel - it will generate revisions
        await handoffConversationToResumeReviseViewModel(
            resumeReviseViewModel: resumeReviseViewModel,
            conversationId: conversationId,
            resume: resume
        )
    }
    
    // MARK: - ResumeReviseViewModel Handoff
    
    /// Hand off conversation context to ResumeReviseViewModel for revision generation
    /// This is the core handoff method mentioned in LLM_MULTI_TURN_WORKFLOWS.md
    /// - Parameters:
    ///   - resumeReviseViewModel: The ViewModel to receive the conversation handoff
    ///   - conversationId: The conversation ID with established Q&A context
    ///   - resume: The resume being revised
    @MainActor
    private func handoffConversationToResumeReviseViewModel(
        resumeReviseViewModel: ResumeReviseViewModel,
        conversationId: UUID,
        resume: Resume
    ) async {
        Logger.debug("🔄 Handing off conversation \(conversationId) to ResumeReviseViewModel")
        
        do {
            // Pass conversation context - ResumeReviseViewModel will generate revisions
            // using the existing conversation thread (no duplicate background docs needed)
            try await resumeReviseViewModel.continueConversationAndGenerateRevisions(
                conversationId: conversationId,
                resume: resume,
                modelId: currentModelId ?? "gpt-4o"
            )
            
            Logger.debug("✅ Conversation handoff complete - ResumeReviseViewModel is managing the workflow")
            
        } catch {
            Logger.error("Error in conversation handoff: \(error.localizedDescription)")
            // Handle error appropriately - perhaps show an error to the user
        }
    }
    
    // MARK: - Private Helpers
    
    /// Handle the clarifying questions response
    private func handleClarifyingQuestionsResponse(
        _ questionsRequest: ClarifyingQuestionsRequest,
        resume: Resume,
        query: ResumeApiQuery,
        modelId: String
    ) async {
        Logger.debug("🔍 Parsed clarifying questions response:")
        Logger.debug("🔍 proceedWithRevisions: \(questionsRequest.proceedWithRevisions)")
        Logger.debug("🔍 questions.count: \(questionsRequest.questions.count)")
        Logger.debug("🔍 questions.isEmpty: \(questionsRequest.questions.isEmpty)")
        
        // Only auto-proceed if AI explicitly says to proceed AND there are no questions
        if questionsRequest.proceedWithRevisions && questionsRequest.questions.isEmpty {
            // AI decided no questions needed, proceed directly to revisions
            Logger.debug("AI opted to proceed without clarifying questions")
            await proceedDirectlyToRevisions(resume: resume, query: query, modelId: modelId)
        } else if !questionsRequest.questions.isEmpty {
            // Store questions for UI - let user decide whether to answer them
            Logger.debug("Generated \(questionsRequest.questions.count) clarifying questions")
            for (index, question) in questionsRequest.questions.enumerated() {
                Logger.debug("🔍 Question \(index + 1): id=\(question.id), question=\(question.question.prefix(50))...")
            }
            questions = questionsRequest.questions
            Logger.debug("🔍 Stored questions in ViewModel, count: \(questions.count)")
        } else {
            // Edge case: no questions and AI didn't explicitly say to proceed
            Logger.debug("No questions generated and AI didn't explicitly request to proceed - treating as no questions needed")
            await proceedDirectlyToRevisions(resume: resume, query: query, modelId: modelId)
        }
    }
    
    /// Proceed directly to revisions without questions
    private func proceedDirectlyToRevisions(
        resume: Resume,
        query: ResumeApiQuery,
        modelId: String
    ) async {
        Logger.info("🎯 Proceeding directly to revisions workflow without clarifying questions")
        
        do {
            // Create a ResumeReviseViewModel instance to handle the revision workflow
            let reviseViewModel = ResumeReviseViewModel(llmService: llmService, appState: appState)
            
            // Start the fresh revision workflow
            try await reviseViewModel.startFreshRevisionWorkflow(
                resume: resume,
                modelId: modelId
            )
            
            // Update our state to indicate we're showing revisions
            Logger.info("✅ Direct revision workflow completed, transitioning to review")
            
            // Signal that revisions are ready (this will be handled by the view layer)
            await MainActor.run {
                appState.resumeReviseViewModel = reviseViewModel
                reviseViewModel.showResumeRevisionSheet = true
            }
            
        } catch {
            Logger.error("❌ Direct revision workflow failed: \(error.localizedDescription)")
            await MainActor.run {
                lastError = "Failed to generate revisions: \(error.localizedDescription)"
                showError = true
            }
        }
    }
    
    /// Start a new conversation with user answers
    private func startConversationWithAnswers(
        answers: [QuestionAnswer],
        resume: Resume,
        modelId: String
    ) async throws -> [ProposedRevisionNode] {
        
        // Create initial conversation with system prompt
        let query = ResumeApiQuery(resume: resume, saveDebugPrompt: UserDefaults.standard.bool(forKey: "saveDebugPrompts"))
        let systemPrompt = query.genericSystemMessage.textContent
        let initialUserMessage = await query.wholeResumeQueryString()
        
        // Start conversation
        let (conversationId, _) = try await llmService.startConversation(
            systemPrompt: systemPrompt,
            userMessage: initialUserMessage,
            modelId: modelId
        )
        
        self.currentConversationId = conversationId
        
        // Now continue with answers - this is a recursive call but now we need resumeReviseViewModel
        // This path shouldn't be used in normal flow since we should have a conversationId
        throw ClarifyingQuestionsError.noActiveConversation
    }
    
    
    /// Create prompt from user answers
    private func createAnswerPrompt(answers: [QuestionAnswer]) -> String {
        var prompt = "Based on my answers to your clarifying questions, please provide revision suggestions in the specified JSON format:\n\n"
        
        for (index, answer) in answers.enumerated() {
            prompt += "Question \(index + 1) (ID: \(answer.questionId))\n"
            prompt += "Answer: \(answer.answer ?? "No answer provided")\n\n"
        }
        
        prompt += "Please provide the revision suggestions in the specified JSON format."
        
        return prompt
    }
    
    /// Reset workflow state
    func resetWorkflow() {
        questions = []
        currentConversationId = nil
        lastError = nil
        showError = false
        isGeneratingQuestions = false
    }
    
    /// Parse JSON from text content with fallback strategies
    private func parseJSONFromText<T: Codable>(_ text: String, as type: T.Type) throws -> T {
        Logger.debug("🔍 Attempting to parse JSON from text: \(text.prefix(500))...")
        
        // First try direct parsing if the entire text is JSON
        if let jsonData = text.data(using: .utf8) {
            do {
                let result = try JSONDecoder().decode(type, from: jsonData)
                Logger.info("✅ Direct JSON parsing successful")
                return result
            } catch {
                Logger.debug("❌ Direct JSON parsing failed: \(error)")
            }
        }
        
        // Try to extract JSON from text (look for JSON between ```json and ``` or just {...})
        let cleanedText = extractJSONFromText(text)
        if let jsonData = cleanedText.data(using: .utf8) {
            do {
                let result = try JSONDecoder().decode(type, from: jsonData)
                Logger.info("✅ Extracted JSON parsing successful")
                return result
            } catch {
                Logger.debug("❌ Extracted JSON parsing failed: \(error)")
            }
        }
        
        throw LLMError.decodingFailed(NSError(domain: "ClarifyingQuestionsViewModel", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not parse JSON from response"]))
    }
    
    /// Extract JSON from text that may contain other content
    private func extractJSONFromText(_ text: String) -> String {
        // Look for JSON between code blocks
        if let range = text.range(of: "```json") {
            let afterStart = text[range.upperBound...]
            if let endRange = afterStart.range(of: "```") {
                return String(afterStart[..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        // Look for standalone JSON object
        if let startRange = text.range(of: "{") {
            var braceCount = 1
            var index = text.index(after: startRange.lowerBound)
            
            while index < text.endIndex && braceCount > 0 {
                let char = text[index]
                if char == "{" {
                    braceCount += 1
                } else if char == "}" {
                    braceCount -= 1
                }
                index = text.index(after: index)
            }
            
            if braceCount == 0 {
                let jsonRange = startRange.lowerBound..<index
                return String(text[jsonRange])
            }
        }
        
        return text
    }
}

// MARK: - Error Types
enum ClarifyingQuestionsError: LocalizedError {
    case noActiveConversation
    
    var errorDescription: String? {
        switch self {
        case .noActiveConversation:
            return "No active conversation to continue with answers"
        }
    }
}