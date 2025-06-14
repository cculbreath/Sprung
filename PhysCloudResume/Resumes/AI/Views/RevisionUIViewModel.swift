// PhysCloudResume/Resumes/AI/Views/RevisionUIViewModel.swift

import Foundation
import SwiftUI

@MainActor
@Observable
class RevisionUIViewModel {
    
    // MARK: - UI State Properties
    
    // Sheet and workflow state
    var showResumeRevisionSheet: Bool = false
    var isProcessingRevisions: Bool = false
    
    // Current revision and feedback
    var resumeRevisions: [ProposedRevisionNode] = []
    var feedbackNodes: [FeedbackNode] = []
    var currentRevisionNode: ProposedRevisionNode?
    var currentFeedbackNode: FeedbackNode?
    
    // Navigation state
    var feedbackIndex: Int = 0
    var updateNodes: [[String: Any]] = []
    
    // UI interaction state
    var isEditingResponse: Bool = false
    var isCommenting: Bool = false
    var isMoreCommenting: Bool = false
    var aiResubmit: Bool = false
    
    // Error handling
    var lastError: String?
    
    // MARK: - Services
    private let workflowService: RevisionWorkflowService
    private let clarifyingQuestionsService: ClarifyingQuestionsService
    
    init(workflowService: RevisionWorkflowService, clarifyingQuestionsService: ClarifyingQuestionsService) {
        self.workflowService = workflowService
        self.clarifyingQuestionsService = clarifyingQuestionsService
    }
    
    // MARK: - Workflow Management
    
    func startFreshRevisionWorkflow(resume: Resume, modelId: String) async {
        resetWorkflowState()
        isProcessingRevisions = true
        
        do {
            let result = try await workflowService.startFreshRevisionWorkflow(
                resume: resume,
                modelId: modelId
            )
            
            await setupRevisionsForReview(result.revisions)
            
        } catch {
            isProcessingRevisions = false
            lastError = error.localizedDescription
            Logger.error("Error starting fresh revision workflow: \(error)")
        }
    }
    
    func continueConversationAndGenerateRevisions(
        conversationId: UUID,
        resume: Resume,
        modelId: String
    ) async {
        isProcessingRevisions = true
        
        do {
            let validatedRevisions = try await workflowService.continueConversationAndGenerateRevisions(
                conversationId: conversationId,
                resume: resume,
                modelId: modelId
            )
            
            await setupRevisionsForReview(validatedRevisions)
            
        } catch {
            isProcessingRevisions = false
            lastError = error.localizedDescription
            Logger.error("Error continuing conversation for revisions: \(error)")
        }
    }
    
    func requestClarifyingQuestions(
        resume: Resume,
        query: ResumeApiQuery,
        modelId: String
    ) async -> ClarifyingQuestionsRequest? {
        do {
            return try await clarifyingQuestionsService.requestClarifyingQuestions(
                resume: resume,
                query: query,
                modelId: modelId
            )
        } catch {
            lastError = error.localizedDescription
            Logger.error("Error requesting clarifying questions: \(error)")
            return nil
        }
    }
    
    // MARK: - UI State Management
    
    func setupRevisionsForReview(_ revisions: [ProposedRevisionNode]) async {
        resumeRevisions = revisions
        feedbackNodes = []
        feedbackIndex = 0
        
        if !revisions.isEmpty {
            currentRevisionNode = revisions[0]
            currentFeedbackNode = revisions[0].createFeedbackNode()
        }
        
        showResumeRevisionSheet = true
        isProcessingRevisions = false
    }
    
    func resetWorkflowState() {
        resumeRevisions = []
        feedbackNodes = []
        currentRevisionNode = nil
        currentFeedbackNode = nil
        aiResubmit = false
        feedbackIndex = 0
        lastError = nil
        resetUIInteractionState()
    }
    
    func resetUIInteractionState() {
        isCommenting = false
        isMoreCommenting = false
        isEditingResponse = false
    }
    
    // MARK: - Navigation Methods
    
    func saveAndNext(response: PostReviewAction, resume: Resume) {
        guard let currentFeedbackNode = currentFeedbackNode else { return }
        
        currentFeedbackNode.processAction(response)
        
        switch response {
        case .acceptedWithChanges:
            isEditingResponse = false
        case .revise, .mandatedChangeNoComment:
            isCommenting = false
        default:
            break
        }
        
        nextNode(resume: resume)
    }
    
    func nextNode(resume: Resume) {
        if let currentFeedbackNode = currentFeedbackNode {
            feedbackNodes.append(currentFeedbackNode)
            feedbackIndex += 1
            Logger.debug("Added node to feedbackNodes. New index: \(feedbackIndex)/\(resumeRevisions.count)")
        }

        if feedbackIndex < resumeRevisions.count {
            Logger.debug("Moving to next node at index \(feedbackIndex)")
            currentRevisionNode = resumeRevisions[feedbackIndex]
            currentFeedbackNode = currentRevisionNode?.createFeedbackNode()
        } else {
            Logger.debug("Reached end of revisionArray. Processing completion...")
            completeReviewWorkflow(with: resume)
        }
    }
    
    func navigateToPrevious() {
        guard feedbackIndex > 0 else { return }
        
        feedbackIndex -= 1
        currentRevisionNode = resumeRevisions[feedbackIndex]
        
        if feedbackIndex < feedbackNodes.count {
            currentFeedbackNode = feedbackNodes[feedbackIndex]
            restoreUIStateFromFeedbackNode(feedbackNodes[feedbackIndex])
        } else {
            currentFeedbackNode = currentRevisionNode?.createFeedbackNode()
            resetUIInteractionState()
        }
        
        Logger.debug("Navigated to previous revision: \(feedbackIndex + 1)/\(resumeRevisions.count)")
    }
    
