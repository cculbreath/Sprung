//
//  ReviewQueueView.swift
//  Sprung
//
//  Scrollable list of items awaiting user review.
//

import SwiftUI

/// View for reviewing generated content items.
/// When `section` is set, shows only that section's items (pending and
/// reviewed) — used as the detail view for sidebar section navigation.
struct ReviewQueueView: View {
    @Bindable var queue: ReviewQueue
    var section: ExperienceSectionKey?
    /// Current target lines per bullet (shown in the rejection sheet)
    var targetBulletLines: Int
    /// Called when the user changes the line target from the rejection sheet
    var onLineTargetChange: (Int) -> Void

    @State private var filterState: FilterState

    init(
        queue: ReviewQueue,
        section: ExperienceSectionKey? = nil,
        targetBulletLines: Int,
        onLineTargetChange: @escaping (Int) -> Void
    ) {
        self.queue = queue
        self.section = section
        self.targetBulletLines = targetBulletLines
        self.onLineTargetChange = onLineTargetChange
        // Section views show everything by default so approved content stays visible
        _filterState = State(initialValue: section == nil ? .pending : .all)
    }

    enum FilterState: String, CaseIterable {
        case pending = "Pending"
        case approved = "Approved"
        // Rejecting an item immediately kicks off a regeneration that replaces
        // it, so this state is only ever occupied while that regeneration is
        // in flight — "Regenerating" is the honest label, not "Rejected".
        case regenerating = "Regenerating"
        case all = "All"
    }

    /// Items in scope for this view (all, or one section's)
    private var scopedItems: [ReviewItem] {
        guard let section else { return queue.items }
        return queue.items.filter { $0.task.section == section }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            contentView
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Text(section.map { $0.rawValue.capitalized } ?? "Review Queue")
                .font(.title2)
                .fontWeight(.semibold)

            Spacer()

            filterPicker

            if scopedItems.contains(where: { $0.userAction == nil }) {
                batchActionButtons
            }
        }
        .padding()
    }

    private var filterPicker: some View {
        Picker("Filter", selection: $filterState) {
            ForEach(FilterState.allCases, id: \.self) { state in
                Text(state.rawValue).tag(state)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 300)
    }

    private var batchActionButtons: some View {
        HStack(spacing: 8) {
            Button {
                for item in scopedItems where item.userAction == nil {
                    queue.setAction(for: item.id, action: .approved)
                }
            } label: {
                Label("Approve All", systemImage: "checkmark.circle")
            }
            .buttonStyle(.bordered)
            .tint(.green)

            Button {
                for item in scopedItems where item.userAction == nil {
                    queue.remove(item.id)
                }
            } label: {
                Label("Delete All", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var contentView: some View {
        let filteredItems = filteredItems(for: filterState)

        if filteredItems.isEmpty {
            emptyStateView
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(filteredItems) { item in
                        ReviewItemCard(
                            item: item,
                            targetBulletLines: targetBulletLines,
                            onApprove: {
                                queue.setAction(for: item.id, action: .approved)
                            },
                            onReject: { comment, lineTarget in
                                onLineTargetChange(lineTarget)
                                if let comment = comment {
                                    queue.setAction(for: item.id, action: .rejectedWithComment(comment))
                                } else {
                                    queue.setAction(for: item.id, action: .rejected)
                                }
                            },
                            onEdit: { editedContent in
                                queue.setEditedContent(for: item.id, content: editedContent)
                            },
                            onEditArray: { editedChildren in
                                queue.setEditedChildren(for: item.id, children: editedChildren)
                            },
                            onDelete: {
                                queue.remove(item.id)
                            }
                        )
                    }
                }
                .padding()
            }
        }
    }

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label(emptyStateTitle, systemImage: emptyStateIcon)
        } description: {
            Text(emptyStateDescription)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Filtering

    private func filteredItems(for state: FilterState) -> [ReviewItem] {
        switch state {
        case .pending:
            return scopedItems.filter { $0.userAction == nil }
        case .approved:
            return scopedItems.filter { $0.isApproved }
        case .regenerating:
            return scopedItems.filter { $0.isRejected }
        case .all:
            return scopedItems
        }
    }

    private var emptyStateTitle: String {
        switch filterState {
        case .pending: return "No Pending Items"
        case .approved: return "No Approved Items"
        case .regenerating: return "Nothing Regenerating"
        case .all: return "Queue is Empty"
        }
    }

    private var emptyStateIcon: String {
        switch filterState {
        case .pending: return "tray"
        case .approved: return "checkmark.circle"
        case .regenerating: return "arrow.triangle.2.circlepath"
        case .all: return "tray"
        }
    }

    private var emptyStateDescription: String {
        switch filterState {
        case .pending: return "All items have been reviewed."
        case .approved: return "No items have been approved yet."
        case .regenerating: return "No items are currently regenerating."
        case .all: return "Generate content to start reviewing."
        }
    }
}
