//
//  RevisionNavigationManager.swift
//  Sprung
//
//  Manages navigation through revision nodes during the review workflow.
//  Handles previous/next navigation, saving feedback, and coordinating completion.
//

import Foundation
import SwiftUI

/// Delegate protocol for navigation manager to communicate with the view model
@MainActor
protocol RevisionNavigationDelegate: AnyObject {
    var currentConversationId: UUID? { get }
    var currentModelId: String? { get }
    var openRouterService: OpenRouterService { get }

    func showReviewSheet()
    func hideReviewSheet()
    func startAIResubmission(feedbackNodes: [FeedbackNode], resume: Resume)
    func setWorkflowCompleted()
}

/// Manages the review workflow navigation and feedback collection.
@MainActor
@Observable
class RevisionNavigationManager {
    // MARK: - Dependencies
    private let completionService: RevisionCompletionService
    private let exportCoordinator: ResumeExportCoordinator
    weak var delegate: RevisionNavigationDelegate?

    // MARK: - Navigation State
    var resumeRevisions: [ProposedRevisionNode] = []
    var feedbackNodes: [FeedbackNode] = []
    var approvedFeedbackNodes: [FeedbackNode] = []
    var feedbackIndex: Int = 0
    var currentRevisionNode: ProposedRevisionNode?
    var currentFeedbackNode: FeedbackNode?
    var updateNodes: [[String: Any]] = []

    // MARK: - UI State
    var isEditingResponse: Bool = false
    var isCommenting: Bool = false
    var isMoreCommenting: Bool = false

    // MARK: - Processing State
    private var isCompletingReview: Bool = false

    init(
        completionService: RevisionCompletionService? = nil,
        exportCoordinator: ResumeExportCoordinator
    ) {
        self.completionService = completionService ?? RevisionCompletionService()
        self.exportCoordinator = exportCoordinator
    }

    // MARK: - Setup

    /// Set up revisions for UI review
    func setupRevisionsForReview(_ revisions: [ProposedRevisionNode]) {
        Logger.debug("🔍 [RevisionNavigationManager] setupRevisionsForReview called with \(revisions.count) revisions")

        resumeRevisions = revisions
        feedbackNodes = []
        feedbackIndex = 0

        if !revisions.isEmpty {
            currentRevisionNode = revisions[0]
            currentFeedbackNode = revisions[0].createFeedbackNode()
        }
    }

    /// Initialize updateNodes for the review workflow
    func initializeUpdateNodes(for resume: Resume) {
        updateNodes = resume.getUpdatableNodes()
    }

    /// Reset all navigation state
    func reset() {
        resumeRevisions = []
        feedbackNodes = []
        approvedFeedbackNodes = []
        feedbackIndex = 0
        currentRevisionNode = nil
        currentFeedbackNode = nil
        updateNodes = []
        isEditingResponse = false
        isCommenting = false
        isMoreCommenting = false
        isCompletingReview = false
    }

    // MARK: - Save and Navigate

    /// Save the current feedback and move to next node
    func saveAndNext(response: PostReviewAction, resume: Resume) {
        guard let currentFeedbackNode = currentFeedbackNode else { return }

        // Let the feedback node handle its own action processing
        currentFeedbackNode.processAction(response)

        // Update UI state based on response
        switch response {
        case .acceptedWithChanges:
            isEditingResponse = false
        case .revise, .mandatedChangeNoComment:
            isCommenting = false
        default:
            break
        }

        let hasMore = nextNode(resume: resume)
        if hasMore {
            attemptAutomaticCompletionIfReady(resume: resume)
        }
    }

