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
    var showQuestionsSheet: Bool = false
    var currentConversationId: UUID?
    
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
            // Create the query for clarifying questions
            let query = ResumeApiQuery(resume: resume)
            
            // Generate clarifying questions using ResumeApiQuery prompt
            let fullPrompt = await query.clarifyingQuestionsPrompt()
            let questionsRequest = try await llmService.executeStructured(
                prompt: fullPrompt,
                modelId: modelId,
                responseType: ClarifyingQuestionsRequest.self
            )
            
            if questionsRequest.proceedWithRevisions || questionsRequest.questions.isEmpty {
                // AI decided no questions needed, proceed directly to revisions
                Logger.debug("AI opted to proceed without clarifying questions")
                await proceedDirectlyToRevisions(resume: resume, query: query, modelId: modelId)
            } else {
                // Show questions to user
                Logger.debug("Generated \(questionsRequest.questions.count) clarifying questions")
                questions = questionsRequest.questions
                showQuestionsSheet = true
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
    
    /// Process user answers and generate revisions, then hand off to ResumeReviseViewModel
    /// - Parameters:
    ///   - answers: User answers to the clarifying questions
    ///   - resumeReviseViewModel: The ViewModel to receive the revisions
    ///   - modelId: The model to use for revision generation
    /// - Returns: The generated revisions for handoff
    func processAnswersAndGenerateRevisions(
        answers: [QuestionAnswer],
        resume: Resume,
        modelId: String
    ) async throws -> [ProposedRevisionNode] {
        
        guard let conversationId = currentConversationId else {
            // Start new conversation if we don't have one
            return try await startConversationWithAnswers(
                answers: answers,
                resume: resume,
                modelId: modelId
            )
        }
        
        // Continue existing conversation with answers
        let answerPrompt = createAnswerPrompt(answers: answers)
        
        let revisionsContainer = try await llmService.continueConversationStructured(
            userMessage: answerPrompt,
            modelId: modelId,
            conversationId: conversationId,
            responseType: RevisionsContainer.self
        )
        
        Logger.debug("✅ Generated \(revisionsContainer.revArray.count) revisions from clarifying questions")
        
        // Return revisions for ResumeReviseViewModel to handle
        return revisionsContainer.revArray
    }
    
    // MARK: - Private Helpers
    
    /// Proceed directly to revisions without questions
    private func proceedDirectlyToRevisions(
        resume: Resume,
        query: ResumeApiQuery,
        modelId: String
    ) async {
        // This would trigger the standard revision workflow
        // For now, we can delegate to ResumeReviseViewModel
        Logger.debug("TODO: Proceed directly to revisions workflow")
    }
    
    /// Start a new conversation with user answers
    private func startConversationWithAnswers(
        answers: [QuestionAnswer],
        resume: Resume,
        modelId: String
    ) async throws -> [ProposedRevisionNode] {
        
        // Create initial conversation with system prompt
        let query = ResumeApiQuery(resume: resume)
        let systemPrompt = query.genericSystemMessage.content
        let initialUserMessage = await query.wholeResumeQueryString()
        
        // Start conversation
        let (conversationId, _) = try await llmService.startConversation(
            systemPrompt: systemPrompt,
            userMessage: initialUserMessage,
            modelId: modelId
        )
        
        self.currentConversationId = conversationId
        
        // Now continue with answers
        return try await processAnswersAndGenerateRevisions(
            answers: answers,
            resume: resume,
            modelId: modelId
        )
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
        showQuestionsSheet = false
        currentConversationId = nil
        lastError = nil
        showError = false
        isGeneratingQuestions = false
    }
}