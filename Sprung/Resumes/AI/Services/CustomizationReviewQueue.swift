//
//  CustomizationReviewQueue.swift
//  Sprung
//
//  Review queue for resume customization workflow.
//  Adapted from SGM's ReviewQueue for the resume customization context.
//

import Foundation

// MARK: - Review Action

/// User action on a customization review item
enum CustomizationReviewAction: Equatable {
    case approved
    case rejected
    case rejectedWithComment(String)
    case edited
}

// MARK: - Review Item

/// Item in the customization review queue
struct CustomizationReviewItem: Identifiable, Equatable {
    let id: UUID
    /// The revision task that produced this item
    let task: RevisionTask
    /// The proposed revision to review
    var revision: ProposedRevisionNode
    /// User's action on this item (nil if not yet acted upon)
    var userAction: CustomizationReviewAction?
    /// User-edited content if they made changes (for scalar nodes)
    var editedContent: String?
    /// User-edited children if they made changes (for container nodes)
    var editedChildren: [String]?
    /// Timestamp when added to queue
    let addedAt: Date
    /// Number of times this item has been regenerated
    var regenerationCount: Int
    /// Whether regeneration is in progress
    var isRegenerating: Bool
    /// ID of the original item if this is a regeneration
    let previousVersionId: UUID?

    init(
        id: UUID = UUID(),
        task: RevisionTask,
        revision: ProposedRevisionNode,
        userAction: CustomizationReviewAction? = nil,
        editedContent: String? = nil,
        editedChildren: [String]? = nil,
        addedAt: Date = Date(),
        regenerationCount: Int = 0,
        isRegenerating: Bool = false,
        previousVersionId: UUID? = nil
    ) {
        self.id = id
        self.task = task
        self.revision = revision
        self.userAction = userAction
        self.editedContent = editedContent
        self.editedChildren = editedChildren
        self.addedAt = addedAt
        self.regenerationCount = regenerationCount
        self.isRegenerating = isRegenerating
        self.previousVersionId = previousVersionId
    }

    /// Whether this item has been acted upon
    var hasAction: Bool {
        userAction != nil
    }

    /// Whether this item was approved (with or without edits)
    var isApproved: Bool {
        switch userAction {
        case .approved, .edited:
            return true
        default:
            return false
        }
    }

    /// Whether this item was rejected
    var isRejected: Bool {
        switch userAction {
        case .rejected, .rejectedWithComment:
            return true
        default:
            return false
        }
    }
}

// MARK: - Review Queue

/// Accumulator for customization review items awaiting user action
@Observable
@MainActor
final class CustomizationReviewQueue {
    /// All items in the queue
    private(set) var items: [CustomizationReviewItem] = []

    /// Callback for when an item needs regeneration
    /// Parameters: (itemId, originalRevision, feedback) -> regenerated revision or nil
    var onRegenerationRequested: ((UUID, ProposedRevisionNode, String?) async -> ProposedRevisionNode?)?

    // MARK: - Computed Properties

    /// Items pending user action
    var pendingItems: [CustomizationReviewItem] {
        items.filter { $0.userAction == nil }
    }

    /// Items that have been approved
    var approvedItems: [CustomizationReviewItem] {
        items.filter { $0.isApproved }
    }

    /// Items that have been rejected
    var rejectedItems: [CustomizationReviewItem] {
        items.filter { $0.isRejected }
    }

    /// Whether there are any items in the queue
    var hasItems: Bool {
        !items.isEmpty
    }

    /// Whether there are pending items
    var hasPendingItems: Bool {
        !pendingItems.isEmpty
    }

    /// Count of pending items
    var pendingCount: Int {
        pendingItems.count
    }

    /// True when all items have been reviewed (no pending items remain)
    var allItemsReviewed: Bool {
        !items.isEmpty && pendingItems.isEmpty
    }

    // MARK: - Queue Management

    /// Add a new item to the queue
    func add(_ item: CustomizationReviewItem) {
        items.append(item)
    }

    /// Add a task result to the queue
    func add(task: RevisionTask, revision: ProposedRevisionNode) {
        let item = CustomizationReviewItem(task: task, revision: revision)
        items.append(item)
    }

    /// Set user action for an item
    func setAction(for itemId: UUID, action: CustomizationReviewAction) {
        guard let index = items.firstIndex(where: { $0.id == itemId }) else { return }

        items[index].userAction = action

        // If rejected, trigger regeneration
        switch action {
        case .rejected, .rejectedWithComment:
            let feedback: String? = {
                if case .rejectedWithComment(let comment) = action {
                    return comment
                }
                return nil
            }()

            // Mark as regenerating
            items[index].isRegenerating = true

            // Trigger regeneration asynchronously
            let item = items[index]
            Task { [weak self] in
                guard let self else { return }
                await self.triggerRegeneration(for: item, feedback: feedback)
            }

        default:
            break
        }
    }

    /// Trigger regeneration for a rejected item
    private func triggerRegeneration(for item: CustomizationReviewItem, feedback: String?) async {
        guard let onRegenerationRequested else {
            Logger.warning("CustomizationReviewQueue: No regeneration callback configured", category: .ai)
            return
        }

        Logger.info("Triggering regeneration for: \(item.task.revNode.displayName)", category: .ai)

        // Request regeneration
        if let newRevision = await onRegenerationRequested(item.id, item.revision, feedback) {
            // Add the regenerated content as a new item
            let newItem = CustomizationReviewItem(
                task: item.task,
                revision: newRevision,
                regenerationCount: item.regenerationCount + 1,
                previousVersionId: item.id
            )

            // Update original item to no longer be regenerating
            if let index = items.firstIndex(where: { $0.id == item.id }) {
                items[index].isRegenerating = false
            }

            // Add the new item
            items.append(newItem)
            Logger.info("Regeneration complete for: \(item.task.revNode.displayName)", category: .ai)
        } else {
            // Regeneration failed - mark as no longer regenerating
            if let index = items.firstIndex(where: { $0.id == item.id }) {
                items[index].isRegenerating = false
            }
            Logger.error("Regeneration failed for: \(item.task.revNode.displayName)", category: .ai)
        }
    }

    /// Set edited content for an item (for scalar nodes)
    func setEditedContent(for itemId: UUID, content: String) {
        if let index = items.firstIndex(where: { $0.id == itemId }) {
            items[index].editedContent = content
            items[index].userAction = .edited
        }
    }

    /// Set edited children for an item (for container nodes)
    func setEditedChildren(for itemId: UUID, children: [String]) {
        if let index = items.firstIndex(where: { $0.id == itemId }) {
            items[index].editedChildren = children
            items[index].userAction = .edited
        }
    }

    /// Approve all pending items
    func approveAll() {
        for index in items.indices where items[index].userAction == nil {
            items[index].userAction = .approved
        }
    }

    /// Remove an item from the queue
    func remove(_ itemId: UUID) {
        items.removeAll { $0.id == itemId }
    }

    /// Clear all items from the queue
    func clear() {
        items.removeAll()
    }

    /// Get item by ID
    func item(for id: UUID) -> CustomizationReviewItem? {
        items.first { $0.id == id }
    }
}