    /// Move to the next revision node in the workflow
    @discardableResult
    func nextNode(resume: Resume) -> Bool {
        // Add current feedback node to array
        if let currentFeedbackNode = currentFeedbackNode {
            if feedbackIndex < feedbackNodes.count {
                feedbackNodes[feedbackIndex] = currentFeedbackNode
            } else {
                feedbackNodes.append(currentFeedbackNode)
            }
            Logger.debug("Recorded feedback for node index \(feedbackIndex + 1) of \(resumeRevisions.count)")
        } else {
            Logger.warning("⚠️ Tried to advance without a currentFeedbackNode at index \(feedbackIndex)")
        }

        feedbackIndex += 1

        if feedbackIndex < resumeRevisions.count {
            Logger.debug("Moving to next node at index \(feedbackIndex)")
            currentRevisionNode = resumeRevisions[feedbackIndex]
            if feedbackIndex < feedbackNodes.count {
                currentFeedbackNode = feedbackNodes[feedbackIndex]
                restoreUIStateFromFeedbackNode(feedbackNodes[feedbackIndex])
            } else {
                currentFeedbackNode = currentRevisionNode?.createFeedbackNode()
                resetUIState()
            }
            return true
        } else {
            Logger.debug("Reached end of revisionArray. Processing completion...")
            completeReviewWorkflow(with: resume)
            return false
        }
    }

    /// Navigate to previous revision node
    func navigateToPrevious() {
        guard feedbackIndex > 0 else {
            Logger.debug("Cannot navigate to previous: already at first revision")
            return
        }

        if let currentFeedbackNode = currentFeedbackNode {
            if feedbackIndex < feedbackNodes.count {
                feedbackNodes[feedbackIndex] = currentFeedbackNode
            } else {
                feedbackNodes.append(currentFeedbackNode)
            }
        }

        feedbackIndex -= 1
        guard ensureFeedbackIndexInBounds() else { return }

        currentRevisionNode = resumeRevisions[feedbackIndex]

        if feedbackIndex < feedbackNodes.count {
            currentFeedbackNode = feedbackNodes[feedbackIndex]
            restoreUIStateFromFeedbackNode(feedbackNodes[feedbackIndex])
        } else {
            currentFeedbackNode = currentRevisionNode?.createFeedbackNode()
            resetUIState()
        }

        Logger.debug("Navigated to previous revision: \(feedbackIndex + 1)/\(resumeRevisions.count)")
    }

    /// Navigate to next revision node
    func navigateToNext() {
        guard feedbackIndex < resumeRevisions.count - 1 else {
            Logger.debug("Cannot navigate to next: already at last revision")
            return
        }

        if let currentFeedbackNode = currentFeedbackNode {
            if feedbackIndex < feedbackNodes.count {
                feedbackNodes[feedbackIndex] = currentFeedbackNode
            } else {
                feedbackNodes.append(currentFeedbackNode)
            }
        }

        feedbackIndex += 1
        guard ensureFeedbackIndexInBounds() else { return }

        currentRevisionNode = resumeRevisions[feedbackIndex]

        if feedbackIndex < feedbackNodes.count {
            currentFeedbackNode = feedbackNodes[feedbackIndex]
            restoreUIStateFromFeedbackNode(feedbackNodes[feedbackIndex])
        } else {
            currentFeedbackNode = currentRevisionNode?.createFeedbackNode()
            resetUIState()
        }

        Logger.debug("Navigated to next revision: \(feedbackIndex + 1)/\(resumeRevisions.count)")
    }

    // MARK: - Review Completion

    /// Complete the review workflow - apply changes and handle resubmission
    func completeReviewWorkflow(with resume: Resume) {
        guard !isCompletingReview else {
            Logger.debug("⚠️ Ignoring re-entrant completeReviewWorkflow call")
            return
        }

        isCompletingReview = true
        defer { isCompletingReview = false }

        // Use completion service to determine next steps
        let result = completionService.completeReviewWorkflow(
            feedbackNodes: feedbackNodes,
            approvedFeedbackNodes: approvedFeedbackNodes,
            resume: resume,
            exportCoordinator: exportCoordinator
        )

        switch result {
        case .requiresResubmission(let nodesToResubmit, _):
            // Keep only nodes that need AI intervention for the next round
            feedbackNodes = nodesToResubmit
            // Start AI resubmission workflow via delegate
            delegate?.startAIResubmission(feedbackNodes: nodesToResubmit, resume: resume)

        case .finished:
            Logger.debug("No nodes need resubmission. All changes applied, dismissing sheet...")
            // Clear all state before dismissing
            approvedFeedbackNodes = []
            feedbackNodes = []
            resumeRevisions = []
            delegate?.hideReviewSheet()
            delegate?.setWorkflowCompleted()
        }
    }

