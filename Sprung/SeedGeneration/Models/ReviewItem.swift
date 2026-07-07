//
//  ReviewItem.swift
//  Sprung
//
//  Item in the review queue awaiting user action.
//

import Foundation

/// Item in the review queue awaiting user action
struct ReviewItem: Identifiable, Equatable {
    let id: UUID
    /// The generation task that produced this item
    let task: GenerationTask
    /// The generated content to review
    var generatedContent: GeneratedContent
    /// User's action on this item (nil if not yet acted upon)
    var userAction: UserAction?
    /// User-edited content if they made changes (for scalar values)
    var editedContent: String?
    /// User-edited children if they made changes (for array values like highlights)
    var editedChildren: [String]?
    /// Timestamp when added to queue
    let addedAt: Date
    /// Whether regeneration is in progress
    var isRegenerating: Bool

    init(
        id: UUID = UUID(),
        task: GenerationTask,
        generatedContent: GeneratedContent,
        userAction: UserAction? = nil,
        editedContent: String? = nil,
        editedChildren: [String]? = nil,
        addedAt: Date = Date(),
        isRegenerating: Bool = false
    ) {
        self.id = id
        self.task = task
        self.generatedContent = generatedContent
        self.userAction = userAction
        self.editedContent = editedContent
        self.editedChildren = editedChildren
        self.addedAt = addedAt
        self.isRegenerating = isRegenerating
    }

    /// User action on a review item
    enum UserAction: Equatable {
        case approved
        case rejected
        case rejectedWithComment(String)
        case edited
        /// Regeneration was attempted but failed; item is actionable again
        case regenerationFailed(reason: String)
    }

    /// Whether this item has been acted upon
    var hasAction: Bool {
        userAction != nil
    }

    /// Whether this item was approved
    var isApproved: Bool {
        switch userAction {
        case .approved, .edited:
            return true
        default:
            return false
        }
    }

    /// Whether the generated content should be applied
    var shouldApplyContent: Bool {
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

/// Accumulator for review items awaiting user action
@Observable
@MainActor
final class ReviewQueue {
    /// All items in the queue
    private(set) var items: [ReviewItem] = []

    /// Callback for when an item needs regeneration.
    /// Parameters: (itemId, originalContent, feedback)
    /// Throws on failure so the caller can surface the reason via `.regenerationFailed`.
    var onRegenerationRequested: ((UUID, GeneratedContent, String?) async throws -> GeneratedContent)?

    /// Items pending user action
    var pendingItems: [ReviewItem] {
        items.filter { $0.userAction == nil }
    }

    /// Items that have been approved
    var approvedItems: [ReviewItem] {
        items.filter { $0.isApproved }
    }

    /// Approved items whose IDs are not in `applied` — the set still awaiting
    /// Apply. Lets the module apply incrementally: newly approved items stay
    /// actionable after an earlier Apply, and already-applied items are never
    /// re-applied.
    func approvedItems(excluding applied: Set<UUID>) -> [ReviewItem] {
        approvedItems.filter { !applied.contains($0.id) }
    }

    /// Items that have been rejected
    var rejectedItems: [ReviewItem] {
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

    // MARK: - Queue Management

    /// Add a new item to the queue
    func add(_ item: ReviewItem) {
        items.append(item)
    }

    /// Add a task result to the queue
    func add(task: GenerationTask, content: GeneratedContent) {
        let item = ReviewItem(task: task, generatedContent: content)
        items.append(item)
    }

    /// Set user action for an item
    func setAction(for itemId: UUID, action: ReviewItem.UserAction) {
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
    private func triggerRegeneration(for item: ReviewItem, feedback: String?) async {
        guard let onRegenerationRequested else {
            Logger.warning("ReviewQueue: No regeneration callback configured", category: .ai)
            if let index = items.firstIndex(where: { $0.id == item.id }) {
                items[index].isRegenerating = false
                items[index].userAction = .regenerationFailed(reason: "Regeneration is not available — please restart seed generation.")
            }
            return
        }

        Logger.info("🔄 Triggering regeneration for: \(item.task.displayName)", category: .ai)

        do {
            let newContent = try await onRegenerationRequested(item.id, item.generatedContent, feedback)
            let newItem = ReviewItem(
                task: item.task,
                generatedContent: newContent
            )

            if let index = items.firstIndex(where: { $0.id == item.id }) {
                items[index] = newItem
            } else {
                items.append(newItem)
            }
            Logger.info("✅ Regeneration complete for: \(item.task.displayName)", category: .ai)
        } catch {
            if let index = items.firstIndex(where: { $0.id == item.id }) {
                items[index].isRegenerating = false
                items[index].userAction = .regenerationFailed(reason: error.localizedDescription)
            }
            Logger.error("❌ Regeneration failed for: \(item.task.displayName) — \(error.localizedDescription)", category: .ai)
        }
    }

    /// Set edited content for an item (scalar values)
    func setEditedContent(for itemId: UUID, content: String) {
        if let index = items.firstIndex(where: { $0.id == itemId }) {
            items[index].editedContent = content
            items[index].userAction = .edited
        }
    }

    /// Set edited children for an item (array values like highlights)
    func setEditedChildren(for itemId: UUID, children: [String]) {
        if let index = items.firstIndex(where: { $0.id == itemId }) {
            items[index].editedChildren = children
            items[index].userAction = .edited
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
    func item(for id: UUID) -> ReviewItem? {
        items.first { $0.id == id }
    }
}
