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
    let generatedContent: GeneratedContent
    /// User's action on this item (nil if not yet acted upon)
    var userAction: UserAction?
    /// User-edited content if they made changes
    var editedContent: String?
    /// Timestamp when added to queue
    let addedAt: Date

    init(
        id: UUID = UUID(),
        task: GenerationTask,
        generatedContent: GeneratedContent,
        userAction: UserAction? = nil,
        editedContent: String? = nil,
        addedAt: Date = Date()
    ) {
        self.id = id
        self.task = task
        self.generatedContent = generatedContent
        self.userAction = userAction
        self.editedContent = editedContent
        self.addedAt = addedAt
    }

    /// User action on a review item
    enum UserAction: Equatable {
        case approved
        case rejected
        case rejectedWithComment(String)
        case edited
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

/// Accumulator for review items awaiting user action
@Observable
@MainActor
final class ReviewQueue {
    /// All items in the queue
    private(set) var items: [ReviewItem] = []

    /// Items pending user action
    var pendingItems: [ReviewItem] {
        items.filter { $0.userAction == nil }
    }

    /// Items that have been approved
    var approvedItems: [ReviewItem] {
        items.filter { $0.isApproved }
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
        if let index = items.firstIndex(where: { $0.id == itemId }) {
            items[index].userAction = action
        }
    }

    /// Set edited content for an item
    func setEditedContent(for itemId: UUID, content: String) {
        if let index = items.firstIndex(where: { $0.id == itemId }) {
            items[index].editedContent = content
            items[index].userAction = .edited
        }
    }

    /// Approve all pending items
    func approveAll() {
        for index in items.indices where items[index].userAction == nil {
            items[index].userAction = .approved
        }
    }

    /// Reject all pending items
    func rejectAll() {
        for index in items.indices where items[index].userAction == nil {
            items[index].userAction = .rejected
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