    func navigateToNext() {
        guard feedbackIndex < resumeRevisions.count - 1 else { return }
        
        if let currentFeedbackNode = currentFeedbackNode, feedbackIndex >= feedbackNodes.count {
            feedbackNodes.append(currentFeedbackNode)
        }
        
        feedbackIndex += 1
        currentRevisionNode = resumeRevisions[feedbackIndex]
        
        if feedbackIndex < feedbackNodes.count {
            currentFeedbackNode = feedbackNodes[feedbackIndex]
            restoreUIStateFromFeedbackNode(feedbackNodes[feedbackIndex])
        } else {
            currentFeedbackNode = currentRevisionNode?.createFeedbackNode()
            resetUIInteractionState()
        }
        
        Logger.debug("Navigated to next revision: \(feedbackIndex + 1)/\(resumeRevisions.count)")
    }
    
    // MARK: - Workflow Completion
    
    func completeReviewWorkflow(with resume: Resume) {
        let nodesToResubmit = workflowService.completeReviewWorkflow(
            feedbackNodes: feedbackNodes,
            resume: resume
        )
        
        if !nodesToResubmit.isEmpty {
            startAIResubmission(with: resume, nodesToResubmit: nodesToResubmit)
        } else {
            showResumeRevisionSheet = false
        }
    }
    
    func startAIResubmission(with resume: Resume, nodesToResubmit: [FeedbackNode]) {
        feedbackNodes = nodesToResubmit
        feedbackIndex = 0
        aiResubmit = true
        
        Task {
            // The actual AI resubmission will be handled by the workflow service
            // This is just updating UI state to show the resubmission is happening
            Logger.debug("AI resubmission UI state updated")
        }
    }
    
    func performAIResubmission(
        with resume: Resume,
        conversationId: UUID,
        modelId: String
    ) async {
        let result = await workflowService.performAIResubmission(
            with: resume,
            feedbackNodes: feedbackNodes,
            conversationId: conversationId,
            modelId: modelId
        )
        
        if result.success {
            resumeRevisions = result.updatedRevisions
            feedbackNodes = []
            feedbackIndex = 0
            
            if !result.updatedRevisions.isEmpty {
                currentRevisionNode = result.updatedRevisions[0]
                currentFeedbackNode = result.updatedRevisions[0].createFeedbackNode()
            }
            
            aiResubmit = false
            Logger.debug("✅ AI resubmission complete: \(result.updatedRevisions.count) new revisions ready for review")
        } else {
            aiResubmit = false
            lastError = result.error
            Logger.error("AI resubmission failed: \(result.error ?? "Unknown error")")
        }
    }
    
    // MARK: - Helper Methods
    
    func initializeUpdateNodes(for resume: Resume) {
        updateNodes = resume.getUpdatableNodes()
    }
    
    func applyAcceptedChanges(to resume: Resume) {
        feedbackNodes.applyAcceptedChanges(to: resume)
    }
    
    // MARK: - UI State Queries
    
    func isNodeAccepted(_ feedbackNode: FeedbackNode?) -> Bool {
        guard let feedbackNode = feedbackNode else { return false }
        let acceptedActions: Set<PostReviewAction> = [.accepted, .acceptedWithChanges, .noChange]
        return acceptedActions.contains(feedbackNode.actionRequested)
    }
    
    func isNodeRejectedWithComments(_ feedbackNode: FeedbackNode?) -> Bool {
        guard let feedbackNode = feedbackNode else { return false }
        return feedbackNode.actionRequested == .revise
    }
    
    func isNodeRejectedWithoutComments(_ feedbackNode: FeedbackNode?) -> Bool {
        guard let feedbackNode = feedbackNode else { return false }
        return feedbackNode.actionRequested == .rewriteNoComment
    }
    
    func isNodeRestored(_ feedbackNode: FeedbackNode?) -> Bool {
        guard let feedbackNode = feedbackNode else { return false }
        return feedbackNode.actionRequested == .restored
    }
    
    func isNodeEdited(_ feedbackNode: FeedbackNode?) -> Bool {
        guard let feedbackNode = feedbackNode else { return false }
        return feedbackNode.actionRequested == .acceptedWithChanges
    }
    
    func isChangeRequested(_ feedbackNode: FeedbackNode?) -> Bool {
        guard let feedbackNode = feedbackNode else { return false }
        let changeRequestedActions: Set<PostReviewAction> = [.mandatedChange, .mandatedChangeNoComment]
        return changeRequestedActions.contains(feedbackNode.actionRequested)
    }
    
    // MARK: - Private Helper Methods
    
    private func restoreUIStateFromFeedbackNode(_ feedbackNode: FeedbackNode) {
        let commentingActions: Set<PostReviewAction> = [.revise, .mandatedChange]
        let moreCommentingActions: Set<PostReviewAction> = [.mandatedChangeNoComment]
        
        if commentingActions.contains(feedbackNode.actionRequested) && !feedbackNode.reviewerComments.isEmpty {
            isCommenting = true
            isMoreCommenting = false
        } else if moreCommentingActions.contains(feedbackNode.actionRequested) && !feedbackNode.reviewerComments.isEmpty {
            isCommenting = false
            isMoreCommenting = true
        } else {
            isCommenting = false
            isMoreCommenting = false
        }
        
        isEditingResponse = false
    }
}