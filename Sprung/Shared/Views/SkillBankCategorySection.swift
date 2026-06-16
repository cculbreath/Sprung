import SwiftUI

/// A category group in the Skills Bank browser: the category header (with inline
/// rename + add-skill controls), an optional inline add-skill row, and the list of
/// `SkillBankRowView`s for the category's skills.
///
/// Expansion, rename, and add-skill state are owned by the parent browser (they are
/// shared/cross-cutting concerns) and threaded in via bindings + callbacks.
struct SkillBankCategorySection: View {
    let category: String
    let skills: [Skill]
    let isExpanded: Bool
    let sortedCategories: [String]

    // Category rename (shared parent state — only one category renames at a time).
    @Binding var renamingCategory: String?
    @Binding var renamingCategoryText: String
    let onCommitRename: () -> Void

    // Inline add-skill (shared parent state — only one add at a time across browser).
    let isAddingToThisCategory: Bool
    let isAddDisabled: Bool
    let isAddingSkill: Bool
    @Binding var newSkillName: String
    let onStartAddingSkill: () -> Void
    let onCommitNewSkill: () -> Void
    let onCancelAddingSkill: () -> Void

    let onToggleCategory: () -> Void

    // Per-skill row callbacks (forwarded to each SkillBankRowView).
    let isSkillExpanded: (Skill) -> Bool
    let onToggleSkillExpand: (Skill) -> Void
    let onCommitSkillEdit: (Skill, _ newName: String, _ newCategory: String) -> Void
    let onDeleteSkill: (Skill) -> Void

    private var color: Color { SkillCategoryColor.color(for: category) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            // Skills list (when expanded)
            if isExpanded {
                VStack(spacing: 1) {
                    // Inline add row when adding to this category
                    if isAddingToThisCategory {
                        inlineAddSkillRow
                    }

                    ForEach(skills.sorted { a, b in
                        a.canonical.localizedCaseInsensitiveCompare(b.canonical) == .orderedAscending
                    }) { skill in
                        SkillBankRowView(
                            skill: skill,
                            sortedCategories: sortedCategories,
                            isExpanded: isSkillExpanded(skill),
                            onToggleExpand: { onToggleSkillExpand(skill) },
                            onCommitEdit: { newName, newCategory in
                                onCommitSkillEdit(skill, newName, newCategory)
                            },
                            onDelete: { onDeleteSkill(skill) }
                        )
                    }
                }
                .padding(.leading, 36)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 0) {
            Button(action: onToggleCategory) {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 16)

                    Image(systemName: SkillCategoryUtils.icon(for: category))
                        .font(.title3)
                        .foregroundStyle(color)
                        .frame(width: 24)

                    if renamingCategory == category {
                        TextField("Category name", text: $renamingCategoryText)
                            .textFieldStyle(.plain)
                            .font(.headline)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color(.textBackgroundColor), in: RoundedRectangle(cornerRadius: 4))
                            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1))
                            .onSubmit { onCommitRename() }
                            .onExitCommand { renamingCategory = nil }
                    } else {
                        Text(category)
                            .font(.headline)
                    }

                    Text("(\(skills.count))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer()
                }
            }
            .buttonStyle(.plain)

            // Add skill button
            Button {
                onStartAddingSkill()
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(color)
            }
            .buttonStyle(.plain)
            .help("Add skill to \(category)")
            .padding(.trailing, 4)
            .disabled(isAddDisabled)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .contextMenu {
            Button("Rename") {
                Logger.debug("[SkillsBankBrowser] Rename triggered for category: \(category)", category: .ui)
                renamingCategoryText = category
                renamingCategory = category
            }
        }
    }

    // MARK: - Inline Add Skill Row

    private var inlineAddSkillRow: some View {
        HStack(alignment: .center, spacing: 12) {
            // Status indicator
            if isAddingSkill {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 10)
            }

            VStack(alignment: .leading, spacing: 6) {
                // Skill name field
                HStack(spacing: 6) {
                    TextField("New skill name...", text: $newSkillName)
                        .font(.subheadline.weight(.medium))
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(Color(.textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.accentColor, lineWidth: 1)
                        )
                        .onSubmit {
                            if !newSkillName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                onCommitNewSkill()
                            }
                        }
                        .disabled(isAddingSkill)

                    // Save button
                    Button {
                        onCommitNewSkill()
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    .buttonStyle(.plain)
                    .disabled(newSkillName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAddingSkill)

                    // Cancel button
                    Button {
                        onCancelAddingSkill()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(isAddingSkill)
                }

                if isAddingSkill {
                    Text("Generating ATS synonyms...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.accentColor.opacity(0.05))
    }
}
