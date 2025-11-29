//
//  ClarifyingQuestionsViewModel.swift
//  Sprung
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
    private let llm: LLMFacade
    private let openRouterService: OpenRouterService
    private let reasoningStreamManager: ReasoningStreamManager
    private let defaultResumeReviseViewModel: ResumeReviseViewModel
    private let exportCoordinator: ResumeExportCoordinator
    private let applicantProfileStore: ApplicantProfileStore
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
        applicantProfileStore: ApplicantProfileStore
    ) {
        self.llm = llmFacade
        self.openRouterService = openRouterService
        self.reasoningStreamManager = reasoningStreamManager
        self.defaultResumeReviseViewModel = defaultResumeReviseViewModel
        self.exportCoordinator = exportCoordinator
        self.applicantProfileStore = applicantProfileStore
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
                    // Handle reasoning content
                    if let reasoningContent = chunk.reasoning {
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
                // Parse the JSON response
                let responseText = jsonResponse.isEmpty ? fullResponse : jsonResponse
                let questionsRequest = try parseJSONFromText(responseText, as: ClarifyingQuestionsRequest.self)
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
        let modelId = currentModelId ?? "gpt-4o" // Use the model from the original workflow
        // Add the user's answers to the conversation
        let answerPrompt = createAnswerPrompt(answers: answers)
        // Check if model supports reasoning for streaming
            let model = openRouterService.findModel(id: modelId)
        let supportsReasoning = model?.supportsReasoning ?? false
        Logger.debug("🤖 [processAnswersAndHandoffConversation] Model: \(modelId)")
        Logger.debug("🤖 [processAnswersAndHandoffConversation] Supports reasoning: \(supportsReasoning)")
        if supportsReasoning {
            // Use streaming with reasoning for supported models
            Logger.info("🧠 Using streaming with reasoning for clarifying question answers: \(modelId)")
            // Configure reasoning parameters using user setting
            let userEffort = UserDefaults.standard.string(forKey: "reasoningEffort") ?? "medium"
            let reasoning = OpenRouterReasoning(
                effort: userEffort,
                includeReasoning: true
            )
            // Show reasoning modal for answer processing
            reasoningStreamManager.clear()
            reasoningStreamManager.modelName = modelId
            reasoningStreamManager.isVisible = true
            reasoningStreamManager.startReasoning(modelName: modelId)
            cancelActiveStreaming()
            let handle = try await llm.continueConversationStreaming(
                userMessage: answerPrompt,
                modelId: modelId,
                conversationId: conversationId,
                images: [],
                temperature: nil,
                reasoning: reasoning,
                jsonSchema: nil
            )
            activeStreamingHandle = handle
            // Process the stream
            for try await chunk in handle.stream {
                // Handle reasoning content
                if let reasoningContent = chunk.reasoning {
                    reasoningStreamManager.reasoningText += reasoningContent
                }
                // Handle completion
                if chunk.isFinished {
                    reasoningStreamManager.isStreaming = false
                    // Keep modal visible - it will be handled by revision generation
                }
            }
            cancelActiveStreaming()
        } else {
            // Use non-streaming for models without reasoning
            Logger.info("📝 Using non-streaming for clarifying question answers: \(modelId)")
            _ = try await llm.continueConversation(
                userMessage: answerPrompt,
                modelId: modelId,
                conversationId: conversationId
            )
        }
        Logger.debug("✅ User answers added to conversation \(conversationId)")
        // Hand off the conversation to ResumeReviseViewModel - it will generate revisions
        await handoffConversationToResumeReviseViewModel(
            resumeReviseViewModel: resumeReviseViewModel,
            conversationId: conversationId,
            resume: resume
        )
    }
    private func cancelActiveStreaming() {
        activeStreamingHandle?.cancel()
        activeStreamingHandle = nil
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
            // If it's a JSON parsing error, show the full response for debugging
            let nsError = error as NSError
            if nsError.domain == "ResumeReviseViewModel",
               let fullResponse = nsError.userInfo["fullResponse"] as? String {
                DispatchQueue.main.async {
                    self.lastError = "AI returned an unexpected response format. Full response:\n\n\(fullResponse)"
                    self.showError = true
                }
            } else {
                DispatchQueue.main.async {
                    self.lastError = "Error processing AI response: \(error.localizedDescription)"
                    self.showError = true
                }
            }
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
    /// Proceed directly to revisions without questions
    private func proceedDirectlyToRevisions(
        resume: Resume,
        modelId: String
    ) async {
        Logger.info("🎯 Proceeding directly to revisions workflow without clarifying questions")
        do {
            let reviseViewModel = defaultResumeReviseViewModel
            Logger.debug("🔍 [ClarifyingQuestionsViewModel] Using shared ResumeReviseViewModel at address: \(String(describing: Unmanaged.passUnretained(reviseViewModel).toOpaque()))")
            // Start the fresh revision workflow
            try await reviseViewModel.startFreshRevisionWorkflow(
                resume: resume,
                modelId: modelId,
                workflow: .clarifying
            )
            // Update our state to indicate we're showing revisions
            Logger.info("✅ Direct revision workflow completed, transitioning to review")
            // Signal that revisions are ready (this will be handled by the view layer)
                await MainActor.run {
                    // Ensure reasoning modal is hidden before transitioning
                    reasoningStreamManager.isVisible = false
                }
        } catch {
            Logger.error("❌ Direct revision workflow failed: \(error.localizedDescription)")
            // If it's a JSON parsing error, show the full response for debugging
            let nsError = error as NSError
            if nsError.domain == "ResumeReviseViewModel",
               let fullResponse = nsError.userInfo["fullResponse"] as? String {
                await MainActor.run {
                    lastError = "AI returned an unexpected response format. Full response:\n\n\(fullResponse)"
                    showError = true
                }
            } else {
                await MainActor.run {
                    lastError = "Failed to generate revisions: \(error.localizedDescription)"
                    showError = true
                }
            }
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
