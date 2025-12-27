//
//  PhaseReviewUnbundledView.swift
//  Sprung
//
//  Unbundled review view for manifest-driven multi-phase review.
//  Shows one item at a time for individual review when phase.bundle = false.
//

import SwiftUI
import SwiftData

/// Generic unbundled review: Shows one item at a time for individual review
struct PhaseReviewUnbundledView: View {
    @Bindable var viewModel: ResumeReviseViewModel
    @Binding var resume: Resume?
    @Environment(\.modelContext) private var modelContext
    @State private var showCancelConfirmation = false

    // Edit sheet state
    @State private var showEditSheet = false
    @State private var editedValue: String = ""
    @State private var editedChildren: [String] = []

    // Feedback sheet state
    @State private var showFeedbackSheet = false
    @State private var feedbackText: String = ""

    private var phaseState: PhaseReviewState {
        viewModel.phaseReviewState
    }

    private var currentReview: PhaseReviewContainer? {
        phaseState.currentReview
    }

    private var currentItem: PhaseReviewItem? {
        guard let review = currentReview,
              phaseState.currentItemIndex < review.items.count else { return nil }
        return review.items[phaseState.currentItemIndex]
    }

    /// Check if current item has children (is a container like keywords)
    /// Must have non-empty arrays to be considered a container
    private var isContainerItem: Bool {
        guard let item = currentItem else { return false }
        let hasOriginal = item.originalChildren?.isEmpty == false
        let hasProposed = item.proposedChildren?.isEmpty == false
        return hasOriginal || hasProposed
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection

            Divider()

            if let item = currentItem {
                // Current item diff content
                ScrollView {
                    VStack(spacing: 16) {
                        // Reason/explanation
                        if !item.reason.isEmpty {
                            reasoningSection(item.reason)
                        }

                        // Diff view based on item type
                        // Check for non-nil AND non-empty arrays to determine container vs scalar
                        if let originalChildren = item.originalChildren,
                           let proposedChildren = item.proposedChildren,
                           !(originalChildren.isEmpty && proposedChildren.isEmpty) {
                            // Show children diff (like keywords)
                            childrenDiffView(
                                original: originalChildren,
                                proposed: proposedChildren,
                                itemName: item.displayName
                            )
                        } else {
                            // Show scalar diff (includes items with empty children arrays)
                            scalarDiffView(item: item)
                        }
                    }
                    .padding(24)
                }
                .frame(minHeight: 300, maxHeight: 500)
            } else if viewModel.isProcessingRevisions {
                loadingView
            } else {
                emptyView
            }

            Divider()

            // Action buttons
            actionButtons
        }
        .frame(minWidth: 600, idealWidth: 850, maxWidth: 900)
        .background(Color(NSColor.windowBackgroundColor))
        .confirmationDialog(
            "Cancel Review?",
            isPresented: $showCancelConfirmation,
            titleVisibility: .visible
        ) {
            if viewModel.hasUnappliedApprovedChanges() {
                Button("Apply Approved & Close") {
                    guard let resume = resume else { return }
                    viewModel.applyApprovedChangesAndClose(resume: resume, context: modelContext)
                }
                Button("Discard All", role: .destructive) {
                    viewModel.discardAllAndClose()
                }
                Button("Continue Review", role: .cancel) { }
            } else {
                Button("Discard & Close", role: .destructive) {
                    viewModel.discardAllAndClose()
                }
                Button("Continue Review", role: .cancel) { }
            }
        } message: {
            if viewModel.hasUnappliedApprovedChanges() {
                Text("You have approved changes that haven't been applied yet. Would you like to apply them before closing?")
            } else {
                Text("Are you sure you want to discard all pending changes?")
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "tag")
                    .font(.system(size: 24))
                    .foregroundStyle(.blue)

                Text(currentItem?.displayName ?? "Review")
                    .font(.system(.title2, design: .rounded, weight: .semibold))
            }

