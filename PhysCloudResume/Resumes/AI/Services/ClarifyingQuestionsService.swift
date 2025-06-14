// PhysCloudResume/Resumes/AI/Services/ClarifyingQuestionsService.swift

import Foundation

@MainActor
class ClarifyingQuestionsService {
    private let llmService: LLMService
    
    init(llmService: LLMService) {
        self.llmService = llmService
    }
    
    // MARK: - Clarifying Questions Generation
    
    func requestClarifyingQuestions(
        resume: Resume,
        query: ResumeApiQuery,
        modelId: String
    ) async throws -> ClarifyingQuestionsRequest? {
        Logger.debug("❓ Requesting clarifying questions")
        
        // Validate model capabilities
        try llmService.validateModel(modelId: modelId, for: [])
        
        // Create clarifying questions prompt using the generic system message
        let systemPrompt = query.genericSystemMessage.textContent
        let userContext = await query.wholeResumeQueryString()
        
        // Request clarifying questions
        let questionsRequest = try await llmService.executeStructured(
            prompt: "\(systemPrompt)\n\nResume Context:\n\(userContext)",
            modelId: modelId,
            responseType: ClarifyingQuestionsRequest.self
        )
        
        Logger.debug("📋 Generated \(questionsRequest.questions.count) clarifying questions")
        Logger.debug("🎯 Proceed with revisions: \(questionsRequest.proceedWithRevisions)")
        
        return questionsRequest
    }
    
    // MARK: - Question and Answer Processing
    
    func formatClarifyingQuestionsAndAnswers(_ qa: [QuestionAnswer]) -> String {
        var formatted = ""
        
        for item in qa {
            formatted += "Question ID: \(item.questionId)\n"
            if let answer = item.answer {
                formatted += "Answer: \(answer)\n\n"
            } else {
                formatted += "Answer: [No answer provided]\n\n"
            }
        }
        
        return formatted.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Question Validation
    
    func validateQuestionsRequest(_ request: ClarifyingQuestionsRequest?) -> Bool {
        guard let request = request else { return false }
        
        // If we should proceed with revisions, no questions needed
        if request.proceedWithRevisions {
            Logger.debug("🚀 AI determined no clarifying questions needed")
            return false
        }
        
        // Validate that we have meaningful questions
        let validQuestions = request.questions.filter { !$0.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        
        if validQuestions.isEmpty {
            Logger.debug("⚠️ No valid clarifying questions found")
            return false
        }
        
        Logger.debug("✅ Found \(validQuestions.count) valid clarifying questions")
        return true
    }
    
    // MARK: - Answer Processing
    
    func processQuestionAnswers(_ qa: [QuestionAnswer]) -> [QuestionAnswer] {
        return qa.compactMap { item in
            // Filter out unanswered questions or questions with empty answers
            guard let answer = item.answer?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !answer.isEmpty else {
                Logger.debug("⚠️ Skipping question \(item.questionId) - no answer provided")
                return nil
            }
            
            return item
        }
    }
    
    // MARK: - Conversation Setup
    
    func prepareConversationWithQuestions(
        resume: Resume,
        query: ResumeApiQuery,
        questionAnswers: [QuestionAnswer],
        modelId: String
    ) async throws -> (conversationId: UUID, systemPrompt: String) {
        Logger.debug("🎯 Preparing conversation with clarifying questions and answers")
        
        // Create system prompt
        let systemPrompt = query.genericSystemMessage.textContent
        
        // Create initial user context
        let userContext = await query.wholeResumeQueryString()
        
        // Format the Q&A for inclusion in the conversation
        let formattedQA = formatClarifyingQuestionsAndAnswers(questionAnswers)
        
        // Combine context with Q&A
        let enrichedUserPrompt = """
        \(userContext)
        
        Additional Context from Clarifying Questions:
        \(formattedQA)
        """
        
        // Start conversation with enriched context
        let (conversationId, _) = try await llmService.startConversation(
            systemPrompt: systemPrompt,
            userMessage: enrichedUserPrompt,
            modelId: modelId
        )
        
        Logger.debug("✅ Conversation prepared with clarifying questions context")
        
        return (conversationId, systemPrompt)
    }
}