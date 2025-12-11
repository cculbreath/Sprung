//
//  PhaseReviewBundledView.swift
//  Sprung
//
//  Generic bundled review view for manifest-driven multi-phase review.
//  Shows all items at once for accept/reject when phase.bundle = true.
//

import SwiftUI
import SwiftData

/// Generic bundled review: Shows all phase items at once for batch review
struct PhaseReviewBundledView: View {
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

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection

            Divider()

            // Items list
            if let review = currentReview {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(review.items.indices, id: \.self) { index in
                            PhaseReviewItemRow(
                                item: bindingForItem(at: index),
                                showChildren: review.items[index].originalChildren != nil
                            )
                        }
                    }
                    .padding(20)
                }
                .frame(maxHeight: 500)
            } else if viewModel.isProcessingRevisions {
                loadingView
            } else {
                emptyView
            }

            Divider()

            // Action buttons
            actionButtons
        }
        .frame(width: 650)
        .background(Color(NSColor.windowBackgroundColor))
        .confirmationDialog(
            "Cancel Review?",
            isPresented: $showCancelConfirmation,
            titleVisibility: .visible
        ) {
            if hasAnyAccepted {
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
            if hasAnyAccepted {
                Text("You have approved \(acceptedCount) changes. Would you like to apply them before closing?")
            } else {
                Text("Are you sure you want to discard all pending changes?")
            }
        }
    }

    // MARK: - Binding Helper

    private func bindingForItem(at index: Int) -> Binding<PhaseReviewItem> {
        Binding(
            get: {
                guard let review = viewModel.phaseReviewState.currentReview,
                      index < review.items.count else {
                    return PhaseReviewItem(id: "", displayName: "", originalValue: "", proposedValue: "")
                }
                return review.items[index]
            },
            set: { newValue in
                guard var review = viewModel.phaseReviewState.currentReview,
                      index < review.items.count else { return }
                review.items[index] = newValue
                viewModel.phaseReviewState.currentReview = review
            }
        )
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: phaseIcon)
                    .font(.system(size: 24))
                    .foregroundStyle(.blue)

                Text(headerTitle)
                    .font(.system(.title2, design: .rounded, weight: .semibold))
            }

            Text(headerSubtitle)
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
                    Text("\(review.items.count) items")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
    }

    private var phaseIcon: String {
        guard let phase = phaseState.currentPhase else { return "folder.badge.gearshape" }
        // Use different icons based on field path pattern
        if phase.field.contains("name") {
            return "folder.badge.gearshape"
        } else if phase.field.contains("keywords") || phase.field.contains("highlights") {
            return "tag"
        }
        return "doc.text.magnifyingglass"
    }

    private var headerTitle: String {
        let section = phaseState.currentSection.capitalized
        guard let phase = phaseState.currentPhase else { return "\(section) Review" }

        // Extract meaningful name from field path
        let components = phase.field.split(separator: ".")
        if let lastComponent = components.last, lastComponent != "*" && lastComponent != "[]" {
            return "\(section) \(String(lastComponent).capitalized) Review"
        }
        return "\(section) Review"
    }

    private var headerSubtitle: String {
        "Review suggested changes for this phase"
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
        .frame(maxWidth: .infinity, maxHeight: 200)
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
        .frame(maxWidth: .infinity, maxHeight: 200)
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 16) {
            Button("Cancel") {
                showCancelConfirmation = true
            }
            .buttonStyle(.bordered)

            Spacer()

            Button("Accept All") {
                acceptAll()
            }
            .buttonStyle(.bordered)

            Button(phaseState.isLastPhase ? "Finish Review" : "Continue to Next Phase") {
                continueToNextPhase()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!hasAnyDecision)
        }
        .padding(20)
    }

    // MARK: - Computed Properties

    private var hasAnyDecision: Bool {
        guard let review = currentReview else { return false }
        return review.items.contains { $0.userDecision != .pending }
    }

    private var hasAnyAccepted: Bool {
        guard let review = currentReview else { return false }
        return review.items.contains { $0.userDecision == .accepted }
    }

    private var acceptedCount: Int {
        guard let review = currentReview else { return 0 }
        return review.items.filter { $0.userDecision == .accepted }.count
    }

    // MARK: - Actions

    private func acceptAll() {
        guard var review = viewModel.phaseReviewState.currentReview else { return }
        for index in review.items.indices {
            review.items[index].userDecision = .accepted
        }
        viewModel.phaseReviewState.currentReview = review
    }

    private func continueToNextPhase() {
        guard let resume = resume else { return }
        viewModel.completeCurrentPhase(resume: resume, context: modelContext)
    }
}

