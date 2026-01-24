//
//  ResumeEntryCardView.swift
//  Sprung
//
//  Card-based view for resume entries (work experience, education, skills, etc.)
//  Clean, professional design with clear visual hierarchy.
//

import SwiftUI

/// Card view for a single resume entry (job, school, skill category, etc.)
struct ResumeEntryCardView: View {
    let node: TreeNode
    let depthOffset: Int
    @Environment(ResumeDetailVM.self) private var vm: ResumeDetailVM

    /// Matched skill IDs from job context
    private var matchedSkillIds: Set<UUID> {
        guard let requirements = node.resume.jobApp?.extractedRequirements else {
            return []
        }
        return Set(requirements.matchedSkillIds.compactMap { UUID(uuidString: $0) })
    }

    /// Whether this entry is under a section with AI configuration
    private var isUnderAISection: Bool {
        guard let parent = node.parent else { return false }
        return parent.bundledAttributes?.isEmpty == false ||
               parent.enumeratedAttributes?.isEmpty == false
    }

    /// Outline color for AI-enabled entries
    private var outlineColor: Color {
        guard isUnderAISection else { return Color.primary.opacity(0.08) }
        let innerColor = NodeAIReviewModeDetector.innerOutlineColor(for: node)
        if innerColor != .clear { return innerColor.opacity(0.4) }
        return Color.primary.opacity(0.08)
    }

