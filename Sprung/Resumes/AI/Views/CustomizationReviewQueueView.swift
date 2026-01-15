//
//  CustomizationReviewQueueView.swift
//  Sprung
//
//  SGM-style accumulating review UI for resume customization.
//  Displays items as they stream in from parallel execution.
//

import SwiftUI

// MARK: - Main Review Queue View

struct CustomizationReviewQueueView: View {
    @Bindable var reviewQueue: CustomizationReviewQueue
    let onComplete: () -> Void
    let onCancel: () -> Void

    @State private var filter: ReviewFilter = .pending
    @State private var expandedItemId: UUID?

    enum ReviewFilter: String, CaseIterable {
        case pending = "Pending"
        case approved = "Approved"
        case rejected = "Rejected"
        case all = "All"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with progress
            headerView

            Divider()

            // Filter tabs
            filterTabs

            // Scrollable list of review cards
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(filteredItems) { item in
                        CustomizationReviewCard(
                            item: item,
                            isExpanded: expandedItemId == item.id,
                            onToggleExpand: { expandedItemId = expandedItemId == item.id ? nil : item.id },
                            onApprove: { reviewQueue.setAction(for: item.id, action: .approved) },
                            onReject: { feedback in
                                if let feedback = feedback, !feedback.isEmpty {
                                    reviewQueue.setAction(for: item.id, action: .rejectedWithComment(feedback))
                                } else {
                                    reviewQueue.setAction(for: item.id, action: .rejected)
                                }
                            },
                            onEdit: { content in
                                reviewQueue.setEditedContent(for: item.id, content: content)
                            }
                        )
                    }
                }
                .padding()
            }

            Divider()

            // Footer with batch actions
            footerView
        }
        .frame(minWidth: 700, idealWidth: 850, maxWidth: 950)
        .frame(minHeight: 500, idealHeight: 650, maxHeight: 800)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Header View

    private var headerView: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "checklist")
                    .font(.system(size: 24))
                    .foregroundStyle(.blue)

                Text("Review Customizations")
                    .font(.system(.title2, design: .rounded, weight: .semibold))

                Spacer()

                // Item count badge
                Text("\(reviewQueue.items.count) items")
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.secondary.opacity(0.1))
                    .clipShape(Capsule())
            }

            // Progress bar
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Reviewing \(reviewedCount) of \(reviewQueue.items.count) items")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(progressPercentage)%")
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        .foregroundStyle(.blue)
                }

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.secondary.opacity(0.2))
                            .frame(height: 8)

                        // Progress
                        RoundedRectangle(cornerRadius: 4)
                            .fill(LinearGradient(
                                colors: [.blue, .cyan],
                                startPoint: .leading,
                                endPoint: .trailing
                            ))
                            .frame(width: geometry.size.width * progressFraction, height: 8)
                    }
                }
                .frame(height: 8)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    // MARK: - Filter Tabs

    private var filterTabs: some View {
        HStack(spacing: 0) {
            ForEach(ReviewFilter.allCases, id: \.self) { filterOption in
                filterTab(for: filterOption)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.secondary.opacity(0.05))
    }

    private func filterTab(for filterOption: ReviewFilter) -> some View {
        let count = itemCount(for: filterOption)
        let isSelected = filter == filterOption

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                filter = filterOption
            }
        } label: {
            HStack(spacing: 6) {
                Text(filterOption.rawValue)
                    .font(.system(.subheadline, design: .rounded, weight: isSelected ? .semibold : .regular))

                if count > 0 {
                    Text("\(count)")
                        .font(.system(.caption2, design: .rounded, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(badgeColor(for: filterOption).opacity(0.2))
                        .foregroundStyle(badgeColor(for: filterOption))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? .blue.opacity(0.1) : .clear)
            .foregroundStyle(isSelected ? .blue : .secondary)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Footer View

    private var footerView: some View {
        HStack(spacing: 12) {
            Button("Cancel") {
                onCancel()
            }
            .buttonStyle(.bordered)

            Spacer()

            Button("Approve All Pending") {
                reviewQueue.approveAll()
            }
            .buttonStyle(.bordered)
            .disabled(reviewQueue.pendingItems.isEmpty)

            Button("Complete Review") {
                onComplete()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!reviewQueue.allItemsReviewed)
        }
        .padding(16)
    }

    // MARK: - Computed Properties

    private var filteredItems: [CustomizationReviewItem] {
        switch filter {
        case .pending: return reviewQueue.pendingItems
        case .approved: return reviewQueue.approvedItems
        case .rejected: return reviewQueue.rejectedItems
        case .all: return reviewQueue.items
        }
    }

    private var reviewedCount: Int {
        reviewQueue.items.filter { $0.hasAction }.count
    }

    private var progressFraction: CGFloat {
        guard !reviewQueue.items.isEmpty else { return 0 }
        return CGFloat(reviewedCount) / CGFloat(reviewQueue.items.count)
    }

    private var progressPercentage: Int {
        Int(progressFraction * 100)
    }

    private func itemCount(for filterOption: ReviewFilter) -> Int {
        switch filterOption {
        case .pending: return reviewQueue.pendingItems.count
        case .approved: return reviewQueue.approvedItems.count
        case .rejected: return reviewQueue.rejectedItems.count
        case .all: return reviewQueue.items.count
        }
    }

    private func badgeColor(for filterOption: ReviewFilter) -> Color {
        switch filterOption {
        case .pending: return .gray
        case .approved: return .green
        case .rejected: return .orange
        case .all: return .blue
        }
    }
}

// MARK: - Review Card View

struct CustomizationReviewCard: View {
    let item: CustomizationReviewItem
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    let onApprove: () -> Void
    let onReject: (String?) -> Void
    let onEdit: (String) -> Void

    @State private var editedContent: String = ""
    @State private var isEditing: Bool = false
    @State private var rejectionFeedback: String = ""
    @State private var showRejectionSheet: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header: display name + status badge + regenerating indicator
            HStack {
                Text(item.task.revNode.displayName)
                    .font(.system(.headline, design: .rounded))
                    .lineLimit(1)

                Spacer()

                statusBadge

                if item.isRegenerating {
                    ProgressView()
                        .scaleEffect(0.7)
                        .padding(.leading, 4)
                }

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }
            .contentShape(Rectangle())
            .onTapGesture { onToggleExpand() }

            if isExpanded {
                expandedContent
            }
        }
        .padding(16)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(cardBorderColor.opacity(0.3), lineWidth: 1)
        )
        .sheet(isPresented: $showRejectionSheet) {
            RejectionFeedbackSheet(
                feedback: $rejectionFeedback,
                onSubmit: {
                    onReject(rejectionFeedback.isEmpty ? nil : rejectionFeedback)
                    showRejectionSheet = false
                    rejectionFeedback = ""
                },
                onCancel: { showRejectionSheet = false }
            )
        }
    }

    // MARK: - Expanded Content

    @ViewBuilder
    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
                .padding(.vertical, 4)

            // Original value (read-only, dimmed)
            GroupBox {
                Text(item.revision.oldValue.isEmpty ? "(empty)" : item.revision.oldValue)
                    .font(.system(.body, design: .rounded))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Label("Original", systemImage: "doc.text")
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            // Proposed value (editable if editing)
            GroupBox {
                if isEditing {
                    TextEditor(text: $editedContent)
                        .font(.system(.body, design: .rounded))
                        .frame(minHeight: 60)
                        .scrollContentBackground(.hidden)
                } else {
                    Text(item.revision.newValue.isEmpty ? "(empty)" : item.revision.newValue)
                        .font(.system(.body, design: .rounded))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } label: {
                Label("Proposed", systemImage: "sparkles")
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(.blue)
            }

            // Why explanation
            if !item.revision.why.isEmpty {
                GroupBox {
                    Text(item.revision.why)
                        .font(.system(.callout, design: .rounded))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Label("Rationale", systemImage: "lightbulb")
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        .foregroundStyle(.purple)
                }
            }

            // Action buttons (only if pending and not regenerating)
            if item.userAction == nil && !item.isRegenerating {
                actionButtons
            }

            // Show regeneration count if item has been regenerated
            if item.regenerationCount > 0 {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 12))
                    Text("Regenerated \(item.regenerationCount) time(s)")
                        .font(.system(.caption, design: .rounded))
                }
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                onApprove()
            } label: {
                Label("Approve", systemImage: "checkmark")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            Button {
                if isEditing {
                    onEdit(editedContent)
                    isEditing = false
                } else {
                    editedContent = item.revision.newValue
                    isEditing = true
                }
            } label: {
                Label(isEditing ? "Save Edit" : "Edit", systemImage: isEditing ? "checkmark.circle" : "pencil")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            if isEditing {
                Button {
                    isEditing = false
                    editedContent = ""
                } label: {
                    Label("Cancel", systemImage: "xmark")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Button {
                showRejectionSheet = true
            } label: {
                Label("Reject", systemImage: "xmark.circle")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .foregroundStyle(.orange)
        }
        .padding(.top, 8)
    }

    // MARK: - Status Badge

    @ViewBuilder
    private var statusBadge: some View {
        let (text, color) = statusInfo

        Text(text)
            .font(.system(.caption2, design: .rounded, weight: .medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private var statusInfo: (String, Color) {
        if item.isRegenerating {
            return ("Regenerating", .blue)
        }

        switch item.userAction {
        case .approved:
            return ("Approved", .green)
        case .edited:
            return ("Edited", .green)
        case .rejected:
            return ("Rejected", .orange)
        case .rejectedWithComment:
            return ("Rejected w/ Feedback", .orange)
        case nil:
            return ("Pending", .gray)
        }
    }

    // MARK: - Card Styling

    private var cardBackground: Color {
        if item.isRegenerating {
            return Color.blue.opacity(0.05)
        }

        switch item.userAction {
        case .approved, .edited:
            return Color.green.opacity(0.05)
        case .rejected, .rejectedWithComment:
            return Color.orange.opacity(0.05)
        case nil:
            return Color(NSColor.controlBackgroundColor)
        }
    }

    private var cardBorderColor: Color {
        if item.isRegenerating {
            return .blue
        }

        switch item.userAction {
        case .approved, .edited:
            return .green
        case .rejected, .rejectedWithComment:
            return .orange
        case nil:
            return .gray
        }
    }
}

// MARK: - Rejection Feedback Sheet

struct RejectionFeedbackSheet: View {
    @Binding var feedback: String
    let onSubmit: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "bubble.left.and.exclamationmark.bubble.right")
                    .font(.system(size: 32))
                    .foregroundStyle(.orange)

                Text("Rejection Feedback")
                    .font(.system(.title3, design: .rounded, weight: .semibold))

                Text("Provide feedback to help improve the regenerated content (optional)")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Feedback text editor
            TextEditor(text: $feedback)
                .font(.system(.body, design: .rounded))
                .frame(minHeight: 100)
                .padding(8)
                .background(Color(NSColor.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )

            // Action buttons
            HStack(spacing: 12) {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)

                Spacer()

                Button("Reject Without Feedback") {
                    feedback = ""
                    onSubmit()
                }
                .buttonStyle(.bordered)
                .foregroundStyle(.orange)

                Button("Reject With Feedback", action: onSubmit)
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(feedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 450, height: 320)
        .background(Color(NSColor.windowBackgroundColor))
    }
}