    /// Handle results from AI resubmission
    func handleResubmissionResults(
        validatedRevisions: [ProposedRevisionNode],
        resubmittedNodeIds: Set<String>
    ) {
        Logger.debug("🔍 Resubmitted \(resubmittedNodeIds.count) nodes, got back \(validatedRevisions.count) revisions")

        // Filter validated revisions to only include ones that were actually requested
        let requestedRevisions = validatedRevisions.filter { revision in
            resubmittedNodeIds.contains(revision.id)
        }

        if requestedRevisions.count != validatedRevisions.count {
            Logger.warning("⚠️ AI returned \(validatedRevisions.count) revisions but only \(requestedRevisions.count) were requested")
        }

        // Store approved feedback for final application
        let approvedFeedbackForLater = feedbackNodes.filter { feedback in
            !resubmittedNodeIds.contains(feedback.id)
        }

        // Replace arrays with only the new revisions requiring review
        resumeRevisions = requestedRevisions
        feedbackNodes = []
        feedbackIndex = 0

        if !resumeRevisions.isEmpty {
            currentRevisionNode = resumeRevisions[0]
            currentFeedbackNode = resumeRevisions[0].createFeedbackNode()
        }

        self.approvedFeedbackNodes = approvedFeedbackForLater

        Logger.debug("✅ Resubmission complete: \(requestedRevisions.count) new revisions ready for review")
    }

    // MARK: - State Inspection

    /// Check if a node was accepted
    func isNodeAccepted(_ feedbackNode: FeedbackNode?) -> Bool {
        guard let feedbackNode = feedbackNode else { return false }
        let acceptedActions: Set<PostReviewAction> = [.accepted, .acceptedWithChanges, .noChange]
        return acceptedActions.contains(feedbackNode.actionRequested)
    }

    /// Check if a node was rejected with comments
    func isNodeRejectedWithComments(_ feedbackNode: FeedbackNode?) -> Bool {
        guard let feedbackNode = feedbackNode else { return false }
        return feedbackNode.actionRequested == .revise
    }

    /// Check if a node was rejected without comments
    func isNodeRejectedWithoutComments(_ feedbackNode: FeedbackNode?) -> Bool {
        guard let feedbackNode = feedbackNode else { return false }
        return feedbackNode.actionRequested == .rewriteNoComment
    }

    /// Check if a node was restored to original
    func isNodeRestored(_ feedbackNode: FeedbackNode?) -> Bool {
        guard let feedbackNode = feedbackNode else { return false }
        return feedbackNode.actionRequested == .restored
    }

    /// Check if a node was edited
    func isNodeEdited(_ feedbackNode: FeedbackNode?) -> Bool {
        guard let feedbackNode = feedbackNode else { return false }
        return feedbackNode.actionRequested == .acceptedWithChanges
    }

    // MARK: - Private Helpers

    private func ensureFeedbackIndexInBounds() -> Bool {
        guard !resumeRevisions.isEmpty else {
            Logger.error("Navigation error: resumeRevisions collection is empty", category: .ui)
            feedbackIndex = 0
            currentRevisionNode = nil
            currentFeedbackNode = nil
            return false
        }

        guard feedbackIndex >= 0 && feedbackIndex < resumeRevisions.count else {
            Logger.error(
                "Navigation error: feedbackIndex \(feedbackIndex) out of bounds for resumeRevisions count \(resumeRevisions.count)",
                category: .ui
            )
            feedbackIndex = max(0, min(feedbackIndex, resumeRevisions.count - 1))
            return false
        }

        return true
    }

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

    private func resetUIState() {
        isCommenting = false
        isMoreCommenting = false
        isEditingResponse = false
    }

    /// Attempt to finish the workflow automatically once every revision has a response
    private func attemptAutomaticCompletionIfReady(resume: Resume) {
        guard !resumeRevisions.isEmpty else { return }
        guard !isCompletingReview else { return }

        guard completionService.allRevisionsHaveResponses(
            feedbackNodes: feedbackNodes,
            resumeRevisions: resumeRevisions
        ) else { return }

        Logger.debug("✅ All revision nodes have responses. Completing workflow automatically.")
        completeReviewWorkflow(with: resume)
    }
}
