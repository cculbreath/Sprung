//
//  ChipChildrenView.swift
//  Sprung
//
//  Displays TreeNode children as horizontal chips with skill bank integration.
//

import SwiftUI
import SwiftData

struct ChipChildrenView: View {
    let children: [TreeNode]
    let parent: TreeNode

    /// Matched skill IDs for highlighting (passed from job context)
    var matchedSkillIds: Set<UUID> = []

    /// Source key for browsing (from manifest: "skillBank", etc.)
    var sourceKey: String?

    @Environment(ResumeDetailVM.self) private var vm
    @Environment(SkillStore.self) private var skillStore
    @Environment(DragInfo.self) private var dragInfo
    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(\.modelContext) private var modelContext

    @State private var isAddingChip: Bool = false
    @State private var newChipText: String = ""
    @State private var showingBrowser: Bool = false
    @State private var showingSuggestions: Bool = false
    @State private var syncToSkillLibrary: Bool = false
    @FocusState private var isTextFieldFocused: Bool

    /// Skill recommendations from job preprocessing
    private var skillRecommendations: [SkillRecommendation] {
        parent.resume.jobApp?.extractedRequirements?.skillRecommendations ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Chip flow with indentation
            FlowStack(spacing: 6, verticalSpacing: 6) {
                ForEach(children, id: \.id) { child in
                    let canReorder = parent.schemaAllowsChildMutation
                    ChipView(
                        node: child,
                        isMatched: isChipMatched(child),
                        onDelete: { vm.deleteNode(child, context: modelContext) },
                        skillStore: skillStore,
                        syncToLibrary: syncToSkillLibrary
                    )
                    .opacity(dragInfo.draggedNode == child ? 0.4 : 1.0)
                    .overlay(chipDropIndicator(for: child))
                    .onDrag {
                        guard canReorder else { return NSItemProvider() }
                        dragInfo.draggedNode = child
                        return NSItemProvider(object: child.id as NSString)
                    }
                    .onDrop(
                        of: [.plainText],
                        delegate: ChipDropDelegate(
                            node: child,
                            siblings: children,
                            dragInfo: dragInfo,
                            appEnvironment: appEnvironment,
                            canReorder: canReorder
                        )
                    )
                }

                // Add chip button / text field with autocomplete
                if parent.schemaAllowsChildMutation {
                    if isAddingChip {
                        addChipWithAutocomplete
                    } else {
                        HStack(spacing: 4) {
                            addChipButton
                            if sourceKey == "skillBank" {
                                browseSourceButton
                            }
                        }
                    }
                }
            }
            .padding(.leading, 16) // Indent under disclosure

            // Skill recommendations from preprocessing
            if !relevantRecommendations.isEmpty {
                recommendationsRow
                    .padding(.leading, 16)
            }

            // Gap suggestions (matched skills from job not yet added)
            if !gapSuggestions.isEmpty {
                skillGapRow
                    .padding(.leading, 16)
            }

            // Sync to skill library toggle (only for skill bank connected chips)
            if sourceKey == "skillBank" {
                syncToggleRow
                    .padding(.leading, 16)
            }
        }
        .padding(.vertical, 4)
        .sheet(isPresented: $showingBrowser) {
            SkillSelectionSheet(
                existingValues: children.map { $0.value },
                onSelect: addFromSkillBank
            )
        }
    }

    // MARK: - Autocomplete Suggestions

    private var autocompleteSuggestions: [Skill] {
        guard sourceKey == "skillBank", !newChipText.isEmpty else { return [] }
        let search = newChipText.lowercased()
        let existing = Set(children.map { $0.value.lowercased() })

        return skillStore.approvedSkills
            .filter { skill in
                !existing.contains(skill.canonical.lowercased()) &&
                (skill.canonical.lowercased().contains(search) ||
                 skill.atsVariants.contains { $0.lowercased().contains(search) })
            }
            .prefix(6)
            .map { $0 }
    }

    /// Recommendations relevant to this skill category (not already added)
    private var relevantRecommendations: [SkillRecommendation] {
        let existing = Set(children.map { $0.value.lowercased() })
        // Filter recommendations that aren't already in this category
        return skillRecommendations.filter { rec in
            !existing.contains(rec.skillName.lowercased())
        }
    }

    // MARK: - Subviews

    private var addChipButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                isAddingChip = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isTextFieldFocused = true
            }
        } label: {
            HStack(spacing: 2) {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .semibold))
                Text("Add")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(.controlBackgroundColor).opacity(0.6), in: Capsule())
            .overlay(Capsule().strokeBorder(Color(.separatorColor).opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var addChipWithAutocomplete: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                TextField("Type to search...", text: $newChipText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .frame(minWidth: 80, maxWidth: 140)
                    .focused($isTextFieldFocused)
                    .onChange(of: newChipText) { _, newValue in
                        showingSuggestions = !newValue.isEmpty && !autocompleteSuggestions.isEmpty
                    }
                    .onSubmit {
                        if let firstSuggestion = autocompleteSuggestions.first {
                            addFromSkillBank(firstSuggestion)
                        } else {
                            addChild()
                        }
                    }
                    .onExitCommand {
                        cancelAdd()
                    }

                Button {
                    cancelAdd()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(.controlBackgroundColor), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.accentColor.opacity(0.4), lineWidth: 1))

            // Autocomplete dropdown
            if showingSuggestions && !autocompleteSuggestions.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(autocompleteSuggestions, id: \.id) { skill in
                        Button {
                            addFromSkillBank(skill)
                        } label: {
                            HStack {
                                Text(skill.canonical)
                                    .font(.system(size: 11))
                                Spacer()
                                Text(skill.category)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(Color(.controlBackgroundColor).opacity(0.6))

                        if skill.id != autocompleteSuggestions.last?.id {
                            Divider()
                        }
                    }
                }
                .background(Color(.windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
                .frame(maxWidth: 220)
            }
        }
    }

    private var browseSourceButton: some View {
        Button {
            showingBrowser = true
        } label: {
            HStack(spacing: 2) {
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 9, weight: .medium))
                Text("Browse")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(.controlBackgroundColor).opacity(0.6), in: Capsule())
            .overlay(Capsule().strokeBorder(Color(.separatorColor).opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var skillGapRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 3) {
                Image(systemName: "checkmark.seal")
                    .font(.system(size: 8))
                    .foregroundStyle(.green.opacity(0.8))
                Text("Matched skills not added:")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }

            FlowStack(spacing: 4, verticalSpacing: 4) {
                ForEach(gapSuggestions.prefix(6), id: \.id) { skill in
                    Button {
                        addFromSuggestion(skill)
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "plus")
                                .font(.system(size: 7, weight: .bold))
                            Text(skill.canonical)
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundStyle(.green.opacity(0.9))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.green.opacity(0.08), in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.green.opacity(0.25), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, 4)
    }

    private var recommendationsRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 3) {
                Image(systemName: "sparkles")
                    .font(.system(size: 8))
                    .foregroundStyle(.orange.opacity(0.8))
                Text("Suggested skills:")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }

            FlowStack(spacing: 4, verticalSpacing: 4) {
                ForEach(relevantRecommendations.prefix(6), id: \.skillName) { rec in
                    Button {
                        addFromRecommendation(rec)
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "plus")
                                .font(.system(size: 7, weight: .bold))
                            Text(rec.skillName)
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundStyle(.orange.opacity(0.9))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.08), in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.orange.opacity(0.25), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help(rec.reason)
                }
            }
        }
        .padding(.top, 4)
    }

    private var syncToggleRow: some View {
        Toggle(isOn: $syncToSkillLibrary) {
            HStack(spacing: 3) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                Text("Apply changes to skill library")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .toggleStyle(.checkbox)
        .controlSize(.small)
        .padding(.top, 4)
        .help("When enabled, edits to skill names will also update the corresponding skill in your skill library")
    }

    // MARK: - Logic

    private func isChipMatched(_ node: TreeNode) -> Bool {
        guard !matchedSkillIds.isEmpty else { return false }
        let chipValue = node.value.lowercased()
        return skillStore.skills.contains { skill in
            matchedSkillIds.contains(skill.id) &&
            (skill.canonical.lowercased() == chipValue ||
             skill.atsVariants.contains { $0.lowercased() == chipValue })
        }
    }

    private var gapSuggestions: [Skill] {
        guard !matchedSkillIds.isEmpty else { return [] }
        let existing = Set(children.map { $0.value.lowercased() })
        return skillStore.skills.filter { skill in
            matchedSkillIds.contains(skill.id) &&
            !existing.contains(skill.canonical.lowercased())
        }
    }

    private func addChild() {
        let trimmed = newChipText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            cancelAdd()
            return
        }

        let newNode = TreeNode(
            name: "",
            value: trimmed,
            children: nil,
            parent: parent,
            inEditor: true,
            status: .saved,
            resume: parent.resume,
            isTitleNode: false
        )
        newNode.myIndex = children.count
        parent.addChild(newNode)

        do {
            try modelContext.save()
        } catch {
            Logger.error("Failed to save new chip: \(error)")
        }

        newChipText = ""
        showingSuggestions = false
        isAddingChip = false
    }

    private func cancelAdd() {
        newChipText = ""
        showingSuggestions = false
        isAddingChip = false
    }

    private func addFromSkillBank(_ skill: Skill) {
        let newNode = TreeNode(
            name: "",
            value: skill.canonical,
            children: nil,
            parent: parent,
            inEditor: true,
            status: .saved,
            resume: parent.resume,
            isTitleNode: false
        )
        newNode.myIndex = children.count
        parent.addChild(newNode)

        do {
            try modelContext.save()
        } catch {
            Logger.error("Failed to save skill from bank: \(error)")
        }

        newChipText = ""
        showingSuggestions = false
        isAddingChip = false
        showingBrowser = false
    }

    private func addFromSuggestion(_ skill: Skill) {
        addFromSkillBank(skill)
    }

    @ViewBuilder
    private func chipDropIndicator(for child: TreeNode) -> some View {
        if dragInfo.dropTargetNode == child {
            GeometryReader { proxy in
                let isLeft = dragInfo.dropPosition == .above
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 2)
                    .position(
                        x: isLeft ? 0 : proxy.size.width,
                        y: proxy.size.height / 2
                    )
            }
            .allowsHitTesting(false)
        }
    }

    private func addFromRecommendation(_ rec: SkillRecommendation) {
        let newNode = TreeNode(
            name: "",
            value: rec.skillName,
            children: nil,
            parent: parent,
            inEditor: true,
            status: .saved,
            resume: parent.resume,
            isTitleNode: false
        )
        newNode.myIndex = children.count
        parent.addChild(newNode)

        do {
            try modelContext.save()
        } catch {
            Logger.error("Failed to save recommendation: \(error)")
        }
    }
}

