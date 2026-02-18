//
//  PhaseReviewItemHandler.swift
//  Sprung
//
//  Handles item-level decisions and navigation within a phase review round.
//  All methods operate on PhaseReviewState and have no LLM or tree-traversal dependencies.
//

import Foundation
import SwiftData

/// Handles item-level decisions and navigation within a phase review round.
/// All methods operate on PhaseReviewState and have no LLM or tree-traversal dependencies.
@MainActor
struct PhaseReviewItemHandler {

    // MARK: - Item Decisions

    /// Accept current review item and move to next. Returns true if the phase is now complete.
    func acceptCurrentItem(in state: inout PhaseReviewState, resume: Resume, context: ModelContext) -> Bool {
        guard var currentReview = state.currentReview,
              state.currentItemIndex < currentReview.items.count else { return false }

        currentReview.items[state.currentItemIndex].userDecision = .accepted
        state.currentReview = currentReview

        state.currentItemIndex += 1

        return state.currentItemIndex >= currentReview.items.count
    }

    /// Reject current review item and move to next.
    /// Marks for LLM resubmission without feedback.
    func rejectCurrentItem(in state: inout PhaseReviewState) {
        guard var currentReview = state.currentReview,
              state.currentItemIndex < currentReview.items.count else { return }

        currentReview.items[state.currentItemIndex].userDecision = .rejected
        state.currentReview = currentReview

        state.currentItemIndex += 1
    }

    /// Reject current review item with feedback and move to next.
    /// Marks for LLM resubmission with user feedback.
    func rejectCurrentItemWithFeedback(_ feedback: String, in state: inout PhaseReviewState) {
        guard var currentReview = state.currentReview,
              state.currentItemIndex < currentReview.items.count else { return }

        currentReview.items[state.currentItemIndex].userDecision = .rejectedWithFeedback
        currentReview.items[state.currentItemIndex].userComment = feedback
        state.currentReview = currentReview

        state.currentItemIndex += 1
    }

    /// Accept current item with user edits and move to next. Returns true if the phase is now complete.
    func acceptCurrentItemWithEdits(
        _ editedValue: String?,
        editedChildren: [String]?,
        in state: inout PhaseReviewState,
        resume: Resume,
        context: ModelContext
    ) -> Bool {
        guard var currentReview = state.currentReview,
              state.currentItemIndex < currentReview.items.count else { return false }

        currentReview.items[state.currentItemIndex].userDecision = .accepted
        currentReview.items[state.currentItemIndex].editedValue = editedValue
        currentReview.items[state.currentItemIndex].editedChildren = editedChildren
        state.currentReview = currentReview

        state.currentItemIndex += 1

        return state.currentItemIndex >= currentReview.items.count
    }

    /// Revert to original value and accept (no change applied). Returns true if the phase is now complete.
    func acceptOriginal(in state: inout PhaseReviewState, resume: Resume, context: ModelContext) -> Bool {
        guard var currentReview = state.currentReview,
              state.currentItemIndex < currentReview.items.count else { return false }

        currentReview.items[state.currentItemIndex].userDecision = .acceptedOriginal
        state.currentReview = currentReview

        state.currentItemIndex += 1

        return state.currentItemIndex >= currentReview.items.count
    }

    // MARK: - Navigation

    /// Navigate to previous item.
    func goToPrevious(in state: inout PhaseReviewState) {
        guard state.currentItemIndex > 0 else { return }
        state.currentItemIndex -= 1
    }

    /// Navigate to next item.
    func goToNext(in state: inout PhaseReviewState) {
        guard let currentReview = state.currentReview,
              state.currentItemIndex < currentReview.items.count - 1 else { return }
        state.currentItemIndex += 1
    }

    /// Check if can navigate to previous item.
    func canGoToPrevious(in state: PhaseReviewState) -> Bool {
        state.currentItemIndex > 0
    }

    /// Check if can navigate to next item.
    func canGoToNext(in state: PhaseReviewState) -> Bool {
        guard let currentReview = state.currentReview else { return false }
        return state.currentItemIndex < currentReview.items.count - 1
    }

    // MARK: - Resubmission Queries

