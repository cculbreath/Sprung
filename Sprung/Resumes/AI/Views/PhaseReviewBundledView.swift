//
//  PhaseReviewBundledView.swift
//  Sprung
//
//  Bundled review view for manifest-driven multi-phase review.
//  Shows all items at once for batch accept/reject when phase.bundle = true.
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
                    VStack(spacing: 16) {
                        ForEach(review.items.indices, id: \.self) { index in
                            PhaseReviewItemRow(
                                item: bindingForItem(at: index),
                                showChildren: review.items[index].originalChildren != nil
                            )
                        }
                    }
                    .padding(24)
                }
                .frame(minHeight: 300, maxHeight: 600)
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
    @State private var isEditing: Bool = false
    @State private var editedValue: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header row with name, action badge, and decision buttons
            HStack(spacing: 12) {
                // Action indicator
                actionIcon
                    .frame(width: 32)

                Text(displayName)
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if item.action != .keep {
                    actionBadge
                }

                Spacer(minLength: 8)

                if showChildren, let children = item.originalChildren {
                    Text("\(children.count) items")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                // Edit button (only for modify actions)
                if item.action == .modify && !showChildren {
                    Button {
                        editedValue = item.proposedValue
                        isEditing = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Edit proposed value")
                }

                // Decision buttons
                decisionButtons
            }

            // Show value change with before/after vertical layout
            if item.action == .modify {
                VStack(alignment: .leading, spacing: 12) {
                    // Before section
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Before")
                            .font(.system(.caption2, design: .rounded, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        if showChildren, let originalChildren = item.originalChildren {
                            ForEach(originalChildren, id: \.self) { child in
                                Text("• " + child)
                                    .font(.system(.caption, design: .rounded))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        } else {
                            Text(item.originalValue)
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.gray.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    // Arrow indicator
                    HStack {
                        Spacer()
                        Image(systemName: "arrow.down")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.blue)
                        Spacer()
                    }

                    // After section
                    VStack(alignment: .leading, spacing: 6) {
                        Text("After")
                            .font(.system(.caption2, design: .rounded, weight: .semibold))
                            .foregroundStyle(.blue)
                            .textCase(.uppercase)

                        if showChildren, let proposedChildren = item.proposedChildren {
                            ForEach(proposedChildren, id: \.self) { child in
                                Text("• " + child)
                                    .font(.system(.caption, design: .rounded, weight: .medium))
                                    .foregroundStyle(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        } else {
                            Text(item.proposedValue)
                                .font(.system(.caption, design: .rounded, weight: .medium))
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.blue.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .padding(.leading, 44)
                .padding(.trailing, 8)
            }

            // Reason text - full display
            if !item.reason.isEmpty {
                Text(item.reason)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 44)
                    .padding(.trailing, 8)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Comment field when rejected
            if item.userDecision == .rejected {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Feedback (optional)")
                        .font(.system(.caption2, design: .rounded, weight: .medium))
                        .foregroundStyle(.secondary)

                    TextField("Why are you rejecting this suggestion?", text: $item.userComment, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(.caption, design: .rounded))
                        .padding(8)
                        .background(Color.red.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.red.opacity(0.2), lineWidth: 1)
                        )
                }
                .padding(.leading, 44)
                .padding(.trailing, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(20)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(borderColor, lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.2), value: item.userDecision)
        .sheet(isPresented: $isEditing) {
            EditProposedValueSheet(
                originalValue: item.originalValue,
                proposedValue: $editedValue,
                onSave: {
                    item.proposedValue = editedValue
                    item.userDecision = .accepted  // Auto-accept when user edits
                    isEditing = false
                },
                onCancel: {
                    isEditing = false
                }
            )
        }
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
            .foregroundStyle(item.userDecision == .rejected ? .red : .primary.opacity(0.6))
            .padding(8)
            .background(item.userDecision == .rejected ? Color.red.opacity(0.15) : Color.gray.opacity(0.1))
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(item.userDecision == .rejected ? Color.red.opacity(0.3) : Color.gray.opacity(0.2), lineWidth: 1)
            )

            Button {
                item.userDecision = .accepted
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(item.userDecision == .accepted ? .green : .primary.opacity(0.6))
            .padding(8)
            .background(item.userDecision == .accepted ? Color.green.opacity(0.15) : Color.gray.opacity(0.1))
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(item.userDecision == .accepted ? Color.green.opacity(0.3) : Color.gray.opacity(0.2), lineWidth: 1)
            )
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

// MARK: - Edit Proposed Value Sheet

struct EditProposedValueSheet: View {
    let originalValue: String
    @Binding var proposedValue: String
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "pencil.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.blue)

                Text("Edit Proposed Value")
                    .font(.system(.title2, design: .rounded, weight: .semibold))
            }
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Original value (read-only reference)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Original Value")
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        Text(originalValue)
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.gray.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    // Editable proposed value
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Proposed Value")
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .foregroundStyle(.blue)
                            .textCase(.uppercase)

                        TextEditor(text: $proposedValue)
                            .font(.system(.body, design: .rounded))
                            .padding(8)
                            .frame(minHeight: 100, maxHeight: 200)
                            .background(Color(NSColor.textBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                            )
                    }

                    Text("Edit the AI's suggestion above. Your changes will be used if you accept this item.")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .padding(24)
            }

            Divider()

            // Action buttons
            HStack(spacing: 16) {
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Save Changes") {
                    onSave()
                }
                .buttonStyle(.borderedProminent)
                .disabled(proposedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(20)
        }
        .frame(width: 500, height: 400)
        .background(Color(NSColor.windowBackgroundColor))
    }
}