// MARK: - Phase Review Item Row

struct PhaseReviewItemRow: View {
    @Binding var item: PhaseReviewItem
    let showChildren: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Action indicator
            actionIcon
                .frame(width: 32)

            // Item info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(displayName)
                        .font(.system(.body, design: .rounded, weight: .medium))

                    if item.action != .keep {
                        actionBadge
                    }

                    Spacer()

                    if showChildren, let children = item.originalChildren {
                        Text("\(children.count) items")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }

                // Show value change if applicable
                if item.action == .modify {
                    HStack(spacing: 4) {
                        Text(item.originalValue)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                            .strikethrough()
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Text(item.proposedValue)
                            .font(.system(.caption, design: .rounded, weight: .medium))
                            .foregroundStyle(.blue)
                    }
                }

                if !item.reason.isEmpty {
                    Text(item.reason)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            // Decision buttons
            decisionButtons
        }
        .padding(12)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(borderColor, lineWidth: 1)
        )
    }

    // MARK: - Subviews

    private var actionIcon: some View {
        Group {
            switch item.action {
            case .keep:
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(.green)
            case .remove:
                Image(systemName: "trash.circle")
                    .foregroundStyle(.red)
            case .modify:
                Image(systemName: "pencil.circle")
                    .foregroundStyle(.orange)
            case .add:
                Image(systemName: "plus.circle")
                    .foregroundStyle(.blue)
            }
        }
        .font(.system(size: 20))
    }

    private var actionBadge: some View {
        Text(actionText)
            .font(.system(.caption2, design: .rounded, weight: .medium))
            .foregroundStyle(actionColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(actionColor.opacity(0.15))
            .clipShape(Capsule())
    }

    private var decisionButtons: some View {
        HStack(spacing: 8) {
            Button {
                item.userDecision = .rejected
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(item.userDecision == .rejected ? .red : .secondary)
            .padding(6)
            .background(item.userDecision == .rejected ? Color.red.opacity(0.15) : Color.clear)
            .clipShape(Circle())

            Button {
                item.userDecision = .accepted
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(item.userDecision == .accepted ? .green : .secondary)
            .padding(6)
            .background(item.userDecision == .accepted ? Color.green.opacity(0.15) : Color.clear)
            .clipShape(Circle())
        }
    }

    // MARK: - Computed Properties

    private var displayName: String {
        if item.action == .add {
            return item.proposedValue.isEmpty ? "New Item" : item.proposedValue
        }
        return item.displayName.isEmpty ? item.originalValue : item.displayName
    }

    private var actionText: String {
        switch item.action {
        case .keep: return "Keep"
        case .remove: return "Remove"
        case .modify: return "Modify"
        case .add: return "Add"
        }
    }

    private var actionColor: Color {
        switch item.action {
        case .keep: return .green
        case .remove: return .red
        case .modify: return .orange
        case .add: return .blue
        }
    }

    private var backgroundColor: Color {
        switch item.userDecision {
        case .pending: return Color(NSColor.controlBackgroundColor)
        case .accepted: return Color.green.opacity(0.05)
        case .rejected: return Color.red.opacity(0.05)
        }
    }

    private var borderColor: Color {
        switch item.userDecision {
        case .pending: return Color.gray.opacity(0.2)
        case .accepted: return Color.green.opacity(0.3)
        case .rejected: return Color.red.opacity(0.3)
        }
    }
}