            Text("Review suggested changes")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)

            // Phase and item info with navigation
            HStack(spacing: 12) {
                Text("Phase \(phaseState.currentPhaseIndex + 1) of \(phaseState.phases.count)")
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .clipShape(Capsule())

                if let review = currentReview {
                    // Navigation controls
                    HStack(spacing: 4) {
                        Button {
                            viewModel.goToPreviousItem()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(viewModel.canGoToPrevious ? .blue : .gray.opacity(0.4))
                        .disabled(!viewModel.canGoToPrevious)

                        Text("Item \(phaseState.currentItemIndex + 1) of \(review.items.count)")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)

                        Button {
                            viewModel.goToNextItem()
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(viewModel.canGoToNext ? .blue : .gray.opacity(0.4))
                        .disabled(!viewModel.canGoToNext)
                    }
                }
            }

            // Show decision status for current item if already decided
            if let item = currentItem, item.userDecision != .pending {
                decisionStatusBadge(for: item)
            }
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func decisionStatusBadge(for item: PhaseReviewItem) -> some View {
        let (text, color): (String, Color) = switch item.userDecision {
        case .pending: ("Pending", .gray)
        case .accepted: ("Accepted", .green)
        case .acceptedOriginal: ("Kept Original", .blue)
        case .rejected: ("Rejected", .orange)
        case .rejectedWithFeedback: ("Rejected w/ Feedback", .orange)
        }

        Text(text)
            .font(.system(.caption2, design: .rounded, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }

    // MARK: - Reasoning Section

    private func reasoningSection(_ reason: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lightbulb")
                .foregroundStyle(.yellow)
                .padding(.top, 2)
            Text(reason)
                .font(.system(.callout, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.yellow.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Scalar Diff View

    private func scalarDiffView(item: PhaseReviewItem) -> some View {
        VStack(spacing: 16) {
            // Action indicator
            HStack {
                actionIcon(for: item.action)
                Text(actionDescription(for: item.action))
                    .font(.system(.headline, design: .rounded, weight: .medium))
                Spacer()
            }
            .padding(.bottom, 8)

            HStack(alignment: .top, spacing: 20) {
                // Original value
                VStack(alignment: .leading, spacing: 8) {
                    Text("Original")
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Text(item.originalValue)
                        .font(.system(.body, design: .rounded))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .frame(maxWidth: .infinity)

                Divider()

                // Proposed value
                VStack(alignment: .leading, spacing: 8) {
                    Text("Proposed")
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                        .foregroundStyle(.blue)

                    Text(item.proposedValue)
                        .font(.system(.body, design: .rounded))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.green.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Children Diff View

    private func childrenDiffView(original: [String], proposed: [String], itemName: String) -> some View {
        VStack(spacing: 16) {
            // Stats
            DiffStatsView(original: original, proposed: proposed)

            // Side by side diff - use flexible layout with clipping
            HStack(alignment: .top, spacing: 16) {
                // Original values
                VStack(alignment: .leading, spacing: 8) {
                    Text("Original")
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                        .foregroundStyle(.secondary)

                    childrenList(
                        items: original,
                        comparison: proposed,
                        isOriginal: true
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()

                Divider()

                // Proposed values
                VStack(alignment: .leading, spacing: 8) {
                    Text("Proposed")
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                        .foregroundStyle(.blue)

                    childrenList(
                        items: proposed,
                        comparison: original,
                        isOriginal: false
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()
            }
            .frame(maxWidth: .infinity)
            .clipped()
        }
    }

    @ViewBuilder
    private func childrenList(items: [String], comparison: [String], isOriginal: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    // Status indicator - fixed size to prevent compression
                    childStatusIcon(item: item, comparison: comparison, isOriginal: isOriginal)
                        .frame(width: 16, height: 16)

                    Text(item)
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(childTextColor(item: item, comparison: comparison, isOriginal: isOriginal))
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(childBackground(item: item, comparison: comparison, isOriginal: isOriginal))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private func childStatusIcon(item: String, comparison: [String], isOriginal: Bool) -> some View {
        Group {
            if isOriginal {
                if !comparison.contains(item) {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.red)
                } else {
                    Image(systemName: "circle")
                        .foregroundStyle(.gray.opacity(0.3))
                }
            } else {
                if !comparison.contains(item) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: "circle")
                        .foregroundStyle(.gray.opacity(0.3))
                }
            }
        }
        .font(.system(size: 14))
    }

    private func childTextColor(item: String, comparison: [String], isOriginal: Bool) -> Color {
        if isOriginal && !comparison.contains(item) {
            return .red
        } else if !isOriginal && !comparison.contains(item) {
            return .green
        }
        return .primary
    }

    private func childBackground(item: String, comparison: [String], isOriginal: Bool) -> Color {
        if isOriginal && !comparison.contains(item) {
            return Color.red.opacity(0.1)
        } else if !isOriginal && !comparison.contains(item) {
            return Color.green.opacity(0.1)
        }
        return Color.clear
    }

    // MARK: - Action Helpers

    private func actionIcon(for action: ReviewItemAction) -> some View {
        Group {
            switch action {
            case .keep:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .remove:
                Image(systemName: "trash.circle.fill")
                    .foregroundStyle(.red)
            case .modify:
                Image(systemName: "pencil.circle.fill")
                    .foregroundStyle(.orange)
            case .add:
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(.blue)
            }
        }
        .font(.system(size: 20))
    }

    private func actionDescription(for action: ReviewItemAction) -> String {
        switch action {
        case .keep: return "No Changes Needed"
        case .remove: return "Remove This Item"
        case .modify: return "Modify This Item"
        case .add: return "Add New Item"
        }
    }

    // MARK: - Loading/Empty Views

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Analyzing...")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("No items to review")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 12) {
            // Primary action row
            HStack(spacing: 12) {
                // Cancel button
                Button("Cancel Review") {
                    if viewModel.hasUnappliedApprovedChanges() {
                        showCancelConfirmation = true
                    } else {
                        viewModel.discardAllAndClose()
                    }
                }
                .buttonStyle(.bordered)

                Spacer()

                // Reject actions (send back to LLM)
                Menu {
                    Button {
                        viewModel.rejectCurrentItemAndMoveNext()
                        checkPhaseComplete()
                    } label: {
                        Label("Reject (No Comment)", systemImage: "xmark")
                    }

                    Button {
                        feedbackText = ""
                        showFeedbackSheet = true
                    } label: {
                        Label("Reject with Feedback...", systemImage: "bubble.left")
                    }
                } label: {
                    Label("Reject", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.bordered)
                .foregroundStyle(.orange)

                // Keep original
                Button {
                    guard let resume = resume else { return }
                    viewModel.acceptOriginalAndMoveNext(resume: resume, context: modelContext)
                } label: {
                    Label("Keep Original", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
                .help("Revert to original value, no change applied")

                // Edit and accept
                Button {
                    prepareEditSheet()
                    showEditSheet = true
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .buttonStyle(.bordered)
                .help("Edit the proposed value before accepting")

                // Accept proposed
                Button {
                    guard let resume = resume else { return }
                    viewModel.acceptCurrentItemAndMoveNext(resume: resume, context: modelContext)
                } label: {
                    Label("Accept", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .disabled(currentItem == nil)
            }
        }
        .padding(20)
        .sheet(isPresented: $showEditSheet) {
            editSheet
        }
        .sheet(isPresented: $showFeedbackSheet) {
            feedbackSheet
        }
    }

    // MARK: - Edit Sheet

    private var editSheet: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Edit Value")
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                Spacer()
                if isContainerItem {
                    Button {
                        editedChildren.append("")
                    } label: {
                        Label("Add Item", systemImage: "plus.circle.fill")
                            .font(.system(.subheadline, design: .rounded))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()

            if isContainerItem {
                // Edit children with individual rows
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(editedChildren.indices, id: \.self) { index in
                            HStack(spacing: 8) {
                                TextField("Item \(index + 1)", text: $editedChildren[index])
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.body, design: .rounded))

                                Button {
                                    editedChildren.remove(at: index)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                                .help("Remove item")
                            }
                        }

                        if editedChildren.isEmpty {
                            Text("No items. Click \"Add Item\" to add one.")
                                .font(.system(.callout, design: .rounded))
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 20)
                        }
                    }
                    .padding(20)
                }
                .frame(minHeight: 200, maxHeight: 350)
            } else {
                // Edit scalar value
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Value", text: $editedValue, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .rounded))
                        .lineLimit(3...8)
                }
                .padding(24)
            }

            Divider()

            // Action buttons
            HStack(spacing: 16) {
                Button("Cancel") {
                    showEditSheet = false
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Save & Accept") {
                    guard let resume = resume else { return }
                    // Filter out empty items for children
                    let filteredChildren = editedChildren.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    if isContainerItem {
                        viewModel.acceptCurrentItemWithEdits(nil, editedChildren: filteredChildren, resume: resume, context: modelContext)
                    } else {
                        viewModel.acceptCurrentItemWithEdits(editedValue, editedChildren: nil, resume: resume, context: modelContext)
                    }
                    showEditSheet = false
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(20)
        }
        .frame(width: 550)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Feedback Sheet

    private var feedbackSheet: some View {
        VStack(spacing: 20) {
            Text("Provide Feedback")
                .font(.system(.title3, design: .rounded, weight: .semibold))

            Text("Your feedback will be sent to the AI for a revised suggestion")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)

            TextEditor(text: $feedbackText)
                .font(.system(.body, design: .rounded))
                .frame(height: 120)
                .padding(8)
                .background(Color(NSColor.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )

            HStack(spacing: 16) {
                Button("Cancel") {
                    showFeedbackSheet = false
                }
                .buttonStyle(.bordered)

                Button("Submit Feedback") {
                    viewModel.rejectCurrentItemWithFeedback(feedbackText)
                    showFeedbackSheet = false
                    checkPhaseComplete()
                }
                .buttonStyle(.borderedProminent)
                .disabled(feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 450)
    }

    // MARK: - Helpers

    private func prepareEditSheet() {
        if let item = currentItem {
            if isContainerItem {
                editedChildren = item.proposedChildren ?? item.originalChildren ?? []
            } else {
                editedValue = item.proposedValue
            }
        }
    }

    private func checkPhaseComplete() {
        guard let review = currentReview else { return }
        if phaseState.currentItemIndex >= review.items.count {
            guard let resume = resume else { return }
            viewModel.completeCurrentPhase(resume: resume, context: modelContext)
        }
    }
}

// MARK: - Diff Stats View

struct DiffStatsView: View {
    let original: [String]
    let proposed: [String]

    private var added: Int {
        proposed.filter { !original.contains($0) }.count
    }

    private var removed: Int {
        original.filter { !proposed.contains($0) }.count
    }

    private var kept: Int {
        original.filter { proposed.contains($0) }.count
    }

    var body: some View {
        HStack(spacing: 16) {
            statBadge(count: kept, label: "Kept", color: .gray)
            statBadge(count: added, label: "Added", color: .green)
            statBadge(count: removed, label: "Removed", color: .red)
        }
    }

    private func statBadge(count: Int, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Text("\(count)")
                .font(.system(.body, design: .rounded, weight: .semibold))
                .foregroundStyle(color)
            Text(label)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(color.opacity(0.1))
        .clipShape(Capsule())
    }
}
