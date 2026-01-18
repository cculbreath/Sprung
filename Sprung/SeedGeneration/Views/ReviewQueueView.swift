//
//  ReviewQueueView.swift
//  Sprung
//
//  Scrollable list of items awaiting user review.
//

import SwiftUI

/// View for reviewing generated content items
struct ReviewQueueView: View {
    @Bindable var queue: ReviewQueue

    @State private var filterState: FilterState = .pending

    enum FilterState: String, CaseIterable {
        case pending = "Pending"
        case approved = "Approved"
        case rejected = "Rejected"
        case all = "All"
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
            Text("Review Queue")
                .font(.title2)
                .fontWeight(.semibold)

            Spacer()

            filterPicker

            if queue.hasPendingItems {
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
                queue.approveAll()
            } label: {
                Label("Approve All", systemImage: "checkmark.circle")
            }
            .buttonStyle(.bordered)
            .tint(.green)

            Button {
                queue.rejectAll()
            } label: {
                Label("Reject All", systemImage: "xmark.circle")
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
                            onApprove: {
                                queue.setAction(for: item.id, action: .approved)
                            },
                            onReject: { comment in
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
            return queue.pendingItems
        case .approved:
            return queue.approvedItems
        case .rejected:
            return queue.rejectedItems
        case .all:
            return queue.items
        }
    }

    private var emptyStateTitle: String {
        switch filterState {
        case .pending: return "No Pending Items"
        case .approved: return "No Approved Items"
        case .rejected: return "No Rejected Items"
        case .all: return "Queue is Empty"
        }
    }

    private var emptyStateIcon: String {
        switch filterState {
        case .pending: return "tray"
        case .approved: return "checkmark.circle"
        case .rejected: return "xmark.circle"
        case .all: return "tray"
        }
    }

    private var emptyStateDescription: String {
        switch filterState {
        case .pending: return "All items have been reviewed."
        case .approved: return "No items have been approved yet."
        case .rejected: return "No items have been rejected."
        case .all: return "Generate content to start reviewing."
        }
    }
}
