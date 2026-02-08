//
//  ResumeEntryCardView.swift
//  Sprung
//
//  Card-based view for resume entries (work experience, education, skills, etc.)
//  Professional design with clear visual hierarchy and refined styling.
//

import AppKit
import SwiftUI

/// Card view for a single resume entry (job, school, skill category, etc.)
struct ResumeEntryCardView: View {
    let node: TreeNode
    let depthOffset: Int
    @Environment(ResumeDetailVM.self) private var vm: ResumeDetailVM
    @Environment(\.modelContext) private var modelContext

    // Inline title rename state
    @State private var isRenamingTitle = false
    @State private var renameTitleText = ""
    @FocusState private var isRenameFocused: Bool

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

            if isRenamingTitle {
                TextField("Name", text: $renameTitleText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .focused($isRenameFocused)
                    .onSubmit { commitTitleRename() }
                    .onExitCommand { cancelTitleRename() }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color(.textBackgroundColor), in: RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1))
            } else {
                Text(node.computedTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .onTapGesture {
                        renameTitleText = node.computedTitle
                        isRenamingTitle = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isRenameFocused = true
                        }
                    }
            }

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
        .contextMenu {
            Button {
                print("[ResumeEntryCardView] Rename triggered for: '\(node.computedTitle)'")
                renameTitleText = node.computedTitle
                isRenamingTitle = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isRenameFocused = true
                }
            } label: {
                Label("Rename", systemImage: "pencil")
            }
        }
    }

    private func commitTitleRename() {
        let trimmed = renameTitleText.trimmingCharacters(in: .whitespacesAndNewlines)
        print("[ResumeEntryCardView] commitTitleRename: '\(trimmed)' for node '\(node.computedTitle)'")
        guard !trimmed.isEmpty else {
            print("[ResumeEntryCardView] commitTitleRename: empty, cancelling")
            cancelTitleRename()
            return
        }
        // Update the title child node's value
        if let titleNode = titleNode {
            print("[ResumeEntryCardView] Updating titleNode.value from '\(titleNode.value)' to '\(trimmed)'")
            titleNode.value = trimmed
        } else {
            // No dedicated title child — update the node's own name
            print("[ResumeEntryCardView] No titleNode found, updating node.name from '\(node.name)' to '\(trimmed)'")
            node.name = trimmed
        }
        do {
            try modelContext.save()
            vm.refreshPDF()
            print("[ResumeEntryCardView] Save succeeded")
        } catch {
            Logger.error("Failed to save title rename: \(error)")
        }
        isRenamingTitle = false
    }

    private func cancelTitleRename() {
        isRenamingTitle = false
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
                if let section = sectionNode {
                    ResolvedAIIconNativeMenuButton(resolution: iconResolution) {
                        self.buildNestedContainerMenu(
                            section: section,
                            containerName: containerName,
                            containerNameWithSuffix: containerNameWithSuffix
                        )
                    }
                } else {
                    ResolvedAIIcon(resolution: iconResolution)
                        .padding(4)
                }

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

    /// Build native NSMenu for nested container AI configuration.
    /// Structure: Bundle▶ → [leaf], Iterate▶ → [leaf], Disable
    private func buildNestedContainerMenu(section: TreeNode, containerName: String, containerNameWithSuffix: String) -> NSMenu {
        let menu = NSMenu()

        let isBundled = section.bundledAttributes?.contains(containerName) == true
        let isIteratedBundled = section.enumeratedAttributes?.contains(containerName) == true
        let isIteratedEach = section.enumeratedAttributes?.contains(containerNameWithSuffix) == true
        let hasConfig = isBundled || isIteratedBundled || isIteratedEach
        let leaf = nestedLeafLabel(for: containerName)

        // Children's collection mode (independent of which list stores the attribute)
        // "Bundle" = children grouped together: attr without [] in either list
        // "Iterate" = children handled individually: attr with [] suffix
        let childrenBundled = isBundled || isIteratedBundled
        let childrenIterated = isIteratedEach

        // Bundle ▶ → leaf item
        let bundleItem = NSMenuItem(title: "Bundle", action: nil, keyEquivalent: "")
        bundleItem.state = childrenBundled ? .on : .off
        let bundleSub = NSMenu()
        bundleSub.addItem(ActionMenuItem(leaf, checked: childrenBundled) {
            setContainerMode(collection: section, attr: containerName, mode: .bundle)
        })
        bundleItem.submenu = bundleSub
        menu.addItem(bundleItem)

        // Iterate ▶ → leaf item
        let iterateItem = NSMenuItem(title: "Iterate", action: nil, keyEquivalent: "")
        iterateItem.state = childrenIterated ? .on : .off
        let iterateSub = NSMenu()
        iterateSub.addItem(ActionMenuItem(leaf, checked: childrenIterated) {
            setContainerMode(collection: section, attr: containerNameWithSuffix, mode: .iterate)
        })
        iterateItem.submenu = iterateSub
        menu.addItem(iterateItem)

        if hasConfig {
            menu.addItem(.separator())
            menu.addItem(ActionMenuItem("Disable AI Review") {
                setContainerMode(collection: section, attr: containerName, mode: .off)
            })
        }

        return menu
    }

    /// Simple singularization for leaf display labels (keywords → Keyword)
    private func nestedLeafLabel(for attr: String) -> String {
        let name = attr.titleCased
        if name.hasSuffix("s") && !name.hasSuffix("ss") {
            return String(name.dropLast())
        }
        return name
    }

    /// Context menu content for nested container (right-click) - uses native Menu format
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
            // AI status: group members get menu, ungrouped toggle directly
            if isGroupMember {
                AIIconMenuButton(mode: iconMode) { dismiss in
                    PopoverMenuItem("Exclude from group review", isChecked: isExcluded) {
                        toggleExcludeFromGroup()
                        dismiss()
                    }
                }
            } else {
                AIStatusIcon(mode: iconMode) {
                    toggleSoloMode()
                }
            }

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

    // MARK: - AI Menu (Member - Simple Toggles)

    private var isSolo: Bool {
        node.status == .aiToReplace
    }

    private var isExcluded: Bool {
        node.status == .excludedFromGroup
    }

    /// Whether this field is a member of a group review (bundled or iterated)
    private var isGroupMember: Bool {
        iconMode == .bundledMember || iconMode == .iteratedMember ||
        iconMode == .excludedBundledMember || iconMode == .excludedIteratedMember
    }

    private func toggleSoloMode() {
        node.status = node.status == .aiToReplace ? .saved : .aiToReplace
    }

    /// Context menu content for AI configuration (right-click) - uses native Menu format
    /// Member menus are simple toggles only
    @ViewBuilder
    private var attributeAIContextMenu: some View {
        if isGroupMember {
            Button {
                toggleExcludeFromGroup()
            } label: {
                HStack {
                    Text("Exclude from group review")
                    if isExcluded { Image(systemName: "checkmark") }
                }
            }
        } else if isSolo {
            Button {
                node.status = .saved
            } label: {
                HStack {
                    Image(systemName: "sparkles")
                    Text("Disable solo review")
                }
            }
        } else {
            Button {
                node.status = .aiToReplace
            } label: {
                HStack {
                    Image(systemName: "target")
                        .foregroundColor(.teal)
                    Text("Enable solo review")
                }
            }
        }
    }

    private func toggleExcludeFromGroup() {
        if node.status == .excludedFromGroup {
            node.status = .saved
        } else {
            node.status = .excludedFromGroup
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

    private var isExcluded: Bool {
        node.status == .excludedFromGroup
    }

    /// Whether this bullet is a member of a group review (bundled or iterated)
    private var isGroupMember: Bool {
        iconMode == .bundledMember || iconMode == .iteratedMember ||
        iconMode == .excludedBundledMember || iconMode == .excludedIteratedMember
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            // AI status: group members get menu, ungrouped toggle directly
            if isGroupMember {
                AIIconMenuButton(mode: iconMode) { dismiss in
                    PopoverMenuItem("Exclude from group review", isChecked: isExcluded) {
                        toggleExcludeFromGroup()
                        dismiss()
                    }
                }
            } else {
                AIStatusIcon(mode: iconMode) {
                    toggleSoloMode()
                }
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

    private func toggleSoloMode() {
        node.status = node.status == .aiToReplace ? .saved : .aiToReplace
    }

    /// Context menu content for bullet item AI configuration (right-click)
    /// Member menus are simple toggles only
    @ViewBuilder
    private var bulletAIContextMenu: some View {
        if isGroupMember {
            Button {
                toggleExcludeFromGroup()
            } label: {
                HStack {
                    Text("Exclude from group review")
                    if isExcluded { Image(systemName: "checkmark") }
                }
            }
        } else if isSolo {
            Button {
                node.status = .saved
            } label: {
                HStack {
                    Image(systemName: "sparkles")
                    Text("Disable solo review")
                }
            }
        } else {
            Button {
                node.status = .aiToReplace
            } label: {
                HStack {
                    Image(systemName: "target")
                        .foregroundColor(.teal)
                    Text("Enable solo review")
                }
            }
        }
    }

    private func toggleExcludeFromGroup() {
        if node.status == .excludedFromGroup {
            node.status = .saved
        } else {
            node.status = .excludedFromGroup
        }
    }
}
