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

    /// The parent (section) node
    private var sectionNode: TreeNode? {
        node.parent
    }

    /// The title/name node (hidden from card content but shown as header icon)
    private var titleNode: TreeNode? {
        let title = node.computedTitle.lowercased()
        return node.orderedChildren.first { child in
            child.name.lowercased() == "name" && child.value.lowercased() == title
        }
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
                    .stroke(Color(.separatorColor).opacity(0.5), lineWidth: 1)
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
            // AI icon for the title/name field (shown here since the name field is hidden from content)
            if let titleNode = titleNode {
                let mode = AIIconModeResolver.detectSingleMode(for: titleNode)
                AIStatusIcon(
                    mode: mode,
                    onTap: { toggleTitleSoloMode() }
                )
            }

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

    private func toggleTitleSoloMode() {
        guard let titleNode = titleNode else { return }
        if titleNode.status == .aiToReplace {
            titleNode.status = .saved
        } else {
            titleNode.status = .aiToReplace
        }
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
        let containerNameWithSuffix = containerName + "[]"

        // Get full icon resolution for this nested container (may be dual with arrow)
        let iconResolution = AIIconModeResolver.resolve(for: child)

        VStack(alignment: .leading, spacing: 6) {
            // Header row with AI icon(s)
            HStack(spacing: 6) {
                // AI status menu - click to configure AI review for this collection
                Menu {
                    if let section = sectionNode {
                        nestedContainerContextMenu(section: section, containerName: containerName, containerNameWithSuffix: containerNameWithSuffix)
                    }
                } label: {
                    ResolvedAIIcon(resolution: iconResolution)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)

                Text(child.displayLabel.titleCased)
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
            if let section = sectionNode {
                nestedContainerContextMenu(section: section, containerName: containerName, containerNameWithSuffix: containerNameWithSuffix)
            }
        }
    }

    @ViewBuilder
    private func nestedContainerContextMenu(section: TreeNode, containerName: String, containerNameWithSuffix: String) -> some View {
        let isBundled = section.bundledAttributes?.contains(containerName) == true
        let isIteratedBundled = section.enumeratedAttributes?.contains(containerName) == true
        let isIteratedEach = section.enumeratedAttributes?.contains(containerNameWithSuffix) == true
        let hasAIConfig = isBundled || isIteratedBundled || isIteratedEach

        Text("AI Review: \(containerName)")

        Divider()

        // Bundle all (1 review for all items across all entries)
        Button {
            setContainerMode(collection: section, attr: containerName, mode: .bundle)
        } label: {
            HStack {
                Image(systemName: "circle.hexagongrid.circle")
                    .foregroundColor(.purple)
                Text("Bundle - 1 review")
                if isBundled { Image(systemName: "checkmark") }
            }
        }

        // Iterate bundled (N reviews, each entry's items together)
        Button {
            setContainerMode(collection: section, attr: containerName, mode: .iterate)
        } label: {
            HStack {
                Image(systemName: "film.stack")
                    .foregroundColor(.indigo)
                Text("Iterate (bundled) - N reviews")
                if isIteratedBundled { Image(systemName: "checkmark") }
            }
        }

        // Iterate each (N×M reviews, each item separate)
        Button {
            setContainerMode(collection: section, attr: containerNameWithSuffix, mode: .iterate)
        } label: {
            HStack {
                Image(systemName: "film.stack")
                    .foregroundColor(.indigo)
                Text("Iterate (each) - N×M reviews")
                if isIteratedEach { Image(systemName: "checkmark") }
            }
        }

        if hasAIConfig {
            Divider()

            Button(role: .destructive) {
                setContainerMode(collection: section, attr: containerName, mode: .off)
            } label: {
                Label("Disable AI Review", systemImage: "xmark.circle")
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
        if node.parent?.schemaInputKind == .chips { return true }
        return false
    }

    private func chipSourceKey(for node: TreeNode) -> String? {
        if let explicit = node.schemaSourceKey { return explicit }
        if let parentSource = node.parent?.schemaSourceKey { return parentSource }
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

    private var isEditing: Bool { vm.editingNodeID == node.id }

    /// Get the icon mode for this field
    private var iconMode: AIIconMode {
        AIIconModeResolver.detectSingleMode(for: node)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // AI status menu - click to configure AI review
            Menu {
                attributeAIContextMenu
            } label: {
                AIIconImage(mode: iconMode)
                    .padding(4)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help(iconMode.helpText)

            // Content
            if isEditing {
                editingView
            } else {
                displayView
            }
        }
        .contextMenu {
            attributeAIContextMenu
        }
    }

    // MARK: - AI Context Menu

    private var isSolo: Bool {
        node.status == .aiToReplace
    }

    /// The collection (grandparent) node for AI configuration
    private var collectionNode: TreeNode? {
        node.parent?.parent
    }

    /// Attribute name for AI configuration
    private var attrName: String {
        node.name.isEmpty ? node.displayLabel : node.name
    }

    /// Whether this attribute is bundled
    private var isBundled: Bool {
        collectionNode?.bundledAttributes?.contains(attrName) == true
    }

    /// Whether this attribute is iterated
    private var isIterated: Bool {
        collectionNode?.enumeratedAttributes?.contains(attrName) == true
    }

    /// Whether this field has AI review configured
    private var hasAIReview: Bool {
        isSolo || isBundled || isIterated
    }

    /// Whether this field can be configured for AI review
    private var supportsAIConfig: Bool {
        guard let collection = collectionNode else { return false }
        return collection.parent != nil
    }

    @ViewBuilder
    private var attributeAIContextMenu: some View {
        Text("AI Review: \(attrName)")

        Divider()

        // Solo option - always available for any field
        Button {
            toggleSoloMode()
        } label: {
            HStack {
                Image(systemName: "target")
                    .foregroundColor(.teal)
                Text("Solo - this field only")
                if isSolo { Image(systemName: "checkmark") }
            }
        }

        // Bundle/Iterate options - only for fields under collections
        if supportsAIConfig {
            Divider()

            Button {
                setAttributeMode(.bundle)
            } label: {
                HStack {
                    Image(systemName: "circle.hexagongrid.circle")
                        .foregroundColor(.purple)
                    Text("Bundle - 1 review")
                    if isBundled { Image(systemName: "checkmark") }
                }
            }

            Button {
                setAttributeMode(.iterate)
            } label: {
                HStack {
                    Image(systemName: "film.stack")
                        .foregroundColor(.indigo)
                    Text("Iterate - N reviews")
                    if isIterated { Image(systemName: "checkmark") }
                }
            }
        }

        if hasAIReview {
            Divider()

            Button(role: .destructive) {
                disableAllAIReview()
            } label: {
                Label("Disable AI Review", systemImage: "xmark.circle")
            }
        }
    }

    private func toggleSoloMode() {
        if isSolo {
            node.status = .saved
        } else {
            // Clear any collection-level settings for this attribute first
            if let collection = collectionNode {
                if var bundled = collection.bundledAttributes {
                    bundled.removeAll { $0 == attrName }
                    collection.bundledAttributes = bundled.isEmpty ? nil : bundled
                }
                if var enumerated = collection.enumeratedAttributes {
                    enumerated.removeAll { $0 == attrName }
                    collection.enumeratedAttributes = enumerated.isEmpty ? nil : enumerated
                }
            }
            node.status = .aiToReplace
        }
    }

    private func setAttributeMode(_ mode: AIReviewMode) {
        guard let collection = collectionNode else { return }

        // Clear solo mode if set
        if isSolo {
            node.status = .saved
        }

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

    private func disableAllAIReview() {
        // Clear solo mode
        if isSolo {
            node.status = .saved
        }

        // Clear collection-level settings
        if let collection = collectionNode {
            if var bundled = collection.bundledAttributes {
                bundled.removeAll { $0 == attrName }
                collection.bundledAttributes = bundled.isEmpty ? nil : bundled
            }
            if var enumerated = collection.enumeratedAttributes {
                enumerated.removeAll { $0 == attrName }
                collection.enumeratedAttributes = enumerated.isEmpty ? nil : enumerated
            }
        }
    }

    @ViewBuilder
    private var displayView: some View {
        Button(action: { vm.startEditing(node: node) }) {
            VStack(alignment: .leading, spacing: 1) {
                if showLabel && !node.name.isEmpty {
                    Text(node.name.titleCased)
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
        }
        .buttonStyle(.plain)
        .disabled(node.status == .disabled)
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

    private var isEditing: Bool { vm.editingNodeID == node.id }

    /// Get the icon mode for this bullet item
    private var iconMode: AIIconMode {
        AIIconModeResolver.detectSingleMode(for: node)
    }

    /// Whether this item is marked as solo
    private var isSolo: Bool {
        node.status == .aiToReplace
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            // AI status menu - click to configure AI review
            Menu {
                bulletAIContextMenu
            } label: {
                AIIconImage(mode: iconMode)
                    .padding(4)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help(iconMode.helpText)

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
                Button(action: { vm.startEditing(node: node) }) {
                    Text(node.value.isEmpty ? node.name : node.value)
                        .font(.system(size: 12))
                        .foregroundStyle(.primary)

                    Spacer(minLength: 0)
                }
                .buttonStyle(.plain)
                .disabled(node.status == .disabled)
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            bulletAIContextMenu
        }
    }

    @ViewBuilder
    private var bulletAIContextMenu: some View {
        let itemLabel = node.value.isEmpty ? node.name : node.value
        let truncatedLabel = itemLabel.count > 30 ? String(itemLabel.prefix(30)) + "..." : itemLabel

        Text("AI Review: \(truncatedLabel)")

        Divider()

        Button {
            toggleSoloMode()
        } label: {
            HStack {
                Image(systemName: "target")
                    .foregroundColor(.teal)
                Text("Solo - this item only")
                if isSolo { Image(systemName: "checkmark") }
            }
        }

        if isSolo {
            Divider()

            Button(role: .destructive) {
                node.status = .saved
            } label: {
                Label("Disable AI Review", systemImage: "xmark.circle")
            }
        }
    }

    private func toggleSoloMode() {
        if isSolo {
            node.status = .saved
        } else {
            node.status = .aiToReplace
        }
    }
}