    /// Check if any items need LLM resubmission.
    func hasItemsNeedingResubmission(in state: PhaseReviewState) -> Bool {
        guard let currentReview = state.currentReview else { return false }
        return currentReview.items.contains { $0.userDecision == .rejected || $0.userDecision == .rejectedWithFeedback }
    }

    /// Get items that need resubmission.
    func itemsNeedingResubmission(in state: PhaseReviewState) -> [PhaseReviewItem] {
        guard let currentReview = state.currentReview else { return [] }
        return currentReview.items.filter { $0.userDecision == .rejected || $0.userDecision == .rejectedWithFeedback }
    }

    // MARK: - Data Merging

    /// Merge original values from exported nodes into review container items.
    /// LLMs may not reliably echo back original values, so we ensure they're populated from source data.
    func mergeOriginalValues(
        into container: PhaseReviewContainer,
        from nodes: [ExportedReviewNode]
    ) -> PhaseReviewContainer {
        let nodeById = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })

        let mergedItems = container.items.map { item -> PhaseReviewItem in
            var merged = item
            if let sourceNode = nodeById[item.id] {
                // Ensure originalValue is populated
                if merged.originalValue.isEmpty {
                    merged.originalValue = sourceNode.value
                }
                // Ensure originalChildren is populated for containers
                if merged.originalChildren == nil || merged.originalChildren?.isEmpty == true {
                    merged.originalChildren = sourceNode.childValues
                }
                // Thread sourceNodeIds for bundled items (needed to apply changes back to tree)
                if sourceNode.isBundled, let ids = sourceNode.sourceNodeIds {
                    merged.sourceNodeIds = ids
                }
            }
            return merged
        }

        return PhaseReviewContainer(
            section: container.section,
            phaseNumber: container.phaseNumber,
            fieldPath: container.fieldPath,
            isBundled: container.isBundled,
            items: mergedItems
        )
    }

    /// Replace the current review with ONLY the rejected items that were resubmitted.
    /// Accepted items have already been applied to the tree and must not reappear.
    func mergeResubmissionResults(
        _ resubmission: PhaseReviewContainer,
        into original: PhaseReviewContainer
    ) -> PhaseReviewContainer {
        // Build lookup of rejected items to preserve their originalValue
        let originalRejectedById = Dictionary(
            uniqueKeysWithValues: original.items
                .filter { $0.userDecision == .rejected || $0.userDecision == .rejectedWithFeedback }
                .map { ($0.id, $0) }
        )
        let rejectedIds = Set(originalRejectedById.keys)

        // Only include LLM proposals that correspond to actually-rejected items.
        // The LLM may hallucinate proposals for approved items -- discard those.
        var newItems: [PhaseReviewItem] = []
        for newProposal in resubmission.items {
            guard rejectedIds.contains(newProposal.id) else {
                Logger.warning("\u{26a0}\u{fe0f} Discarding LLM proposal for non-rejected item '\(newProposal.displayName)' (id: \(newProposal.id))")
                continue
            }
            let originalItem = originalRejectedById[newProposal.id]
            let item = PhaseReviewItem(
                id: newProposal.id,
                displayName: newProposal.displayName,
                originalValue: originalItem?.originalValue ?? newProposal.originalValue,
                proposedValue: newProposal.proposedValue,
                action: newProposal.action,
                reason: newProposal.reason,
                userDecision: .pending,
                userComment: "",
                editedValue: nil,
                editedChildren: nil,
                originalChildren: originalItem?.originalChildren ?? newProposal.originalChildren,
                proposedChildren: newProposal.proposedChildren,
                sourceNodeIds: originalItem?.sourceNodeIds
            )
            newItems.append(item)
            Logger.debug("\u{1f504} Resubmitted item '\(item.displayName)' ready for re-review")
        }

        // Create fresh review container with only the resubmitted items
        let freshReview = PhaseReviewContainer(
            section: original.section,
            phaseNumber: original.phaseNumber,
            fieldPath: original.fieldPath,
            isBundled: original.isBundled,
            items: newItems
        )

        Logger.info("\u{1f4cb} Review now contains \(newItems.count) resubmitted items for re-review (filtered from \(resubmission.items.count) LLM proposals)")
        return freshReview
    }
}
