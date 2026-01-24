//
//  ResumeEntryCardView.swift
//  Sprung
//
//  Card-based view for resume entries (work experience, education, skills, etc.)
//  Professional design with clear visual hierarchy and refined styling.
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

    /// Border color based on AI status
    private var borderColor: Color {
        guard isUnderAISection else { return Color(.separatorColor).opacity(0.5) }
        let innerColor = NodeAIReviewModeDetector.innerOutlineColor(for: node)
        if innerColor != .clear { return innerColor.opacity(0.5) }
        return Color(.separatorColor).opacity(0.5)
    }

    /// Children to display (filters out redundant "name" field)
    private var displayChildren: [TreeNode] {
        let title = node.computedTitle.lowercased()
        return node.orderedChildren.filter { child in
            // Skip "name" field if it just repeats the card title
            if child.name.lowercased() == "name" && child.value.lowercased() == title {
                return false
            }
            return true
        }
    }

    var body: some View {
        DraggableNodeWrapper(node: node, siblings: node.parent?.orderedChildren ?? []) {
            VStack(alignment: .leading, spacing: 0) {
                cardHeader
                if !displayChildren.isEmpty || node.orderedChildren.isEmpty {
                    cardContent
                }
            }
            .background(Color(.textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(borderColor, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
    }

    // MARK: - Card Header

    @ViewBuilder
    private var cardHeader: some View {
        HStack(spacing: 8) {
            Text(node.computedTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)

            Spacer()

            if node.allowsChildAddition {
                Button(action: { vm.addChild(to: node) }) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Add field")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.windowBackgroundColor).opacity(0.5))
    }

    // MARK: - Card Content

    @ViewBuilder
    private var cardContent: some View {
        if node.orderedChildren.isEmpty {
            // Leaf node - show value editor
            FieldValueEditor(node: node, showLabel: false)
                .padding(12)
        } else if !displayChildren.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(displayChildren.enumerated()), id: \.element.id) { index, child in
                    if index > 0 {
                        Divider()
                            .padding(.leading, 12)
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
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        } else {
            // Nested container (highlights, keywords)
            nestedContainerRow(child)
        }
    }

    @ViewBuilder
    private func nestedContainerRow(_ child: TreeNode) -> some View {
        let containerName = child.name.isEmpty ? child.displayLabel : child.name
        let collectionNode = node.parent  // The section (e.g., Skills)
        let isBundled = collectionNode?.bundledAttributes?.contains(containerName) == true
        let isIteratedBundled = collectionNode?.enumeratedAttributes?.contains(containerName) == true
        let isIteratedEach = collectionNode?.enumeratedAttributes?.contains(containerName + "[]") == true
        let hasAIConfig = isBundled || isIteratedBundled || isIteratedEach

        // Accent color for the container
        let accentColor: Color? = {
            if isBundled { return .purple }
            if isIteratedBundled || isIteratedEach { return .cyan }
            return nil
        }()

        VStack(alignment: .leading, spacing: 6) {
            // Header row with optional accent bar
            HStack(spacing: 6) {
                if let color = accentColor {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(color.opacity(0.6))
                        .frame(width: 3, height: 14)
                }

                Text(child.displayLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer()

                if child.allowsChildAddition {
                    Button(action: { vm.addChild(to: child) }) {
                        Image(systemName: "plus")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.tertiary)
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
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(child.orderedChildren, id: \.id) { grandchild in
                        BulletItemEditor(node: grandchild)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contextMenu {
            if let collection = collectionNode {
                Text("AI Review: \(containerName)")

                Divider()

                // Bundle all (1 review for all items across all entries)
                Button {
                    setContainerMode(collection: collection, attr: containerName, mode: .bundle)
                } label: {
                    HStack {
                        Image(systemName: "square.on.square.squareshape.controlhandles")
                            .foregroundColor(.purple)
                        Text("Bundle – 1 review")
                        if isBundled { Image(systemName: "checkmark") }
                    }
                }

                // Iterate bundled (N reviews, each entry's items together)
                Button {
                    setContainerMode(collection: collection, attr: containerName, mode: .iterate)
                } label: {
                    HStack {
                        Image(systemName: "flowchart")
                            .foregroundColor(.cyan)
                        Text("Iterate (bundled) – N reviews")
                        if isIteratedBundled { Image(systemName: "checkmark") }
                    }
                }

                // Iterate each (N×M reviews, each item separate)
                Button {
                    setContainerMode(collection: collection, attr: containerName + "[]", mode: .iterate)
                } label: {
                    HStack {
                        Image(systemName: "flowchart")
                            .foregroundColor(.cyan)
                        Text("Iterate (each) – N×M reviews")
                        if isIteratedEach { Image(systemName: "checkmark") }
                    }
                }

                if hasAIConfig {
                    Divider()

                    Button(role: .destructive) {
                        setContainerMode(collection: collection, attr: containerName, mode: .off)
                    } label: {
                        Label("Disable AI Review", systemImage: "xmark.circle")
                    }
                }
            }
        }
    }

    private func setContainerMode(collection: TreeNode, attr: String, mode: AIReviewMode) {
        let baseAttr = attr.replacingOccurrences(of: "[]", with: "")
        let attrWithSuffix = baseAttr + "[]"

        // Remove from both lists
        if var bundled = collection.bundledAttributes {
            bundled.removeAll { $0 == baseAttr || $0 == attrWithSuffix }
            collection.bundledAttributes = bundled.isEmpty ? nil : bundled
        }
        if var enumerated = collection.enumeratedAttributes {
            enumerated.removeAll { $0 == baseAttr || $0 == attrWithSuffix }
            collection.enumeratedAttributes = enumerated.isEmpty ? nil : enumerated
        }

        // Add to appropriate list
        if mode == .bundle {
            var bundled = collection.bundledAttributes ?? []
            bundled.append(baseAttr)
            collection.bundledAttributes = bundled
        } else if mode == .iterate {
            var enumerated = collection.enumeratedAttributes ?? []
            enumerated.append(attr)  // Use the attr as-is (may have [] suffix)
            collection.enumeratedAttributes = enumerated
        }
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
        guard let parent = node.parent, let grandparent = parent.parent else { return false }
        let attrName = node.name.isEmpty ? node.displayLabel : node.name
        return grandparent.bundledAttributes?.contains(attrName) == true ||
               grandparent.enumeratedAttributes?.contains(attrName) == true
    }

    /// Left accent bar color based on AI status
    private var accentColor: Color? {
        guard hasAIReview else { return nil }
        if node.status == .aiToReplace { return .orange }
        guard let parent = node.parent, let grandparent = parent.parent else { return nil }
        let attrName = node.name.isEmpty ? node.displayLabel : node.name
        if grandparent.enumeratedAttributes?.contains(attrName) == true { return .cyan }
        if grandparent.bundledAttributes?.contains(attrName) == true { return .purple }
        return nil
    }

    /// The collection (grandparent) node for AI configuration
    private var collectionNode: TreeNode? {
        node.parent?.parent
    }

    /// Attribute name for AI configuration
    private var attrName: String {
        node.name.isEmpty ? node.displayLabel : node.name
    }

    /// Whether this field can be configured for AI review
    private var supportsAIConfig: Bool {
        guard let collection = collectionNode else { return false }
        return collection.parent != nil  // Has a great-grandparent (is under a collection)
    }

    /// Whether this attribute is bundled
    private var isBundled: Bool {
        collectionNode?.bundledAttributes?.contains(attrName) == true
    }

    /// Whether this attribute is iterated
    private var isIterated: Bool {
        collectionNode?.enumeratedAttributes?.contains(attrName) == true
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // AI accent bar
            if let color = accentColor {
                RoundedRectangle(cornerRadius: 1)
                    .fill(color.opacity(0.6))
                    .frame(width: 3)
                    .padding(.trailing, 8)
            }

            // Content
            if isEditing {
                editingView
            } else {
                displayView
            }
        }
        .onHover { isHovering = $0 }
        .contextMenu {
            if supportsAIConfig {
                attributeAIContextMenu
            }
        }
    }

    // MARK: - AI Context Menu

    @ViewBuilder
    private var attributeAIContextMenu: some View {
        Text("AI Review: \(attrName)")

        Divider()

        Button {
            setAttributeMode(.bundle)
        } label: {
            HStack {
                Image(systemName: "square.on.square.squareshape.controlhandles")
                    .foregroundColor(.purple)
                Text("Bundle – 1 review")
                if isBundled { Image(systemName: "checkmark") }
            }
        }

        Button {
            setAttributeMode(.iterate)
        } label: {
            HStack {
                Image(systemName: "flowchart")
                    .foregroundColor(.cyan)
                Text("Iterate – N reviews")
                if isIterated { Image(systemName: "checkmark") }
            }
        }

        if hasAIReview {
            Divider()

            Button(role: .destructive) {
                setAttributeMode(.off)
            } label: {
                Label("Disable AI Review", systemImage: "xmark.circle")
            }
        }
    }

    private func setAttributeMode(_ mode: AIReviewMode) {
        guard let collection = collectionNode else { return }

        // Remove from both first
        if var bundled = collection.bundledAttributes {
            bundled.removeAll { $0 == attrName }
            collection.bundledAttributes = bundled.isEmpty ? nil : bundled
        }
        if var enumerated = collection.enumeratedAttributes {
            enumerated.removeAll { $0 == attrName }
            collection.enumeratedAttributes = enumerated.isEmpty ? nil : enumerated
        }

        // Add to appropriate list
        if mode == .bundle {
            var bundled = collection.bundledAttributes ?? []
            bundled.append(attrName)
            collection.bundledAttributes = bundled
        } else if mode == .iterate {
            var enumerated = collection.enumeratedAttributes ?? []
            enumerated.append(attrName)
            collection.enumeratedAttributes = enumerated
        }
    }

    @ViewBuilder
    private var displayView: some View {
        VStack(alignment: .leading, spacing: 1) {
            if showLabel && !node.name.isEmpty {
                Text(node.name)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            if !node.value.isEmpty {
                Text(node.value)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
            } else if node.value.isEmpty && node.name.isEmpty {
                Text("Empty")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .italic()
            }
        }

        Spacer(minLength: 0)

        // Edit button (appears on hover)
        if isHovering && node.status != .disabled {
            Button(action: { vm.startEditing(node: node) }) {
                Image(systemName: "pencil")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
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
        guard let parent = node.parent,
              let entry = parent.parent,
              let collection = entry.parent else { return false }
        let containerName = parent.name.isEmpty ? parent.displayLabel : parent.name
        return collection.enumeratedAttributes?.contains(containerName + "[]") == true ||
               collection.bundledAttributes?.contains(containerName + "[]") == true
    }

    /// Left accent color based on AI status
    private var accentColor: Color? {
        guard hasAIReview else { return nil }
        if node.status == .aiToReplace { return .orange }
        return .cyan
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            // Bullet or AI accent
            if let color = accentColor {
                Circle()
                    .fill(color.opacity(0.7))
                    .frame(width: 5, height: 5)
                    .padding(.top, 5)
            } else {
                Circle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 4, height: 4)
                    .padding(.top, 6)
            }

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
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)

                if isHovering && node.status != .disabled {
                    Button(action: { vm.startEditing(node: node) }) {
                        Image(systemName: "pencil")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 2)
        .onHover { isHovering = $0 }
    }
}
