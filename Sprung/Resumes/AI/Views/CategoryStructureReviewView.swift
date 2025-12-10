//
//  CategoryStructureReviewView.swift
//  Sprung
//
//  Phase 1 UI for two-phase hierarchical skills review
//  Shows category-level proposals (keep/remove/rename/merge/add)
//

import SwiftUI
import SwiftData

/// Phase 1 UI: Review skill category structure before diving into keywords
struct CategoryStructureReviewView: View {
    @Bindable var viewModel: ResumeReviseViewModel
    @Binding var resume: Resume?
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection

            Divider()

            // Category list
            ScrollView {
                VStack(spacing: 12) {
                    ForEach($viewModel.categoryRevisions) { $category in
                        CategoryRevisionRow(category: $category)
                    }
                }
                .padding(20)
            }
            .frame(maxHeight: 500)

            Divider()

            // Action buttons
            actionButtons
        }
        .frame(width: 600)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "folder.badge.gearshape")
                    .font(.system(size: 24))
                    .foregroundStyle(.blue)

                Text("Skill Categories Review")
                    .font(.system(.title2, design: .rounded, weight: .semibold))
            }

            Text("Review suggested changes to your skill category structure")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)

            Text("Phase 1 of 2: Category Structure")
                .font(.system(.caption, design: .rounded, weight: .medium))
                .foregroundStyle(.blue)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.1))
                .clipShape(Capsule())
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 16) {
            Button("Cancel") {
                viewModel.discardAllAndClose()
            }
            .buttonStyle(.bordered)

            Spacer()

            Button("Accept All") {
                acceptAll()
            }
            .buttonStyle(.bordered)

            Button("Continue to Keywords") {
                continueToPhase2()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!hasAnyDecision)
        }
        .padding(20)
    }

    // MARK: - Computed Properties

    private var hasAnyDecision: Bool {
        viewModel.categoryRevisions.contains { $0.userDecision != .pending }
    }

    // MARK: - Actions

    private func acceptAll() {
        for index in viewModel.categoryRevisions.indices {
            viewModel.categoryRevisions[index].userDecision = .accepted
        }
    }

    private func continueToPhase2() {
        guard let resume = resume else { return }
        viewModel.completeCategoryStructurePhase(resume: resume, context: modelContext)
    }
}

// MARK: - Category Revision Row

struct CategoryRevisionRow: View {
    @Binding var category: CategoryRevisionNode

    var body: some View {
        HStack(spacing: 12) {
            // Action indicator
            actionIcon
                .frame(width: 32)

            // Category info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(displayName)
                        .font(.system(.body, design: .rounded, weight: .medium))

                    if category.action != .keep {
                        actionBadge
                    }

                    Spacer()

                    Text("\(category.keywordCount) keywords")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                if !category.why.isEmpty {
                    Text(category.why)
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
            switch category.action {
            case .keep:
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(.green)
            case .remove:
                Image(systemName: "trash.circle")
                    .foregroundStyle(.red)
            case .rename:
                Image(systemName: "pencil.circle")
                    .foregroundStyle(.orange)
            case .merge:
                Image(systemName: "arrow.triangle.merge")
                    .foregroundStyle(.purple)
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
                category.userDecision = .rejected
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(category.userDecision == .rejected ? .red : .secondary)
            .padding(6)
            .background(category.userDecision == .rejected ? Color.red.opacity(0.15) : Color.clear)
            .clipShape(Circle())

            Button {
                category.userDecision = .accepted
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(category.userDecision == .accepted ? .green : .secondary)
            .padding(6)
            .background(category.userDecision == .accepted ? Color.green.opacity(0.15) : Color.clear)
            .clipShape(Circle())
        }
    }

    // MARK: - Computed Properties

    private var displayName: String {
        switch category.action {
        case .rename:
            return "\(category.name) → \(category.newName ?? category.name)"
        case .merge:
            return "\(category.name) → merge into \(category.mergeWithName ?? "other")"
        case .add:
            return category.newName ?? "New Category"
        default:
            return category.name
        }
    }

    private var actionText: String {
        switch category.action {
        case .keep: return "Keep"
        case .remove: return "Remove"
        case .rename: return "Rename"
        case .merge: return "Merge"
        case .add: return "Add"
        }
    }

    private var actionColor: Color {
        switch category.action {
        case .keep: return .green
        case .remove: return .red
        case .rename: return .orange
        case .merge: return .purple
        case .add: return .blue
        }
    }

    private var backgroundColor: Color {
        switch category.userDecision {
        case .pending: return Color(NSColor.controlBackgroundColor)
        case .accepted: return Color.green.opacity(0.05)
        case .rejected: return Color.red.opacity(0.05)
        }
    }

    private var borderColor: Color {
        switch category.userDecision {
        case .pending: return Color.gray.opacity(0.2)
        case .accepted: return Color.green.opacity(0.3)
        case .rejected: return Color.red.opacity(0.3)
        }
    }
}
