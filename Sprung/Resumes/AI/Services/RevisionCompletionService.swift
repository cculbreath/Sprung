//
//  RevisionCompletionService.swift
//  Sprung
//
import Foundation
/// Result of completing a review workflow
enum RevisionCompletionResult {
    case finished
    case requiresResubmission(nodes: [FeedbackNode], prompt: String)
}
/// Service responsible for completing revision workflows and handling resubmission logic
@MainActor
class RevisionCompletionService {
    /// Complete the review workflow by applying changes and determining next steps
    /// - Parameters:
    ///   - feedbackNodes: All feedback collected in current round
    ///   - approvedFeedbackNodes: Previously approved feedback from earlier rounds
    ///   - resume: The resume to apply changes to
    ///   - exportCoordinator: Coordinator for applying changes
    /// - Returns: Completion result indicating whether resubmission is needed
    func completeReviewWorkflow(
        feedbackNodes: [FeedbackNode],
        approvedFeedbackNodes: [FeedbackNode],
        resume: Resume,
        exportCoordinator: ResumeExportCoordinator
    ) -> RevisionCompletionResult {
        // Merge approved feedback from previous rounds with current feedback
        let allFeedbackNodes = approvedFeedbackNodes + feedbackNodes
        // Log statistics and apply changes using all feedback
        allFeedbackNodes.logFeedbackStatistics()
        allFeedbackNodes.applyAcceptedChanges(to: resume, exportCoordinator: exportCoordinator)
        // Check for resubmission using all feedback
        let nodesToResubmit = allFeedbackNodes.nodesRequiringAIResubmission
        if !nodesToResubmit.isEmpty {
            Logger.debug("Resubmitting \(nodesToResubmit.count) nodes to AI...")
            nodesToResubmit.logResubmissionSummary()
            let revisionPrompt = createRevisionPrompt(feedbackNodes: nodesToResubmit)
            return .requiresResubmission(nodes: nodesToResubmit, prompt: revisionPrompt)
        } else {
            Logger.debug("No nodes need resubmission. All changes applied.")
            return .finished
        }
    }
    /// Check if all revisions have been responded to
    /// - Parameters:
    ///   - feedbackNodes: Current feedback nodes
    ///   - resumeRevisions: Original revision nodes
    /// - Returns: True if all revisions have responses
    func allRevisionsHaveResponses(
        feedbackNodes: [FeedbackNode],
        resumeRevisions: [ProposedRevisionNode]
    ) -> Bool {
        guard !resumeRevisions.isEmpty else { return false }
        let respondedIds = feedbackNodes
            .filter { $0.actionRequested != .unevaluated }
            .map { $0.id }
        let respondedSet = Set(respondedIds)
        let expectedSet = Set(resumeRevisions.map { $0.id })
        return expectedSet.isSubset(of: respondedSet)
    }
    // MARK: - Private Helpers
    /// Create a revision prompt from feedback nodes
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
}
