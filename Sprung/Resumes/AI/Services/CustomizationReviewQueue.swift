//
//  CustomizationReviewQueue.swift
//  Sprung
//
//  Review queue for resume customization workflow.
//  Supports compound groups where related fields are reviewed together.
//

import Foundation

// MARK: - Review Action

/// User action on a customization review item
enum CustomizationReviewAction: Equatable {
    case approved
    case rejected
    case rejectedWithComment(String)
    case edited
    case useOriginal  // Keep original value, do not regenerate
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
    /// Compound group ID (non-nil if this item belongs to a compound group)
    let compoundGroupId: String?

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
        previousVersionId: UUID? = nil,
        compoundGroupId: String? = nil
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
        self.compoundGroupId = compoundGroupId
    }

    /// Whether this item has been acted upon
    var hasAction: Bool {
        userAction != nil
    }

    /// Whether this item was approved (including useOriginal which keeps the original value)
    var isApproved: Bool {
        switch userAction {
        case .approved, .edited, .useOriginal:
            return true
        default:
            return false
        }
    }

    /// Whether the LLM's proposed change should be applied (excludes useOriginal)
    var shouldApplyRevision: Bool {
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

    /// Whether this item belongs to a compound group
    var isCompoundMember: Bool {
        compoundGroupId != nil
    }
}

// MARK: - Compound Group

/// Represents a visual group of compound review items
struct CompoundReviewGroup: Identifiable {
    let id: String  // The compound group ID
    let displayName: String
    var items: [CustomizationReviewItem]

    /// Whether any item in the group is regenerating
    var isRegenerating: Bool {
        items.contains { $0.isRegenerating }
    }

