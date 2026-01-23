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
                    ChipView(
                        node: child,
                        isMatched: isChipMatched(child),
                        onDelete: { vm.deleteNode(child, context: modelContext) },
                        skillStore: skillStore,
                        syncToLibrary: syncToSkillLibrary
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
            HStack(spacing: 3) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                Text("Add")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(.blue)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.blue.opacity(0.1), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.blue.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var addChipWithAutocomplete: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                TextField("Type to search...", text: $newChipText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .frame(minWidth: 100, maxWidth: 160)
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
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(.controlBackgroundColor), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1.5))

            // Autocomplete dropdown
            if showingSuggestions && !autocompleteSuggestions.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(autocompleteSuggestions, id: \.id) { skill in
                        Button {
                            addFromSkillBank(skill)
                        } label: {
                            HStack {
                                Text(skill.canonical)
                                    .font(.system(size: 12))
                                Spacer()
                                Text(skill.category.rawValue)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(Color(.controlBackgroundColor).opacity(0.8))

                        if skill.id != autocompleteSuggestions.last?.id {
                            Divider()
                        }
                    }
                }
                .background(Color(.windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                .frame(maxWidth: 250)
            }
        }
    }

    private var browseSourceButton: some View {
        Button {
            showingBrowser = true
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 10, weight: .medium))
                Text("Browse")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(.controlBackgroundColor), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var skillGapRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.green)
                Text("Matched skills not added:")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            FlowStack(spacing: 4, verticalSpacing: 4) {
                ForEach(gapSuggestions.prefix(6), id: \.id) { skill in
                    Button {
                        addFromSuggestion(skill)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "plus")
                                .font(.system(size: 8, weight: .bold))
                            Text(skill.canonical)
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.1), in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.green.opacity(0.3), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, 4)
    }

    private var recommendationsRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 9))
                    .foregroundStyle(.orange)
                Text("Suggested skills:")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            FlowStack(spacing: 4, verticalSpacing: 4) {
                ForEach(relevantRecommendations.prefix(6), id: \.skillName) { rec in
                    Button {
                        addFromRecommendation(rec)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "plus")
                                .font(.system(size: 8, weight: .bold))
                            Text(rec.skillName)
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.1), in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.orange.opacity(0.3), lineWidth: 1))
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
            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text("Apply changes to skill library")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.checkbox)
        .controlSize(.small)
        .padding(.top, 6)
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
    @FocusState private var isFieldFocused: Bool
    @Environment(\.modelContext) private var modelContext

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
        HStack(spacing: 5) {
            if isMatched {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.green)
            }

            Text(node.value)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)

            Button {
                onDelete()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            isMatched ? Color.green.opacity(0.15) : Color(.controlBackgroundColor),
            in: Capsule()
        )
        .overlay(
            Capsule()
                .strokeBorder(isMatched ? Color.green.opacity(0.4) : Color(.separatorColor), lineWidth: 1)
        )
        .contentShape(Capsule())
        .onTapGesture {
            originalValue = node.value
            editText = node.value
            isEditing = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isFieldFocused = true
            }
        }
    }

    private var editingView: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                TextField("", text: $editText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .frame(minWidth: 60, maxWidth: 150)
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
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.green)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(.controlBackgroundColor), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.accentColor, lineWidth: 1.5))

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
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(Color(.controlBackgroundColor).opacity(0.8))

                        if skill.id != autocompleteSuggestions.last?.id {
                            Divider()
                        }
                    }
                }
                .background(Color(.windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .shadow(color: .black.opacity(0.12), radius: 3, y: 2)
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
