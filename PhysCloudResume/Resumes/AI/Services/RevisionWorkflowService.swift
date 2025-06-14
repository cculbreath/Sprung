// PhysCloudResume/Resumes/AI/Services/RevisionWorkflowService.swift

import Foundation

struct RevisionWorkflowResult {
    let revisions: [ProposedRevisionNode]
    let conversationId: UUID
    let modelId: String
}

struct AIResubmissionResult {
    let updatedRevisions: [ProposedRevisionNode]
    let success: Bool
    let error: String?
}

@MainActor
class RevisionWorkflowService {
    private let llmService: LLMService
    
    init(llmService: LLMService) {
        self.llmService = llmService
    }
    
    // MARK: - Fresh Revision Workflow
    
    func startFreshRevisionWorkflow(
        resume: Resume,
        modelId: String
    ) async throws -> RevisionWorkflowResult {
        Logger.debug("🚀 Starting fresh revision workflow")
        
        // Create query for revision workflow
        let query = ResumeApiQuery(resume: resume, saveDebugPrompt: UserDefaults.standard.bool(forKey: "saveDebugPrompts"))
        
        // Start conversation with system prompt and user query
        let systemPrompt = query.genericSystemMessage.textContent
        let userPrompt = await query.wholeResumeQueryString()
        
        // Start conversation and get revisions
        let (conversationId, _) = try await llmService.startConversation(
            systemPrompt: systemPrompt,
            userMessage: userPrompt,
            modelId: modelId
        )
        
        // Request structured revision output with schema enforcement
        let revisions = try await llmService.continueConversationStructured(
            userMessage: "Please provide the revision suggestions in the specified JSON format.",
            modelId: modelId,
            conversationId: conversationId,
            responseType: RevisionsContainer.self,
            jsonSchema: ResumeApiQuery.revNodeArraySchema
        )
        
        // Validate and process the revisions
        let validatedRevisions = validateRevisions(revisions.revArray, for: resume)
        
        Logger.debug("✅ Fresh revision workflow complete: \(validatedRevisions.count) revisions")
        
        return RevisionWorkflowResult(
            revisions: validatedRevisions,
            conversationId: conversationId,
            modelId: modelId
        )
    }
    
    // MARK: - Conversation Continuation
    
    func continueConversationAndGenerateRevisions(
        conversationId: UUID,
        resume: Resume,
        modelId: String
    ) async throws -> [ProposedRevisionNode] {
        Logger.debug("🔄 Continuing conversation for revisions")
        
        // Continue the conversation to request revisions with schema enforcement
        let revisions = try await llmService.continueConversationStructured(
            userMessage: "Based on our discussion, please provide revision suggestions for the resume in the specified JSON format.",
            modelId: modelId,
            conversationId: conversationId,
            responseType: RevisionsContainer.self,
            jsonSchema: ResumeApiQuery.revNodeArraySchema
        )
        
        // Process and validate revisions
        let validatedRevisions = validateRevisions(revisions.revArray, for: resume)
        
        Logger.debug("✅ Conversation handoff complete: \(validatedRevisions.count) revisions ready for review")
        
        return validatedRevisions
    }
    
    // MARK: - AI Resubmission Workflow
    
    func performAIResubmission(
        with resume: Resume,
        feedbackNodes: [FeedbackNode],
        conversationId: UUID,
        modelId: String
    ) async -> AIResubmissionResult {
        Logger.debug("🔄 Starting AI resubmission workflow")
        
        do {
            // Ensure PDF is fresh before resubmission
            try await resume.ensureFreshRenderedText()
            Logger.debug("PDF rendering complete for AI resubmission")
            
            // Filter nodes that need AI intervention
            let nodesToResubmit = filterNodesForAIResubmission(feedbackNodes)
            Logger.debug("🔄 Resubmitting \(nodesToResubmit.count) nodes to AI")
            
            let revisionPrompt = createRevisionPrompt(feedbackNodes: nodesToResubmit)
            
            // Continue the conversation with revision feedback and get new revisions
            let revisions = try await llmService.continueConversationStructured(
                userMessage: revisionPrompt,
                modelId: modelId,
                conversationId: conversationId,
                responseType: RevisionsContainer.self,
                jsonSchema: ResumeApiQuery.revNodeArraySchema
            )
            
            // Validate and process the new revisions
            let validatedRevisions = validateRevisions(revisions.revArray, for: resume)
            
            Logger.debug("✅ AI resubmission complete: \(validatedRevisions.count) new revisions ready for review")
            
            return AIResubmissionResult(
                updatedRevisions: validatedRevisions,
                success: true,
                error: nil
            )
            
        } catch {
            Logger.error("Error in AI resubmission: \(error.localizedDescription)")
            return AIResubmissionResult(
                updatedRevisions: [],
                success: false,
                error: error.localizedDescription
            )
        }
    }
    
    // MARK: - Workflow Completion
    
    func completeReviewWorkflow(
        feedbackNodes: [FeedbackNode],
        resume: Resume
    ) -> [FeedbackNode] {
        Logger.debug("🏁 Completing review workflow")
        
        // Log statistics and apply changes
        feedbackNodes.logFeedbackStatistics()
        feedbackNodes.applyAcceptedChanges(to: resume)
        
        // Check for resubmission
        let nodesToResubmit = feedbackNodes.nodesRequiringAIResubmission
        
        if !nodesToResubmit.isEmpty {
            Logger.debug("Resubmitting \(nodesToResubmit.count) nodes to AI...")
            nodesToResubmit.logResubmissionSummary()
            return nodesToResubmit
        } else {
            Logger.debug("No nodes need resubmission. All changes applied.")
            return []
        }
    }
    
    // MARK: - Private Helper Methods
    
    private func filterNodesForAIResubmission(_ feedbackNodes: [FeedbackNode]) -> [FeedbackNode] {
        let aiActions: Set<PostReviewAction> = [
            .revise, .mandatedChange, .mandatedChangeNoComment, .rewriteNoComment
        ]
        
        let nodesToRevise = feedbackNodes.filter { aiActions.contains($0.actionRequested) }
        
        Logger.debug("🔍 Found \(nodesToRevise.count) nodes requiring AI resubmission")
        for node in nodesToRevise {
            Logger.debug("  - Node \(node.id): \(node.actionRequested.rawValue)")
        }
        
        return nodesToRevise
    }
    
    private func createRevisionPrompt(feedbackNodes: [FeedbackNode]) -> String {
        var prompt = "Please revise the following items based on the feedback provided:\n\n"
        
        for (index, node) in feedbackNodes.enumerated() {
            prompt += "## Item \(index + 1)\n"
            prompt += "Original Text: \(node.originalValue)\n"
            prompt += "Previous Revision: \(node.proposedRevision)\n"
            prompt += "Action Requested: \(node.actionRequested.rawValue)\n"
            
            if !node.reviewerComments.isEmpty {
                prompt += "Reviewer Comments: \(node.reviewerComments)\n"
            }
            
            prompt += "\n"
        }
        
        prompt += "Please provide improved revisions that address the feedback, maintaining the same JSON format as before."
        
        return prompt
    }
    
    // MARK: - Validation Helper
    
    private func validateRevisions(_ revisions: [ProposedRevisionNode], for resume: Resume) -> [ProposedRevisionNode] {
        let validationService = RevisionValidationService()
        return validationService.validateRevisions(revisions, for: resume)
    }
}