    /// Count of fields in this group
    var fieldCount: Int {
        items.count
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

    /// Callback for compound group regeneration
    /// Parameters: (compoundGroupId, feedback) -> array of regenerated revisions or nil
    var onCompoundRegenerationRequested: ((String, String?) async -> [ProposedRevisionNode]?)?

    /// Most recent regeneration error for UI display. Auto-clears after 10 seconds.
    var lastRegenerationError: (itemId: UUID, displayName: String)?

    // MARK: - Computed Properties

    /// IDs of items replaced by a regenerated version
    private var supersededItemIds: Set<UUID> {
        Set(items.compactMap { $0.previousVersionId })
    }

    /// Items not superseded by a regeneration. Primary data source for UI.
    var activeItems: [CustomizationReviewItem] {
        let superseded = supersededItemIds
        return items.filter { !superseded.contains($0.id) }
    }

    /// Items pending user action
    var pendingItems: [CustomizationReviewItem] {
        activeItems.filter { $0.userAction == nil }
    }

    /// Items that have been approved
    var approvedItems: [CustomizationReviewItem] {
        activeItems.filter { $0.isApproved }
    }

    /// Items that have been rejected
    var rejectedItems: [CustomizationReviewItem] {
        activeItems.filter { $0.isRejected }
    }

    /// Whether there are any items in the queue
    var hasItems: Bool {
        !activeItems.isEmpty
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
        !activeItems.isEmpty && pendingItems.isEmpty
    }

    /// Whether any items have been approved
    var hasApprovedItems: Bool { !approvedItems.isEmpty }

    // MARK: - Compound Group Support

    /// Get active items grouped by compound group ID.
    /// Non-compound items are returned as single-item groups.
    var groupedActiveItems: [CompoundReviewGroup] {
        var groups: [String: [CustomizationReviewItem]] = [:]
        var groupOrder: [String] = []
        var ungroupedItems: [CustomizationReviewItem] = []

        for item in activeItems {
            if let groupId = item.compoundGroupId {
                if groups[groupId] == nil {
                    groupOrder.append(groupId)
                }
                groups[groupId, default: []].append(item)
            } else {
                ungroupedItems.append(item)
            }
        }

        var result: [CompoundReviewGroup] = []

        // Add compound groups in order
        for groupId in groupOrder {
            if let groupItems = groups[groupId] {
                let displayName = groupItems.first?.task.revNode.displayName ?? groupId
                result.append(CompoundReviewGroup(
                    id: groupId,
                    displayName: displayName,
                    items: groupItems
                ))
            }
        }

        // Add ungrouped items as single-item groups
        for item in ungroupedItems {
            result.append(CompoundReviewGroup(
                id: item.id.uuidString,
                displayName: item.task.revNode.displayName,
                items: [item]
            ))
        }

        return result
    }

    /// Get all items belonging to a compound group
    func itemsInCompoundGroup(_ groupId: String) -> [CustomizationReviewItem] {
        activeItems.filter { $0.compoundGroupId == groupId }
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

    /// Add compound task results to the queue as a group
    func addCompoundGroup(
        compoundTask: RevisionTask,
        revisions: [ProposedRevisionNode],
        originalNodes: [ExportedReviewNode]
    ) {
        let groupId = compoundTask.revNode.id  // "compound-<parent path>"

        for (index, revision) in revisions.enumerated() {
            // Build a task for each individual field
            let originalNode: ExportedReviewNode
            if index < originalNodes.count {
                originalNode = originalNodes[index]
            } else {
                // Fallback: use the compound node itself
                originalNode = compoundTask.revNode
            }

            let fieldTask = RevisionTask(
                revNode: originalNode,
                taskPrompt: compoundTask.taskPrompt,
                nodeType: .generic,
                phase: compoundTask.phase
            )

            let item = CustomizationReviewItem(
                task: fieldTask,
                revision: revision,
                compoundGroupId: groupId
            )
            items.append(item)
        }

        Logger.info("Added compound group '\(groupId)' with \(revisions.count) items", category: .ai)
    }

    /// Set user action for an item
    func setAction(for itemId: UUID, action: CustomizationReviewAction) {
        guard let index = items.firstIndex(where: { $0.id == itemId }) else { return }
        if lastRegenerationError?.itemId == itemId { lastRegenerationError = nil }

        items[index].userAction = action

        // If rejected, check if this is a compound group member
        switch action {
        case .rejected, .rejectedWithComment:
            let feedback: String? = {
                if case .rejectedWithComment(let comment) = action {
                    return comment
                }
                return nil
            }()

            let item = items[index]

            if let groupId = item.compoundGroupId {
                // Compound group member: mark all group members as regenerating and trigger group regeneration
                markCompoundGroupRegenerating(groupId: groupId)
                Task { [weak self] in
                    guard let self else { return }
                    await self.triggerCompoundRegeneration(groupId: groupId, feedback: feedback)
                }
            } else {
                // Standard item: regenerate individually
                items[index].isRegenerating = true
                Task { [weak self] in
                    guard let self else { return }
                    await self.triggerRegeneration(for: item, feedback: feedback)
                }
            }

        default:
            // For compound group members, auto-approve the action (approve, edit, useOriginal)
            // for the individual item only -- no cascading
            break
        }
    }

    /// Mark all items in a compound group as regenerating
    private func markCompoundGroupRegenerating(groupId: String) {
        for index in items.indices {
            if items[index].compoundGroupId == groupId {
                items[index].isRegenerating = true
                items[index].userAction = .rejected  // Mark all as rejected for regeneration
            }
        }
    }

    /// Trigger regeneration for a compound group
    private func triggerCompoundRegeneration(groupId: String, feedback: String?) async {
        guard let onCompoundRegenerationRequested else {
            Logger.warning("CustomizationReviewQueue: No compound regeneration callback configured", category: .ai)
            clearCompoundRegenerating(groupId: groupId)
            return
        }

        Logger.info("Triggering compound regeneration for group: \(groupId)", category: .ai)

        if let newRevisions = await onCompoundRegenerationRequested(groupId, feedback) {
            // Get current group items
            let groupItems = items.filter { $0.compoundGroupId == groupId && !supersededItemIds.contains($0.id) }

            // Create new items for each regenerated revision
            for (index, newRevision) in newRevisions.enumerated() {
                guard index < groupItems.count else { break }
                let oldItem = groupItems[index]

                let newItem = CustomizationReviewItem(
                    task: oldItem.task,
                    revision: newRevision,
                    regenerationCount: oldItem.regenerationCount + 1,
                    previousVersionId: oldItem.id,
                    compoundGroupId: groupId
                )

                // Mark original as no longer regenerating
                if let oldIndex = items.firstIndex(where: { $0.id == oldItem.id }) {
                    items[oldIndex].isRegenerating = false
                }

                items.append(newItem)
            }

            Logger.info("Compound regeneration complete for group: \(groupId)", category: .ai)
        } else {
            clearCompoundRegenerating(groupId: groupId)
            Logger.error("Compound regeneration failed for group: \(groupId)", category: .ai)

            if let firstItem = items.first(where: { $0.compoundGroupId == groupId }) {
                lastRegenerationError = (itemId: firstItem.id, displayName: groupId)
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(10))
                    if self?.lastRegenerationError?.itemId == firstItem.id {
                        self?.lastRegenerationError = nil
                    }
                }
            }
        }
    }

    /// Clear regenerating state for all items in a compound group
    private func clearCompoundRegenerating(groupId: String) {
        for index in items.indices {
            if items[index].compoundGroupId == groupId {
                items[index].isRegenerating = false
            }
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
                previousVersionId: item.id,
                compoundGroupId: item.compoundGroupId
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

            lastRegenerationError = (itemId: item.id, displayName: item.task.revNode.displayName)
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(10))
                if self?.lastRegenerationError?.itemId == item.id {
                    self?.lastRegenerationError = nil
                }
            }
        }
    }

    /// Set edited content for an item (for scalar nodes)
    func setEditedContent(for itemId: UUID, content: String) {
        if lastRegenerationError?.itemId == itemId { lastRegenerationError = nil }
        if let index = items.firstIndex(where: { $0.id == itemId }) {
            items[index].editedContent = content
            items[index].userAction = .edited
        }
    }

    /// Set edited children for an item (for container nodes)
    func setEditedChildren(for itemId: UUID, children: [String]) {
        if lastRegenerationError?.itemId == itemId { lastRegenerationError = nil }
        if let index = items.firstIndex(where: { $0.id == itemId }) {
            items[index].editedChildren = children
            items[index].userAction = .edited
        }
    }

    /// Approve all pending items
    func approveAll() {
        let superseded = supersededItemIds
        for index in items.indices where items[index].userAction == nil && !superseded.contains(items[index].id) {
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
        lastRegenerationError = nil
    }

    /// Get item by ID
    func item(for id: UUID) -> CustomizationReviewItem? {
        items.first { $0.id == id }
    }
}
