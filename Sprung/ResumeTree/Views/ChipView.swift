//
//  ChipView.swift
//  Sprung
//
//  Renders and manages a single skill chip: display state, hover state,
//  inline editing with autocomplete, AI status icon, and optional
//  skill-library sync on edit commit.
//

import SwiftUI
import SwiftData

struct ChipView: View {
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
    @Environment(ResumeDetailVM.self) private var vm

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
        iconMode == .bundledMember || iconMode == .iteratedMember || iconMode == .iterateBundledMember ||
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
                vm.refreshPDF()
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