    var body: some View {
        DraggableNodeWrapper(node: node, siblings: node.parent?.orderedChildren ?? []) {
            VStack(alignment: .leading, spacing: 0) {
                cardHeader
                cardContent
            }
            .background(Color(.textBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(outlineColor, lineWidth: 1)
            )
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
    }

    // MARK: - Card Header

    @ViewBuilder
    private var cardHeader: some View {
        HStack(spacing: 10) {
            Text(node.computedTitle)
                .font(.headline)
                .lineLimit(2)

            Spacer()

            if node.allowsChildAddition {
                Button(action: { vm.addChild(to: node) }) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .background(Circle().fill(Color.primary.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .help("Add field")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.primary.opacity(0.02))
    }

    // MARK: - Card Content

    @ViewBuilder
    private var cardContent: some View {
        if node.orderedChildren.isEmpty {
            // Leaf node - show value editor
            FieldValueEditor(node: node, showLabel: false)
                .padding(14)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(node.orderedChildren.enumerated()), id: \.element.id) { index, child in
                    if index > 0 {
                        Divider()
                            .padding(.leading, 14)
                    }
                    fieldRow(child)
                }
            }
        }
    }

    @ViewBuilder
    private func fieldRow(_ child: TreeNode) -> some View {
        if child.orderedChildren.isEmpty {
            // Simple field
            FieldValueEditor(node: child, showLabel: true)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        } else {
            // Nested container (highlights, keywords)
            nestedContainerRow(child)
        }
    }

    @ViewBuilder
    private func nestedContainerRow(_ child: TreeNode) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header row
            HStack(spacing: 8) {
                Text(child.displayLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                if child.allowsChildAddition {
                    Button(action: { vm.addChild(to: child) }) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Add item")
                }
            }

            // Content
            if shouldDisplayAsChips(child) {
                ChipChildrenView(
                    children: child.orderedChildren,
                    parent: child,
                    matchedSkillIds: matchedSkillIds,
                    sourceKey: chipSourceKey(for: child)
                )
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(child.orderedChildren, id: \.id) { grandchild in
                        BulletItemEditor(node: grandchild)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Helpers

    private func shouldDisplayAsChips(_ node: TreeNode) -> Bool {
        if node.schemaInputKind == .chips { return true }
        let nodeName = node.name.lowercased()
        if nodeName == "keywords" {
            if let grandparent = node.parent?.parent {
                let sectionName = grandparent.name.lowercased()
                if sectionName == "skills" || sectionName.contains("skill") {
                    return true
                }
            }
        }
        return false
    }

    private func chipSourceKey(for node: TreeNode) -> String? {
        if let explicit = node.schemaSourceKey { return explicit }
        if shouldDisplayAsChips(node) && node.name.lowercased() == "keywords" {
            return "skillBank"
        }
        return nil
    }
}

// MARK: - Field Value Editor

/// Clean inline editor for a single field value
private struct FieldValueEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(ResumeDetailVM.self) private var vm: ResumeDetailVM
    @State var node: TreeNode
    let showLabel: Bool

    @State private var isHovering = false
    private var isEditing: Bool { vm.editingNodeID == node.id }

    /// Whether this field has AI review configured
    private var hasAIReview: Bool {
        if node.status == .aiToReplace { return true }
        // Check if this attribute is in parent's collection config
        guard let parent = node.parent, let grandparent = parent.parent else { return false }
        let attrName = node.name.isEmpty ? node.displayLabel : node.name
        return grandparent.bundledAttributes?.contains(attrName) == true ||
               grandparent.enumeratedAttributes?.contains(attrName) == true
    }

    /// Background based on AI status
    private var fieldBackground: Color {
        guard hasAIReview else { return .clear }
        if node.status == .aiToReplace {
            return .orange.opacity(0.08)
        }
        // Check collection-level config for this attribute
        guard let parent = node.parent, let grandparent = parent.parent else { return .clear }
        let attrName = node.name.isEmpty ? node.displayLabel : node.name
        if grandparent.enumeratedAttributes?.contains(attrName) == true {
            return .cyan.opacity(0.06)
        }
        if grandparent.bundledAttributes?.contains(attrName) == true {
            return .purple.opacity(0.06)
        }
        return .clear
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if isEditing {
                editingView
            } else {
                displayView
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(fieldBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onHover { isHovering = $0 }
    }

    @ViewBuilder
    private var displayView: some View {
        // Content
        VStack(alignment: .leading, spacing: 2) {
            if showLabel && !node.name.isEmpty {
                Text(node.name)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            if !node.value.isEmpty {
                Text(node.value)
                    .foregroundStyle(.primary)
            } else if node.value.isEmpty && node.name.isEmpty {
                Text("Empty")
                    .foregroundStyle(.tertiary)
                    .italic()
            }
        }

        Spacer(minLength: 0)

        // Edit button (appears on hover)
        if isHovering && node.status != .disabled {
            Button(action: { vm.startEditing(node: node) }) {
                Image(systemName: "pencil")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var editingView: some View {
        EditingControls(
            isEditing: Binding(
                get: { isEditing },
                set: { if !$0 { vm.cancelEditing() } }
            ),
            tempName: Binding(get: { vm.tempName }, set: { vm.tempName = $0 }),
            tempValue: Binding(get: { vm.tempValue }, set: { vm.tempValue = $0 }),
            node: node,
            validationError: vm.validationError,
            allowNameEditing: node.allowsInlineNameEditing,
            saveChanges: { vm.saveEdits() },
            cancelChanges: { vm.cancelEditing() },
            deleteNode: { vm.deleteNode(node, context: context) },
            clearValidation: { vm.validationError = nil }
        )
    }
}

// MARK: - Bullet Item Editor

/// Editor for bulleted list items (like highlights)
private struct BulletItemEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(ResumeDetailVM.self) private var vm: ResumeDetailVM
    @State var node: TreeNode

    @State private var isHovering = false
    private var isEditing: Bool { vm.editingNodeID == node.id }

    /// Whether this item has AI review configured
    private var hasAIReview: Bool {
        if node.status == .aiToReplace { return true }
        // Check for [] suffix config (each item separate)
        guard let parent = node.parent,
              let entry = parent.parent,
              let collection = entry.parent else { return false }
        let containerName = parent.name.isEmpty ? parent.displayLabel : parent.name
        return collection.enumeratedAttributes?.contains(containerName + "[]") == true ||
               collection.bundledAttributes?.contains(containerName + "[]") == true
    }

    private var itemBackground: Color {
        guard hasAIReview else { return .clear }
        if node.status == .aiToReplace {
            return .orange.opacity(0.1)
        }
        return .cyan.opacity(0.08)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 5, height: 5)
                .padding(.top, 7)

            if isEditing {
                EditingControls(
                    isEditing: Binding(
                        get: { isEditing },
                        set: { if !$0 { vm.cancelEditing() } }
                    ),
                    tempName: Binding(get: { vm.tempName }, set: { vm.tempName = $0 }),
                    tempValue: Binding(get: { vm.tempValue }, set: { vm.tempValue = $0 }),
                    node: node,
                    validationError: vm.validationError,
                    allowNameEditing: false,
                    saveChanges: { vm.saveEdits() },
                    cancelChanges: { vm.cancelEditing() },
                    deleteNode: { vm.deleteNode(node, context: context) },
                    clearValidation: { vm.validationError = nil }
                )
            } else {
                Text(node.value.isEmpty ? node.name : node.value)
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)

                if isHovering && node.status != .disabled {
                    Button(action: { vm.startEditing(node: node) }) {
                        Image(systemName: "pencil")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(itemBackground)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .onHover { isHovering = $0 }
    }
}
