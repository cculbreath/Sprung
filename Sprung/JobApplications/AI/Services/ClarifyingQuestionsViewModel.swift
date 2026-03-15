//
//  ClarifyingQuestionsViewModel.swift
//  Sprung
//
//
import Foundation
import SwiftUI
/// ViewModel for managing the clarifying questions workflow
/// Handles the flow: Generate Questions → User Answers → Generate Revisions → Show ReviewView
@MainActor
@Observable
class ClarifyingQuestionsViewModel {
    // MARK: - Dependencies
    private let llm: LLMFacade
    private let openRouterService: OpenRouterService
    private let reasoningStreamManager: ReasoningStreamManager
    private let defaultResumeReviseViewModel: ResumeReviseViewModel
    private let exportCoordinator: ResumeExportCoordinator
    private let applicantProfileStore: ApplicantProfileStore
    private let knowledgeCardStore: KnowledgeCardStore
    private var activeStreamingHandle: LLMStreamingHandle?
    // MARK: - UI State
    var isGeneratingQuestions: Bool = false
    var questions: [ClarifyingQuestion] = []
    var currentConversationId: UUID?
    var currentModelId: String? // Track the model used for conversation continuity
    // MARK: - Error Handling
    var lastError: String?
    var showError: Bool = false
    init(
        llmFacade: LLMFacade,
        openRouterService: OpenRouterService,
        reasoningStreamManager: ReasoningStreamManager,
        defaultResumeReviseViewModel: ResumeReviseViewModel,
        exportCoordinator: ResumeExportCoordinator,
        applicantProfileStore: ApplicantProfileStore,
        knowledgeCardStore: KnowledgeCardStore,
    ) {
        self.llm = llmFacade
        self.openRouterService = openRouterService
        self.reasoningStreamManager = reasoningStreamManager
        self.defaultResumeReviseViewModel = defaultResumeReviseViewModel
        self.exportCoordinator = exportCoordinator
        self.applicantProfileStore = applicantProfileStore
        self.knowledgeCardStore = knowledgeCardStore
    }
    // MARK: - Public Interface
    /// Start the clarifying questions workflow
    /// - Parameters:
    ///   - resume: The resume to analyze
    ///   - modelId: The model to use for question generation
    func startClarifyingQuestionsWorkflow(
        resume: Resume,
        modelId: String
    ) async throws {
        isGeneratingQuestions = true
        lastError = nil
        do {
            // Store the model for conversation continuity
            currentModelId = modelId
            // Check if model supports reasoning
            let model = openRouterService.findModel(id: modelId)
            let supportsReasoning = model?.supportsReasoning ?? false
            // Create the query for clarifying questions
            let query = ResumeApiQuery(
                resume: resume,
                exportCoordinator: exportCoordinator,
                applicantProfile: applicantProfileStore.currentProfile(),
                allKnowledgeCards: knowledgeCardStore.knowledgeCards,
                saveDebugPrompt: UserDefaults.standard.bool(forKey: "saveDebugPrompts")
            )
            // Start a new conversation with background docs and clarifying questions request
            let systemPrompt = query.genericSystemMessage.textContent
            let userPrompt = await query.clarifyingQuestionsPrompt()
            if supportsReasoning {
                // Use streaming with reasoning for supported models from the start
                Logger.info("🧠 Using streaming with reasoning for model: \(modelId)")
                // Configure reasoning parameters using user setting
                let userEffort = UserDefaults.standard.string(forKey: "reasoningEffort") ?? "medium"
                let reasoning = OpenRouterReasoning(
                    effort: userEffort,
                    includeReasoning: true // We want to see the reasoning
                )
                // Start streaming conversation with reasoning
                cancelActiveStreaming()
                let handle = try await llm.startConversationStreaming(
                    systemPrompt: systemPrompt,
                    userMessage: userPrompt,
                    modelId: modelId,
                    reasoning: reasoning,
                    jsonSchema: ResumeApiQuery.clarifyingQuestionsSchema
                )
                guard let conversationId = handle.conversationId else {
                    throw LLMError.clientError("Failed to establish conversation for clarifying questions")
                }
                // Store the conversation ID
                currentConversationId = conversationId
                activeStreamingHandle = handle
                // Clear any previous reasoning content and start fresh
                reasoningStreamManager.clear()
                reasoningStreamManager.startReasoning(modelName: modelId)
                var fullResponse = ""
                var collectingJSON = false
                var jsonResponse = ""
                for try await chunk in handle.stream {
                    // Handle reasoning content (supports both legacy and new reasoning_details format)
                    if let reasoningContent = chunk.allReasoningText {
                        Logger.debug("🧠 [ClarifyingQuestionsViewModel] Adding reasoning content: \(reasoningContent.prefix(100))...")
                        reasoningStreamManager.reasoningText += reasoningContent
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
                        reasoningStreamManager.isStreaming = false
                    }
                }
                cancelActiveStreaming()
                // Parse the JSON response using shared parser
                let responseText = jsonResponse.isEmpty ? fullResponse : jsonResponse
                let questionsRequest = try JSONResponseParser.parseText(responseText, as: ClarifyingQuestionsRequest.self)
                // Continue with the parsed questions
                await handleClarifyingQuestionsResponse(questionsRequest, resume: resume, modelId: modelId)
            } else {
                // Use non-streaming for models without reasoning support
                // Start conversation
                let (conversationId, _) = try await llm.startConversation(
                    systemPrompt: systemPrompt,
                    userMessage: userPrompt,
                    modelId: modelId
                )
                // Store the conversation ID
                currentConversationId = conversationId
                let questionsRequest = try await llm.continueConversationStructured(
                    userMessage: "Please provide clarifying questions in the specified JSON format.",
                    modelId: modelId,
                    conversationId: conversationId,
                    as: ClarifyingQuestionsRequest.self,
                    jsonSchema: ResumeApiQuery.clarifyingQuestionsSchema
                )
                await handleClarifyingQuestionsResponse(questionsRequest, resume: resume, modelId: modelId)
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
    /// Process user answers and hand off to revision workflow
    /// - Parameters:
    ///   - answers: User answers to the clarifying questions
    ///   - resume: The resume being revised
    ///   - resumeReviseViewModel: The ViewModel to receive the workflow handoff
    func processAnswersAndHandoffConversation(
        answers: [QuestionAnswer],
        resume: Resume,
        resumeReviseViewModel: ResumeReviseViewModel
    ) async throws {
        Logger.debug("✅ Processing \(answers.count) clarifying question answers")
        await handoffToRevisionWorkflow(
            resumeReviseViewModel: resumeReviseViewModel,
            resume: resume
        )
    }
    private func cancelActiveStreaming() {
        activeStreamingHandle?.cancel()
        activeStreamingHandle = nil
    }
    // MARK: - Revision Workflow Handoff
    /// Hand off to sequential revision workflow
    @MainActor
    private func handoffToRevisionWorkflow(
        resumeReviseViewModel: ResumeReviseViewModel,
        resume: Resume
    ) async {
        Logger.debug("🔄 Handing off to revision workflow")
        do {
            guard let modelId = currentModelId, !modelId.isEmpty else {
                throw ModelConfigurationError.modelNotConfigured(
                    settingKey: "currentModelId",
                    operationName: "Clarifying Questions"
                )
            }
            try await resumeReviseViewModel.startFreshRevisionWorkflow(
                resume: resume,
                modelId: modelId,
                workflow: .customize
            )
            Logger.debug("✅ Revision workflow started")
        } catch {
            Logger.error("Error starting revision workflow: \(error.localizedDescription)")
            lastError = "Error starting customization: \(error.localizedDescription)"
            showError = true
        }
    }
    // MARK: - Private Helpers
    /// Handle the clarifying questions response
    private func handleClarifyingQuestionsResponse(
        _ questionsRequest: ClarifyingQuestionsRequest,
        resume: Resume,
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
            await proceedDirectlyToRevisions(resume: resume, modelId: modelId)
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
            await proceedDirectlyToRevisions(resume: resume, modelId: modelId)
        }
    }
    /// Proceed directly to revision workflow without clarifying questions
    private func proceedDirectlyToRevisions(
        resume: Resume,
        modelId: String
    ) async {
        Logger.info("🎯 Proceeding directly to revision workflow without clarifying questions")
        do {
            let reviseViewModel = defaultResumeReviseViewModel
            try await reviseViewModel.startFreshRevisionWorkflow(
                resume: resume,
                modelId: modelId,
                workflow: .customize
            )
            Logger.info("✅ Revision workflow started, transitioning to review")
            reasoningStreamManager.isVisible = false
        } catch {
            Logger.error("❌ Revision workflow failed: \(error.localizedDescription)")
            lastError = "Failed to start customization: \(error.localizedDescription)"
            showError = true
        }
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