// MARK: - Chip View

private struct ChipView: View {
    let node: TreeNode
    let isMatched: Bool
    let onDelete: () -> Void
    let skillStore: SkillStore
    var syncToLibrary: Bool = false

    @State private var isEditing: Bool = false
    @State private var editText: String = ""
    @State private var originalValue: String = ""
    @State private var showingSuggestions: Bool = false
    @State private var isHovering: Bool = false
    @FocusState private var isFieldFocused: Bool
    @Environment(\.modelContext) private var modelContext

    /// Get the icon mode for this chip node
    private var iconMode: AIIconMode {
        AIIconModeResolver.detectSingleMode(for: node)
    }

    private var autocompleteSuggestions: [Skill] {
        guard !editText.isEmpty else { return [] }
        let search = editText.lowercased()
        return skillStore.approvedSkills
            .filter { skill in
                skill.canonical.lowercased().contains(search) ||
                skill.atsVariants.contains { $0.lowercased().contains(search) }
            }
            .prefix(5)
            .map { $0 }
    }

    var body: some View {
        if isEditing {
            editingView
        } else {
            displayView
        }
    }

    private var displayView: some View {
        HStack(spacing: 4) {
            if isMatched {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.green)
            }

            Text(node.value)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)

            // AI status icon (trailing): group members get menu, ungrouped toggle directly
            if node.status != LeafStatus.disabled {
                if isGroupMember {
                    AIIconMenuButton(mode: iconMode, size: 11) { dismiss in
                        PopoverMenuItem(
                            "Exclude from group review",
                            isChecked: node.status == .excludedFromGroup
                        ) {
                            node.status = node.status == .excludedFromGroup ? .saved : .excludedFromGroup
                            dismiss()
                        }
                    }
                } else {
                    AIStatusIcon(mode: iconMode, size: 11) {
                        node.status = node.status == .aiToReplace ? .saved : .aiToReplace
                    }
                }
            }

