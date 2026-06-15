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

            if node.allowsDeletion {
                Button(action: { vm.deleteNode(node, context: modelContext) }) {
                    Image(systemName: "trash")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Delete entry")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.windowBackgroundColor).opacity(0.5))
        .contextMenu {
            Button {
                Logger.debug("[ResumeEntryCardView] Rename triggered for: '\(node.computedTitle)'")
                renameTitleText = node.computedTitle
                isRenamingTitle = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isRenameFocused = true
                }
            } label: {
                Label("Rename", systemImage: "pencil")
            }

            if node.allowsDeletion {
                Divider()
                Button(role: .destructive) {
                    vm.deleteNode(node, context: modelContext)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    private func commitTitleRename() {
        let trimmed = renameTitleText.trimmingCharacters(in: .whitespacesAndNewlines)
        Logger.debug("[ResumeEntryCardView] commitTitleRename: '\(trimmed)' for node '\(node.computedTitle)'")
        guard !trimmed.isEmpty else {
            Logger.debug("[ResumeEntryCardView] commitTitleRename: empty, cancelling")
            cancelTitleRename()
            return
        }
        // Update the title child node's value
        if let titleNode = titleNode {
            Logger.debug("[ResumeEntryCardView] Updating titleNode.value from '\(titleNode.value)' to '\(trimmed)'")
            titleNode.value = trimmed
        } else {
            // No dedicated title child — update the node's own name
            Logger.debug("[ResumeEntryCardView] No titleNode found, updating node.name from '\(node.name)' to '\(trimmed)'")
            node.name = trimmed
        }
        do {
            try modelContext.save()
            vm.refreshPDF()
            Logger.debug("[ResumeEntryCardView] Save succeeded")
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
        let iconMode = AIIconModeResolver.detectSingleMode(for: child)

        VStack(alignment: .leading, spacing: 6) {
            // Header row with AI icon
            HStack(spacing: 6) {
                // AI status menu - click to include/exclude this collection from AI revision
                AIIconNativeMenuButton(mode: iconMode, showDropIndicator: true) {
                    nestedContainerMenu(for: child)
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
            nestedContainerContextMenu(for: child)
        }
    }

    /// Single-toggle native menu for a nested container's AI editability.
    private func nestedContainerMenu(for container: TreeNode) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(ActionMenuItem(
            "Include in AI revision",
            checked: container.status == .aiToReplace
        ) {
            container.status = container.status == .aiToReplace ? .saved : .aiToReplace
        })
        return menu
    }

    /// Right-click context menu for a nested container: single editable toggle.
    @ViewBuilder
    private func nestedContainerContextMenu(for container: TreeNode) -> some View {
        Button {
            container.status = container.status == .aiToReplace ? .saved : .aiToReplace
        } label: {
            HStack {
                Text("Include in AI revision")
                if container.status == .aiToReplace { Image(systemName: "checkmark") }
            }
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
        .onChange(of: node.value) { _, _ in vm.refreshPDF() }
        .onChange(of: node.name) { _, _ in vm.refreshPDF() }
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

    /// Whether this field sits under an editable ancestor (included or opted-out)
    private var isGroupMember: Bool {
        iconMode == .included || iconMode == .excluded
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

    /// Whether this bullet sits under an editable ancestor (included or opted-out)
    private var isGroupMember: Bool {
        iconMode == .included || iconMode == .excluded
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
        .onChange(of: node.value) { _, _ in vm.refreshPDF() }
        .onChange(of: node.name) { _, _ in vm.refreshPDF() }
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
