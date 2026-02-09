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
    let phaseNumber: Int
    let totalPhases: Int
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

            // Scrollable list of review cards with compound grouping
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(filteredGroups) { group in
                        if group.items.count > 1 {
                            // Compound group: shared container with group header
                            CompoundGroupView(
                                group: group,
                                reviewQueue: reviewQueue
                            )
                        } else if let item = group.items.first {
                            // Single item (non-compound)
                            CustomizationReviewCard(
                                item: item,
                                isCompoundMember: false,
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
                                },
                                onUnapprove: {
                                    reviewQueue.unapprove(itemId: item.id)
                                }
                            )
                        }
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
        .alert(
            "Regeneration Failed",
            isPresented: Binding(
                get: { reviewQueue.lastRegenerationError != nil },
                set: { if !$0 { reviewQueue.lastRegenerationError = nil } }
            )
        ) {
            Button("OK") { reviewQueue.lastRegenerationError = nil }
        } message: {
            if let error = reviewQueue.lastRegenerationError {
                Text("Failed to regenerate \"\(error.displayName)\". You can try again or use a different action.")
            }
        }
        .onChange(of: reviewQueue.activeItems.count) { oldCount, newCount in
            if oldCount == 0 && newCount > 0 {
                filter = .pending
            }
        }
        .onChange(of: reviewQueue.allItemsApproved) { _, allApproved in
            if allApproved && phaseNumber < totalPhases {
                Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    onComplete()
                }
            }
        }
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

                if totalPhases > 1 {
                    Text("Phase \(phaseNumber) of \(totalPhases)")
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.orange.opacity(0.1))
                        .clipShape(Capsule())
                }

                Spacer()

                // Item count badge
                Text("\(reviewQueue.activeItems.count) items")
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
                    Text("Reviewing \(reviewedCount) of \(reviewQueue.activeItems.count) items")
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

            if phaseNumber >= totalPhases {
                Button("Complete Review") {
                    onComplete()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!reviewQueue.allItemsApproved)
            }
        }
        .padding(16)
    }

    // MARK: - Computed Properties

    /// Filtered groups based on the current filter selection.
    /// Groups that contain at least one item matching the filter are included.
    private var filteredGroups: [CompoundReviewGroup] {
        let allGroups = reviewQueue.groupedActiveItems

        switch filter {
        case .all:
            return allGroups
        case .pending:
            return allGroups.compactMap { group in
                let filtered = group.items.filter { $0.userAction == nil }
                return filtered.isEmpty ? nil : CompoundReviewGroup(id: group.id, displayName: group.displayName, items: filtered)
            }
        case .approved:
            return allGroups.compactMap { group in
                let filtered = group.items.filter { $0.isApproved }
                return filtered.isEmpty ? nil : CompoundReviewGroup(id: group.id, displayName: group.displayName, items: filtered)
            }
        case .rejected:
            return allGroups.compactMap { group in
                let filtered = group.items.filter { $0.isRejected }
                return filtered.isEmpty ? nil : CompoundReviewGroup(id: group.id, displayName: group.displayName, items: filtered)
            }
        }
    }

    private var filteredItems: [CustomizationReviewItem] {
        switch filter {
        case .pending: return reviewQueue.pendingItems
        case .approved: return reviewQueue.approvedItems
        case .rejected: return reviewQueue.rejectedItems
        case .all: return reviewQueue.activeItems
        }
    }

    private var reviewedCount: Int {
        reviewQueue.activeItems.filter { $0.hasAction }.count
    }

    private var progressFraction: CGFloat {
        guard !reviewQueue.activeItems.isEmpty else { return 0 }
        return CGFloat(reviewedCount) / CGFloat(reviewQueue.activeItems.count)
    }

    private var progressPercentage: Int {
        Int(progressFraction * 100)
    }

    private func itemCount(for filterOption: ReviewFilter) -> Int {
        switch filterOption {
        case .pending: return reviewQueue.pendingItems.count
        case .approved: return reviewQueue.approvedItems.count
        case .rejected: return reviewQueue.rejectedItems.count
        case .all: return reviewQueue.activeItems.count
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

// MARK: - Compound Group View

/// Visual container for a compound group of related review items.
struct CompoundGroupView: View {
    let group: CompoundReviewGroup
    @Bindable var reviewQueue: CustomizationReviewQueue

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Group header
            HStack(spacing: 6) {
                Image(systemName: "rectangle.3.group")
                    .font(.system(size: 12))
                    .foregroundStyle(.indigo)

                Text(group.displayName)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(.indigo)

                Text("\(group.fieldCount) fields")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.indigo.opacity(0.1))
                    .clipShape(Capsule())

                Spacer()

                if group.isRegenerating {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.5)
                        Text("Regenerating group...")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)

            // Note about compound regeneration
            Text("Rejecting any field regenerates the entire group to maintain coherence.")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)

            // Individual items
            ForEach(group.items) { item in
                CustomizationReviewCard(
                    item: item,
                    isCompoundMember: true,
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
                    },
                    onUnapprove: {
                        reviewQueue.unapprove(itemId: item.id)
                    }
                )
                .padding(.horizontal, 6)
            }
        }
        .padding(.bottom, 8)
        .background(.indigo.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.indigo.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Review Card View

struct CustomizationReviewCard: View {
    let item: CustomizationReviewItem
    var isCompoundMember: Bool = false
    let onApprove: () -> Void
    let onReject: (String?) -> Void
    let onEdit: (String) -> Void
    let onEditArray: ([String]) -> Void
    let onUseOriginal: () -> Void
    var onUnapprove: (() -> Void)? = nil

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

    /// Display array: prefers user edits over LLM proposed values
    private var displayContentArray: [String] {
        if let edited = item.editedChildren, !edited.isEmpty {
            return edited
        }
        return contentArray
    }

    /// Display scalar: prefers user edits over LLM proposed value
    private var displayContentScalar: String {
        item.editedContent ?? item.revision.newValue
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

            // Action buttons (hidden while regenerating)
            if !item.isRegenerating {
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
                    if isArrayContent, !displayContentArray.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(displayContentArray, id: \.self) { value in
                                HStack(alignment: .top, spacing: 4) {
                                    Text("\u{2022}")
                                        .foregroundStyle(.blue)
                                    SelectableText(value)
                                        .font(.system(.callout, design: .rounded))
                                }
                            }
                        }
                    } else {
                        SelectableText(displayContentScalar.isEmpty ? "(empty)" : displayContentScalar)
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

    @ViewBuilder
    private var actionButtons: some View {
        if isEditing {
            editingButtons
        } else if item.userAction == nil {
            pendingButtons
        } else if item.isApproved {
            approvedButtons
        }
        // Rejected items: no buttons (regeneration handles them)
    }

    /// Buttons shown while editing (any prior state)
    private var editingButtons: some View {
        HStack(spacing: 8) {
            Button {
                if isArrayContent {
                    let nonEmptyItems = editedItems.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                    onEditArray(nonEmptyItems)
                } else {
                    onEdit(editedContent)
                }
                isEditing = false
            } label: {
                Label("Save", systemImage: "checkmark.circle")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .tint(.green)

            Button {
                isEditing = false
                editedContent = ""
                editedItems = []
            } label: {
                Label("Cancel", systemImage: "xmark")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Spacer()
        }
        .padding(.top, 8)
    }

    /// Buttons shown for pending items (userAction == nil)
    private var pendingButtons: some View {
        HStack(spacing: 8) {
            Button {
                onApprove()
            } label: {
                Label("Approve", systemImage: "checkmark")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .tint(.green)

            Button {
                enterEditMode()
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button {
                onUseOriginal()
            } label: {
                Label("Use Original", systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .foregroundStyle(.secondary)

            Button {
                showRejectionSheet = true
            } label: {
                Label("Regenerate", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .foregroundStyle(.orange)

            Spacer()
        }
        .padding(.top, 8)
    }

    /// Buttons shown for approved items (.approved, .edited, .useOriginal)
    private var approvedButtons: some View {
        HStack(spacing: 8) {
            Button {
                enterEditMode()
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button {
                onUnapprove?()
            } label: {
                Label("Unapprove", systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .foregroundStyle(.orange)

            Spacer()
        }
        .padding(.top, 8)
    }

    /// Pre-populate editors and enter edit mode.
    /// Prefers existing user edits over the LLM's proposed values.
    private func enterEditMode() {
        if isArrayContent {
            if let edited = item.editedChildren, !edited.isEmpty {
                editedItems = edited
            } else {
                editedItems = contentArray.isEmpty ? [""] : contentArray
            }
        } else {
            editedContent = item.editedContent ?? item.revision.newValue
        }
        isEditing = true
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