            // Delete button - use opacity to avoid reflow
            Button {
                onDelete()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(isHovering ? 1 : 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            isMatched ? Color.green.opacity(0.12) : Color(.controlBackgroundColor).opacity(0.8),
            in: Capsule()
        )
        .overlay(
            Capsule()
                .strokeBorder(isMatched ? Color.green.opacity(0.35) : Color(.separatorColor).opacity(0.6), lineWidth: 1)
        )
        .contentShape(Capsule())
        .onHover { isHovering = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovering)
        .onTapGesture {
            originalValue = node.value
            editText = node.value
            isEditing = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isFieldFocused = true
            }
        }
    }

    /// Whether this chip is a member of a group review (bundled or iterated)
    private var isGroupMember: Bool {
        iconMode == .bundledMember || iconMode == .iteratedMember ||
        iconMode == .excludedBundledMember || iconMode == .excludedIteratedMember
    }

    private var editingView: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                TextField("", text: $editText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .frame(minWidth: 60, maxWidth: 140)
                    .focused($isFieldFocused)
                    .onChange(of: editText) { _, newValue in
                        showingSuggestions = !newValue.isEmpty && !autocompleteSuggestions.isEmpty
                    }
                    .onSubmit {
                        if let firstSuggestion = autocompleteSuggestions.first,
                           firstSuggestion.canonical.lowercased() == editText.lowercased() {
                            editText = firstSuggestion.canonical
                        }
                        commitEdit()
                    }
                    .onExitCommand {
                        cancelEdit()
                    }

                Button {
                    commitEdit()
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.green)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(.controlBackgroundColor), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 1))

            // Autocomplete dropdown
            if showingSuggestions && !autocompleteSuggestions.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(autocompleteSuggestions, id: \.id) { skill in
                        Button {
                            editText = skill.canonical
                            showingSuggestions = false
                            commitEdit()
                        } label: {
                            Text(skill.canonical)
                                .font(.system(size: 11))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(Color(.controlBackgroundColor).opacity(0.6))

                        if skill.id != autocompleteSuggestions.last?.id {
                            Divider()
                        }
                    }
                }
                .background(Color(.windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
            }
        }
    }

    private func commitEdit() {
        let trimmed = editText.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            node.value = trimmed
            do {
                try modelContext.save()
            } catch {
                Logger.error("Failed to save chip edit: \(error)")
            }

            // Sync to skill library if enabled
            if syncToLibrary && trimmed != originalValue {
                syncToSkillLibrary(oldValue: originalValue, newValue: trimmed)
            }
        }
        showingSuggestions = false
        isEditing = false
    }

    private func syncToSkillLibrary(oldValue: String, newValue: String) {
        // Find matching skill by canonical name or variant
        let oldLower = oldValue.lowercased()
        if let matchingSkill = skillStore.skills.first(where: { skill in
            skill.canonical.lowercased() == oldLower ||
            skill.atsVariants.contains { $0.lowercased() == oldLower }
        }) {
            // Update the canonical name
            matchingSkill.canonical = newValue
            Logger.info("Synced skill edit to library: '\(oldValue)' -> '\(newValue)'")
        }
    }

    private func cancelEdit() {
        showingSuggestions = false
        isEditing = false
    }
}

