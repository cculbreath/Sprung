import SwiftUI

/// A single skill row in the Skills Bank browser.
///
/// Owns its own inline-editing state (name field, category picker, delete) since
/// only one row edits at a time and that state is naturally local to the row.
/// The expandable ATS-variants section is driven by `isExpanded`/`onToggleExpand`
/// supplied by the parent, which owns the cross-row expansion set.
struct SkillBankRowView: View {
    let skill: Skill
    let sortedCategories: [String]
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    /// Persist the edited name/category. Receives the resolved category (custom
    /// categories already resolved) so the parent can expand it. Returns nothing.
    let onCommitEdit: (_ newName: String, _ newCategory: String) -> Void
    let onDelete: () -> Void

    // Inline editing state — local to the row that is currently being edited.
    @State private var isEditing = false
    @State private var editingName: String = ""
    @State private var editingCategory: String = ""
    @State private var editingCustomCategory: String = ""

    private var hasVariants: Bool { !skill.atsVariants.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main skill row
            HStack(alignment: .top, spacing: 12) {
                // Expand/collapse indicator (only if has variants)
                if hasVariants {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 10)
                        .padding(.top, 6)
                }

                VStack(alignment: .leading, spacing: 4) {
                    // Skill name - editable
                    HStack(spacing: 6) {
                        if isEditing {
                            // Inline editing mode
                            VStack(alignment: .leading, spacing: 6) {
                                // Name field with action buttons
                                HStack(spacing: 6) {
                                    TextField("Skill name", text: $editingName)
                                        .font(.subheadline.weight(.medium))
                                        .textFieldStyle(.plain)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color(.textBackgroundColor))
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 4)
                                                .stroke(Color.accentColor, lineWidth: 1)
                                        )
                                        .onSubmit {
                                            commitEdit()
                                        }

                                    Button {
                                        commitEdit()
                                    } label: {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                    }
                                    .buttonStyle(.plain)

                                    Button {
                                        cancelEdit()
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)

                                    Spacer()

                                    // Delete button
                                    Button {
                                        deleteSkill()
                                    } label: {
                                        Image(systemName: "trash")
                                            .foregroundStyle(.red)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Delete skill")
                                }

                                // Category picker
                                HStack(spacing: 8) {
                                    Text("Category:")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    Picker("", selection: $editingCategory) {
                                        ForEach(sortedCategories, id: \.self) { cat in
                                            Text(cat).tag(cat)
                                        }
                                        Divider()
                                        Text("New Category...").tag("__custom__")
                                    }
                                    .controlSize(.small)
                                    .frame(maxWidth: 200)

                                    if editingCategory == "__custom__" {
                                        TextField("Category name", text: $editingCustomCategory)
                                            .font(.caption)
                                            .textFieldStyle(.plain)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color(.textBackgroundColor))
                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 4)
                                                    .stroke(Color.accentColor, lineWidth: 1)
                                            )
                                            .frame(maxWidth: 160)
                                    }
                                }
                            }
                        } else {
                            // Display mode - double-click to edit
                            Text(skill.canonical)
                                .font(.subheadline.weight(.medium))
                                .onTapGesture(count: 2) {
                                    startEditing()
                                }

                            if skill.isPending {
                                Text("Pending")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.orange)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.12))
                                    .clipShape(Capsule())
                                    .help("Created during onboarding but never approved — use Approve Pending above")
                            }

                            // Edit button on hover
                            Button {
                                startEditing()
                            } label: {
                                Image(systemName: "pencil")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .opacity(0.5)
                        }
                    }

                    // ATS variants preview (collapsed) or count indicator
                    if hasVariants && !isExpanded {
                        Text("\(skill.atsVariants.count) ATS synonym\(skill.atsVariants.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // Evidence count
                    if !skill.evidence.isEmpty {
                        Label("\(skill.evidence.count) evidence", systemImage: "doc.text")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                // Last used
                if let lastUsed = skill.lastUsed {
                    Text(lastUsed)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .onTapGesture {
                // Only expand/collapse if not editing and has variants
                if !isEditing && hasVariants {
                    onToggleExpand()
                }
            }

            // Expanded ATS variants section
            if isExpanded && hasVariants {
                VStack(alignment: .leading, spacing: 8) {
                    Text("ATS Synonyms")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    FlowStack(spacing: 6) {
                        ForEach(skill.atsVariants, id: \.self) { variant in
                            Text(variant)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.accentColor.opacity(0.1))
                                .foregroundStyle(Color.accentColor)
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .padding(.leading, 22)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Inline Editing

    private func startEditing() {
        editingName = skill.canonical
        editingCategory = skill.category
        editingCustomCategory = ""
        isEditing = true
    }

    private func commitEdit() {
        let newName = editingName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedCategory = editingCategory == "__custom__"
            ? editingCustomCategory.trimmingCharacters(in: .whitespacesAndNewlines)
            : editingCategory
        onCommitEdit(newName, resolvedCategory)
        cancelEdit()
    }

    private func deleteSkill() {
        onDelete()
        cancelEdit()
    }

    private func cancelEdit() {
        isEditing = false
        editingName = ""
        editingCategory = ""
        editingCustomCategory = ""
    }
}
