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
                        if let originalChildren = item.originalChildren,
                           let proposedChildren = item.proposedChildren {
                            // Show children diff (like keywords)
                            childrenDiffView(
                                original: originalChildren,
                                proposed: proposedChildren,
                                itemName: item.displayName
                            )
                        } else {
                            // Show scalar diff
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
        .frame(width: 900)
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

            HStack(spacing: 8) {
                Text("Phase \(phaseState.currentPhaseIndex + 1) of \(phaseState.phases.count)")
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .clipShape(Capsule())

                if let review = currentReview {
                    Text("Item \(phaseState.currentItemIndex + 1) of \(review.items.count)")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
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

            // Side by side diff
            HStack(alignment: .top, spacing: 20) {
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
            }
        }
    }

    @ViewBuilder
    private func childrenList(items: [String], comparison: [String], isOriginal: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    // Status indicator
                    childStatusIcon(item: item, comparison: comparison, isOriginal: isOriginal)
                        .padding(.top, 2)

                    Text(item)
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(childTextColor(item: item, comparison: comparison, isOriginal: isOriginal))
                        .fixedSize(horizontal: false, vertical: true)
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
        HStack(spacing: 16) {
            Button("Cancel Review") {
                if viewModel.hasUnappliedApprovedChanges() {
                    showCancelConfirmation = true
                } else {
                    viewModel.discardAllAndClose()
                }
            }
            .buttonStyle(.bordered)

            Spacer()

            Button("Skip") {
                viewModel.rejectCurrentItemAndMoveNext()
                checkPhaseComplete()
            }
            .buttonStyle(.bordered)

            Button("Accept Changes") {
                guard let resume = resume else { return }
                viewModel.acceptCurrentItemAndMoveNext(resume: resume, context: modelContext)
            }
            .buttonStyle(.borderedProminent)
            .disabled(currentItem == nil)
        }
        .padding(20)
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
