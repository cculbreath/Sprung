//
//  PerItemListDiffView.swift
//  Sprung
//
//  Per-item review UI for work experience highlights
//  Allows accepting/rejecting individual bullet points
//

import SwiftUI
import SwiftData

/// Per-item review UI for work experience highlights
/// Default: batch behavior (Accept All / Reject All)
/// Per-item: hover over any item to show reject/comment buttons for that specific item
struct PerItemListDiffView: View {
    @Bindable var viewModel: ResumeReviseViewModel
    let revision: ProposedRevisionNode
    @Binding var itemFeedback: [ItemFeedback]
    let onComplete: ([ItemFeedback]) -> Void
    let onCancel: () -> Void

    @State private var showCommentSheet = false
    @State private var commentingItemIndex: Int?
    @State private var commentText: String = ""
    @State private var batchComment: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection

            Divider()

            // Items list - showing the diff
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(Array(zip(revision.newValues.indices, revision.newValues)), id: \.0) { index, newValue in
                        HighlightDiffRow(
                            index: index,
                            oldValue: index < revision.oldValues.count ? revision.oldValues[index] : nil,
                            newValue: newValue,
                            feedback: binding(for: index),
                            onReject: {
                                updateFeedback(index: index, status: .rejected)
                            },
                            onComment: {
                                commentingItemIndex = index
                                commentText = itemFeedback.first { $0.index == index }?.comment ?? ""
                                showCommentSheet = true
                            }
                        )
                    }
                }
                .padding(20)
            }
            .frame(maxHeight: 450)

            // Summary if any items have per-item feedback
            if hasAnyPerItemFeedback {
                Divider()
                statsSection
            }

            Divider()

            // Batch action buttons (primary workflow)
            batchActionButtons
        }
        .frame(width: 700)
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(isPresented: $showCommentSheet) {
            CommentEntrySheet(
                commentText: $commentText,
                onSave: {
                    if let index = commentingItemIndex {
                        updateFeedback(index: index, status: .rejectedWithComment, comment: commentText)
                    }
                    showCommentSheet = false
                },
                onCancel: {
                    showCommentSheet = false
                }
            )
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 24))
                    .foregroundStyle(.blue)

                Text("Review Highlights")
                    .font(.system(.title2, design: .rounded, weight: .semibold))
            }

            Text(revision.treePath)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)

            Text("Per-Item Review Mode")
                .font(.system(.caption, design: .rounded, weight: .medium))
                .foregroundStyle(.purple)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Color.purple.opacity(0.1))
                .clipShape(Capsule())
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Stats Section

    private var statsSection: some View {
        HStack(spacing: 16) {
            statBadge(count: acceptedCount, label: "Accepted", color: .green)
            statBadge(count: rejectedCount, label: "Rejected", color: .red)
            statBadge(count: pendingCount, label: "Pending", color: .gray)
        }
        .padding(.vertical, 12)
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

    // MARK: - Batch Action Buttons (Primary Workflow)

    private var batchActionButtons: some View {
        VStack(spacing: 12) {
            // Hint about per-item actions
            if !hasAnyPerItemFeedback {
                Text("Hover over any item to reject it individually")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.bordered)

                Spacer()

                // Reject batch with comment
                Button {
                    commentingItemIndex = -1  // Special value for batch
                    commentText = batchComment
                    showCommentSheet = true
                } label: {
                    Label("Reject with Comment...", systemImage: "bubble.left")
                }
                .buttonStyle(.bordered)

                // Accept batch (excluding individually rejected items)
                Button {
                    acceptRemainingItems()
                    onComplete(itemFeedback)
                } label: {
                    if rejectedCount > 0 {
                        Text("Accept \(revision.newValues.count - rejectedCount) Items")
                    } else {
                        Text("Accept All")
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
    }

    // MARK: - Legacy Action Buttons (kept for compatibility)

    private var actionButtons: some View {
        batchActionButtons
    }

    // MARK: - Helpers

    private func binding(for index: Int) -> Binding<ItemFeedback> {
        Binding(
            get: {
                if let existing = itemFeedback.first(where: { $0.index == index }) {
                    return existing
                }
                return ItemFeedback(index: index)
            },
            set: { newValue in
                if let existingIndex = itemFeedback.firstIndex(where: { $0.index == index }) {
                    itemFeedback[existingIndex] = newValue
                } else {
                    itemFeedback.append(newValue)
                }
            }
        )
    }

    private func updateFeedback(index: Int, status: ItemFeedback.ItemStatus, comment: String = "") {
        if index == -1 {
            // Apply to all pending items
            for i in 0..<revision.newValues.count {
                if let existingIndex = itemFeedback.firstIndex(where: { $0.index == i }) {
                    if itemFeedback[existingIndex].status == .pending {
                        itemFeedback[existingIndex].status = status
                        itemFeedback[existingIndex].comment = comment
                    }
                } else {
                    var feedback = ItemFeedback(index: i)
                    feedback.status = status
                    feedback.comment = comment
                    itemFeedback.append(feedback)
                }
            }
        } else {
            if let existingIndex = itemFeedback.firstIndex(where: { $0.index == index }) {
                itemFeedback[existingIndex].status = status
                itemFeedback[existingIndex].comment = comment
            } else {
                var feedback = ItemFeedback(index: index)
                feedback.status = status
                feedback.comment = comment
                itemFeedback.append(feedback)
            }
        }
    }

    private func acceptAll() {
        for index in 0..<revision.newValues.count {
            updateFeedback(index: index, status: .accepted)
        }
    }

    private func acceptRemainingItems() {
        // Accept all items that haven't been individually rejected
        for index in 0..<revision.newValues.count {
            let existing = itemFeedback.first { $0.index == index }
            if existing == nil || existing?.status == .pending {
                updateFeedback(index: index, status: .accepted)
            }
        }
    }

    // MARK: - Computed Properties

    private var acceptedCount: Int {
        itemFeedback.filter { $0.status == .accepted }.count
    }

    private var rejectedCount: Int {
        itemFeedback.filter { $0.status == .rejected || $0.status == .rejectedWithComment }.count
    }

    private var pendingCount: Int {
        revision.newValues.count - acceptedCount - rejectedCount
    }

    private var hasAnyPerItemFeedback: Bool {
        itemFeedback.contains { $0.status != .pending }
    }
}

// MARK: - Highlight Diff Row

struct HighlightDiffRow: View {
    let index: Int
    let oldValue: String?
    let newValue: String
    @Binding var feedback: ItemFeedback
    let onReject: () -> Void
    let onComment: () -> Void

    @State private var isHovering = false

    private var isChanged: Bool {
        guard let old = oldValue else { return true }  // New item
        return old != newValue
    }

    private var isNewItem: Bool {
        oldValue == nil
    }

    private var isRejected: Bool {
        feedback.status == .rejected || feedback.status == .rejectedWithComment
    }

    var body: some View {
        HStack(spacing: 12) {
            // Index indicator
            Text("\(index + 1)")
                .font(.system(.caption, design: .monospaced, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 24)

            // Content
            VStack(alignment: .leading, spacing: 4) {
                if isNewItem {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.green)
                            .font(.system(size: 12))
                        Text("New")
                            .font(.system(.caption2, design: .rounded, weight: .medium))
                            .foregroundStyle(.green)
                    }
                } else if isChanged {
                    HStack(spacing: 6) {
                        Image(systemName: "pencil.circle.fill")
                            .foregroundStyle(.orange)
                            .font(.system(size: 12))
                        Text("Modified")
                            .font(.system(.caption2, design: .rounded, weight: .medium))
                            .foregroundStyle(.orange)
                    }
                }

                if let old = oldValue, isChanged {
                    Text(old)
                        .font(.system(.callout, design: .rounded))
                        .foregroundStyle(.secondary)
                        .strikethrough()
                }

                Text(newValue)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(isChanged ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Per-item action panel (appears on hover or if rejected)
            if isHovering || isRejected {
                HStack(spacing: 8) {
                    // Reject with comment
                    Button {
                        onComment()
                    } label: {
                        Image(systemName: feedback.status == .rejectedWithComment ? "bubble.left.fill" : "bubble.left")
                            .font(.system(size: 16))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(feedback.status == .rejectedWithComment ? .purple : .secondary)
                    .help("Reject with comment for AI")

                    // Reject without comment
                    Button {
                        if isRejected {
                            // Toggle off rejection
                            feedback.status = .pending
                            feedback.comment = ""
                        } else {
                            onReject()
                        }
                    } label: {
                        Image(systemName: isRejected ? "xmark.circle.fill" : "xmark.circle")
                            .font(.system(size: 16))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(isRejected ? .red : .secondary)
                    .help(isRejected ? "Undo rejection" : "Reject this item")
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.9))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .padding(12)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(borderColor, lineWidth: 1)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }

    private var backgroundColor: Color {
        if isRejected {
            return Color.red.opacity(0.05)
        }
        return Color(NSColor.controlBackgroundColor)
    }

    private var borderColor: Color {
        if isRejected {
            return Color.red.opacity(0.3)
        }
        return Color.gray.opacity(0.2)
    }
}

// MARK: - Comment Entry Sheet

struct CommentEntrySheet: View {
    @Binding var commentText: String
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("Add Comment for AI")
                .font(.system(.title3, design: .rounded, weight: .semibold))

            Text("Explain what changes you'd like the AI to make")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)

            TextEditor(text: $commentText)
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
                    onCancel()
                }
                .buttonStyle(.bordered)

                Button("Save Comment") {
                    onSave()
                }
                .buttonStyle(.borderedProminent)
                .disabled(commentText.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 400)
    }
}
