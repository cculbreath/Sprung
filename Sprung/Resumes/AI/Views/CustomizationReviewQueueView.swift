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

            // Scrollable list of review cards - compact spacing
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(filteredItems) { item in
                        CustomizationReviewCard(
                            item: item,
                            isExpanded: true,  // Always expanded
                            onToggleExpand: { },  // No-op
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
                            },
                            onEditArray: { children in
                                reviewQueue.setEditedChildren(for: item.id, children: children)
                            },
                            onUseOriginal: {
                                reviewQueue.setAction(for: item.id, action: .useOriginal)
                            }
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
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
    let isExpanded: Bool  // Kept for API compatibility but ignored
    let onToggleExpand: () -> Void  // Kept for API compatibility but ignored
    let onApprove: () -> Void
    let onReject: (String?) -> Void
    let onEdit: (String) -> Void
    let onEditArray: ([String]) -> Void
    let onUseOriginal: () -> Void

    @State private var editedContent: String = ""
    @State private var editedItems: [String] = []
    @State private var isEditing: Bool = false
    @State private var rejectionFeedback: String = ""
    @State private var showRejectionSheet: Bool = false

    /// Whether this content type uses array editing
    private var isArrayContent: Bool {
        item.revision.nodeType == .list ||
        (item.revision.newValueArray != nil && !item.revision.newValueArray!.isEmpty) ||
        (item.task.revNode.sourceNodeIds != nil && !item.task.revNode.sourceNodeIds!.isEmpty)
    }

    /// Get the array elements from the revision
    private var contentArray: [String] {
        item.revision.newValueArray ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header row: name + status + regenerating indicator
            HStack(spacing: 8) {
                Text(item.task.revNode.displayName)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .lineLimit(1)

                Spacer()

                if item.isRegenerating {
                    ProgressView()
                        .scaleEffect(0.6)
                }

                statusBadge
            }

            // Compact content - always visible
            compactContent

            // Action buttons (only if pending and not regenerating)
            if item.userAction == nil && !item.isRegenerating {
                actionButtons
            }

            // Regeneration count (compact)
            if item.regenerationCount > 0 {
                Label("Regenerated \(item.regenerationCount)×", systemImage: "arrow.triangle.2.circlepath")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
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

    // MARK: - Compact Content (always visible, no collapse)

    @ViewBuilder
    private var compactContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Original value - compact inline label
            HStack(alignment: .top, spacing: 6) {
                Text("Was:")
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .trailing)

                if isArrayContent, let oldArray = item.revision.oldValueArray, !oldArray.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(oldArray, id: \.self) { value in
                            HStack(alignment: .top, spacing: 4) {
                                Text("\u{2022}")
                                    .foregroundStyle(.secondary)
                                SelectableText(value)
                                    .font(.system(.callout, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } else {
                    SelectableText(item.revision.oldValue.isEmpty ? "(empty)" : item.revision.oldValue)
                        .font(.system(.callout, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

            // Proposed value - editable or selectable
            HStack(alignment: .top, spacing: 6) {
                Text("Now:")
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(.blue)
                    .frame(width: 36, alignment: .trailing)

                if isEditing {
                    if isArrayContent {
                        arrayEditingView
                    } else {
                        scalarEditingView
                    }
                } else {
                    if isArrayContent, !contentArray.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(contentArray, id: \.self) { value in
                                HStack(alignment: .top, spacing: 4) {
                                    Text("\u{2022}")
                                        .foregroundStyle(.blue)
                                    SelectableText(value)
                                        .font(.system(.callout, design: .rounded))
                                }
                            }
                        }
                    } else {
                        SelectableText(item.revision.newValue.isEmpty ? "(empty)" : item.revision.newValue)
                            .font(.system(.callout, design: .rounded))
                    }
                }
            }

            // Why - only if present, very compact
            if !item.revision.why.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Text("Why:")
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(.purple)
                        .frame(width: 36, alignment: .trailing)

                    SelectableText(item.revision.why)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Editing Views

    /// Editing view for scalar (single text) content
    private var scalarEditingView: some View {
        TextEditor(text: $editedContent)
            .font(.system(.callout, design: .rounded))
            .frame(minHeight: 40)
            .scrollContentBackground(.hidden)
            .padding(4)
            .background(Color(NSColor.textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    /// Editing view for array content (per-element text fields)
    private var arrayEditingView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Spacer()
                Button {
                    editedItems.append("")
                } label: {
                    Label("Add", systemImage: "plus.circle")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }

            ForEach(editedItems.indices, id: \.self) { index in
                HStack(spacing: 6) {
                    Text("\(index + 1).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 18)

                    TextField("Item \(index + 1)", text: $editedItems[index], axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(.callout, design: .rounded))
                        .padding(6)
                        .background(Color(NSColor.textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(.quaternary, lineWidth: 1)
                        )

                    Button {
                        if editedItems.count > 1 {
                            editedItems.remove(at: index)
                        }
                    } label: {
                        Image(systemName: "minus.circle")
                            .foregroundStyle(editedItems.count > 1 ? .red : .gray)
                    }
                    .buttonStyle(.plain)
                    .disabled(editedItems.count <= 1)
                }
            }
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 8) {
            Button {
                onApprove()
            } label: {
                Label("Approve", systemImage: "checkmark")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.mini)

            Button {
                if isEditing {
                    // Save changes
                    if isArrayContent {
                        // Filter out empty items and save
                        let nonEmptyItems = editedItems.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                        onEditArray(nonEmptyItems)
                    } else {
                        onEdit(editedContent)
                    }
                    isEditing = false
                } else {
                    // Start editing
                    if isArrayContent {
                        editedItems = contentArray.isEmpty ? [""] : contentArray
                    } else {
                        editedContent = item.revision.newValue
                    }
                    isEditing = true
                }
            } label: {
                Label(isEditing ? "Save" : "Edit", systemImage: isEditing ? "checkmark.circle" : "pencil")
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)

            if isEditing {
                Button {
                    isEditing = false
                    editedContent = ""
                    editedItems = []
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }

            Button {
                onUseOriginal()
            } label: {
                Label("Use Original", systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .foregroundStyle(.secondary)

            Button {
                showRejectionSheet = true
            } label: {
                Label("Regenerate", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .foregroundStyle(.orange)

            Spacer()
        }
        .padding(.top, 4)
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
        case .useOriginal:
            return ("Kept Original", .gray)
        case .rejected:
            return ("Regenerating", .orange)
        case .rejectedWithComment:
            return ("Regenerating", .orange)
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
        case .useOriginal:
            return Color.gray.opacity(0.05)
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
        case .useOriginal:
            return .gray
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

// MARK: - Selectable Text Helper

/// Text view that allows selection and copying on macOS
struct SelectableText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