// MARK: - Chip Drop Delegate

private struct ChipDropDelegate: DropDelegate {
    let node: TreeNode
    let siblings: [TreeNode]
    let dragInfo: DragInfo
    let appEnvironment: AppEnvironment
    let canReorder: Bool

    func validateDrop(info: DropInfo) -> Bool {
        guard canReorder,
              let dragged = dragInfo.draggedNode,
              dragged != node,
              dragged.parent?.id == node.parent?.id else { return false }
        return true
    }

    func dropEntered(info: DropInfo) {
        guard canReorder,
              let dragged = dragInfo.draggedNode,
              dragged != node,
              dragged.parent?.id == node.parent?.id else { return }

        DispatchQueue.main.async {
            dragInfo.dropTargetNode = node
            // For chips in a flow layout, use left/right (mapped to above/below)
            let midX = info.location.x
            dragInfo.dropPosition = midX < 20 ? .above : .below
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard canReorder else { return nil }
        // Update left/right position as cursor moves within the chip
        if let dragged = dragInfo.draggedNode,
           dragged != node,
           dragged.parent?.id == node.parent?.id {
            let midX = info.location.x
            dragInfo.dropPosition = midX < 20 ? .above : .below
        }
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard canReorder,
              let dragged = dragInfo.draggedNode,
              dragged.parent?.id == node.parent?.id else { return false }

        reorder(draggedNode: dragged, overNode: node)

        dragInfo.draggedNode = nil
        dragInfo.dropTargetNode = nil
        dragInfo.dropPosition = .none
        return true
    }

    func dropExited(info: DropInfo) {
        guard canReorder else { return }
        dragInfo.dropTargetNode = nil
        dragInfo.dropPosition = .none
    }

    private func reorder(draggedNode: TreeNode, overNode: TreeNode) {
        guard let parent = overNode.parent, var array = parent.children else { return }
        array.sort { $0.myIndex < $1.myIndex }
        guard let fromIndex = array.firstIndex(of: draggedNode),
              let toIndex = array.firstIndex(of: overNode) else { return }

        withAnimation(.easeInOut) {
            array.remove(at: fromIndex)
            let insertionIndex = (dragInfo.dropPosition == .above) ? toIndex : toIndex + 1
            let boundedIndex = max(0, min(insertionIndex, array.count))
            array.insert(draggedNode, at: boundedIndex)
            for (index, node) in array.enumerated() {
                node.myIndex = index
            }
            parent.children = array
        }

        do {
            try parent.resume.modelContext?.save()
        } catch {
            Logger.warning("Failed to save reordered chips: \(error.localizedDescription)", category: .storage)
        }
        appEnvironment.resumeExportCoordinator.debounceExport(resume: parent.resume)
    }
}
