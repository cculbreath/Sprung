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
            
            // Create the query for clarifying questions
            let query = ResumeApiQuery(resume: resume, saveDebugPrompt: UserDefaults.standard.bool(forKey: "saveDebugPrompts"))
            
            // Start a new conversation with background docs and clarifying questions request
            let systemPrompt = query.genericSystemMessage.textContent
            let userPrompt = await query.clarifyingQuestionsPrompt()
            
            // Start conversation
            let (conversationId, _) = try await llmService.startConversation(
                systemPrompt: systemPrompt,
                userMessage: userPrompt,
                modelId: modelId
            )
            
            // Store the conversation ID and get structured response
            currentConversationId = conversationId
            
            // Request clarifying questions in structured format with schema enforcement
            let questionsRequest = try await llmService.continueConversationStructured(
                userMessage: "Please provide clarifying questions in the specified JSON format.",
                modelId: modelId,
                conversationId: conversationId,
                responseType: ClarifyingQuestionsRequest.self,
                jsonSchema: ResumeApiQuery.clarifyingQuestionsSchema
            )
            
            Logger.debug("🔍 Parsed clarifying questions response:")
            Logger.debug("🔍 proceedWithRevisions: \(questionsRequest.proceedWithRevisions)")
            Logger.debug("🔍 questions.count: \(questionsRequest.questions.count)")
            Logger.debug("🔍 questions.isEmpty: \(questionsRequest.questions.isEmpty)")
            
            if questionsRequest.proceedWithRevisions || questionsRequest.questions.isEmpty {
                // AI decided no questions needed, proceed directly to revisions
                Logger.debug("AI opted to proceed without clarifying questions")
                await proceedDirectlyToRevisions(resume: resume, query: query, modelId: modelId)
            } else {
                // Store questions for UI
                Logger.debug("Generated \(questionsRequest.questions.count) clarifying questions")
                for (index, question) in questionsRequest.questions.enumerated() {
                    Logger.debug("🔍 Question \(index + 1): id=\(question.id), question=\(question.question.prefix(50))...")
                }
                questions = questionsRequest.questions
                Logger.debug("🔍 Stored questions in ViewModel, count: \(questions.count)")
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