import SwiftUI

// MARK: - Category Section & Skill Row Views + CRUD Helpers

extension SkillsBankBrowser {

    // MARK: - Inline Add Skill

    func startAddingSkill(to category: String) {
        addingToCategory = category
        newSkillName = ""
        newSkillProficiency = .proficient
        // Ensure category is expanded
        expandedCategories.insert(category)
    }

    func cancelAddingSkill() {
        addingToCategory = nil
        newSkillName = ""
        newSkillProficiency = .proficient
        isAddingSkill = false
    }

    func commitNewSkill() {
        guard let skillStore = skillStore,
              let category = addingToCategory else { return }
        let trimmedName = newSkillName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        isAddingSkill = true

        Task {
            // Create the skill first
            let newSkill = Skill(
                canonical: trimmedName,
                category: category,
                proficiency: newSkillProficiency
            )
            skillStore.add(newSkill)

            // Generate ATS variants if we have the facade
            if let facade = llmFacade {
                do {
                    let service = SkillsProcessingService(skillStore: skillStore, facade: facade)
                    let variants = try await service.generateATSVariantsForSkill(newSkill)
                    newSkill.atsVariants = variants
                    skillStore.update(newSkill)
                } catch {
                    Logger.warning("Failed to generate ATS variants for new skill: \(error.localizedDescription)", category: .ai)
                    // Skill was still added, just without ATS variants
                }
            }

            await MainActor.run {
                cancelAddingSkill()
            }
        }
    }

    func inlineAddSkillRow(for category: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            // Status indicator
            if isAddingSkill {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 10)
            } else {
                Circle()
                    .fill(colorFor(newSkillProficiency))
                    .frame(width: 8, height: 8)
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
                                commitNewSkill()
                            }
                        }
                        .disabled(isAddingSkill)

                    // Save button
                    Button {
                        commitNewSkill()
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    .buttonStyle(.plain)
                    .disabled(newSkillName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAddingSkill)

                    // Cancel button
                    Button {
                        cancelAddingSkill()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(isAddingSkill)
                }

                // Proficiency picker
                HStack(spacing: 8) {
                    Text("Proficiency:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("", selection: $newSkillProficiency) {
                        Text("Expert").tag(Proficiency.expert)
                        Text("Proficient").tag(Proficiency.proficient)
                        Text("Familiar").tag(Proficiency.familiar)
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .frame(maxWidth: 200)
                    .disabled(isAddingSkill)

                    if isAddingSkill {
                        Text("Generating ATS synonyms...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.accentColor.opacity(0.05))
    }

    // MARK: - New Category Creation

    var newCategoryRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder.badge.plus")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            TextField("Category name...", text: $newCategoryName)
                .font(.subheadline.weight(.medium))
                .textFieldStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.accentColor, lineWidth: 1)
                )
                .onSubmit { commitNewCategory() }

            Button {
                commitNewCategory()
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            .buttonStyle(.plain)
            .disabled(newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button {
                isCreatingCategory = false
                newCategoryName = ""
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    func commitNewCategory() {
        let trimmed = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isCreatingCategory = false
        newCategoryName = ""
        expandedCategories.insert(trimmed)
        startAddingSkill(to: trimmed)
    }

    // MARK: - Inline Editing

    func startEditing(_ skill: Skill) {
        editingSkillId = skill.id
        editingSkillName = skill.canonical
        editingSkillProficiency = skill.proficiency
        editingSkillCategory = skill.category
        editingSkillCustomCategory = ""
    }

    func commitEdit() {
        guard let skillId = editingSkillId,
              let skill = skillStore?.skill(withId: skillId) else {
            cancelEdit()
            return
        }

        var didChange = false
        let newName = editingSkillName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !newName.isEmpty && newName != skill.canonical {
            skill.canonical = newName
            didChange = true
        }
        if skill.proficiency != editingSkillProficiency {
            skill.proficiency = editingSkillProficiency
            didChange = true
        }
        let resolvedCategory = editingSkillCategory == "__custom__"
            ? editingSkillCustomCategory.trimmingCharacters(in: .whitespacesAndNewlines)
            : editingSkillCategory
        if !resolvedCategory.isEmpty && resolvedCategory != skill.category {
            skill.category = resolvedCategory
            expandedCategories.insert(resolvedCategory)
            didChange = true
        }
        if didChange {
            skillStore?.update(skill)
        }

        cancelEdit()
    }

    func deleteEditingSkill() {
        guard let skillId = editingSkillId,
              let skill = skillStore?.skill(withId: skillId) else {
            cancelEdit()
            return
        }
        skillStore?.delete(skill)
        cancelEdit()
    }

    func cancelEdit() {
        editingSkillId = nil
        editingSkillName = ""
        editingSkillCategory = ""
        editingSkillCustomCategory = ""
    }

    // MARK: - Category Section

    func categorySection(_ category: String) -> some View {
        let skills = groupedSkills[category] ?? []
        let isExpanded = expandedCategories.contains(category)

        return VStack(alignment: .leading, spacing: 0) {
            // Category header
            HStack(spacing: 0) {
                Button(action: { toggleCategory(category) }) {
                    HStack {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 16)

                        Image(systemName: SkillCategoryUtils.icon(for: category))
                            .font(.title3)
                            .foregroundStyle(colorForCategory(category))
                            .frame(width: 24)

                        if renamingCategory == category {
                            TextField("Category name", text: $renamingCategoryText)
                                .textFieldStyle(.plain)
                                .font(.headline)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color(.textBackgroundColor), in: RoundedRectangle(cornerRadius: 4))
                                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1))
                                .onSubmit { commitCategoryRename(from: category) }
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
                    startAddingSkill(to: category)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(colorForCategory(category))
                }
                .buttonStyle(.plain)
                .help("Add skill to \(category)")
                .padding(.trailing, 4)
                .disabled(addingToCategory != nil)
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
            .contextMenu {
                Button("Rename") {
                    print("[SkillsBankBrowser] Rename triggered for category: \(category)")
                    renamingCategoryText = category
                    renamingCategory = category
                }
            }

            // Skills list (when expanded)
            if isExpanded {
                VStack(spacing: 1) {
                    // Inline add row when adding to this category
                    if addingToCategory == category {
                        inlineAddSkillRow(for: category)
                    }

                    ForEach(skills.sorted { a, b in
                        if !sortFrozenOrder.isEmpty {
                            return (sortFrozenOrder[a.id] ?? Int.max) < (sortFrozenOrder[b.id] ?? Int.max)
                        }
                        return a.proficiency.sortOrder < b.proficiency.sortOrder
                    }) { skill in
                        skillRow(skill)
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

    // MARK: - Skill Row

    func skillRow(_ skill: Skill) -> some View {
        let isExpanded = expandedSkills.contains(skill.id)
        let hasVariants = !skill.atsVariants.isEmpty

        return VStack(alignment: .leading, spacing: 0) {
            // Main skill row
            HStack(alignment: .top, spacing: 12) {
                // Expand/collapse indicator (only if has variants)
                if hasVariants {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 10)
                        .padding(.top, 6)
                } else {
                    // Proficiency indicator when no variants (use editing value when editing)
                    Circle()
                        .fill(colorFor(editingSkillId == skill.id ? editingSkillProficiency : skill.proficiency))
                        .frame(width: 8, height: 8)
                        .padding(.top, 6)
                        .onTapGesture {
                            cycleProficiency(skill)
                        }
                }

                VStack(alignment: .leading, spacing: 4) {
                    // Skill name with proficiency dot - editable
                    HStack(spacing: 6) {
                        if hasVariants {
                            // Use editing value when editing this skill
                            Circle()
                                .fill(colorFor(editingSkillId == skill.id ? editingSkillProficiency : skill.proficiency))
                                .frame(width: 8, height: 8)
                                .onTapGesture {
                                    cycleProficiency(skill)
                                }
                        }

                        if editingSkillId == skill.id {
                            // Inline editing mode
                            VStack(alignment: .leading, spacing: 6) {
                                // Name field with action buttons
                                HStack(spacing: 6) {
                                    TextField("Skill name", text: $editingSkillName)
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
                                        deleteEditingSkill()
                                    } label: {
                                        Image(systemName: "trash")
                                            .foregroundStyle(.red)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Delete skill")
                                }

                                // Proficiency picker
                                HStack(spacing: 8) {
                                    Text("Proficiency:")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    Picker("", selection: $editingSkillProficiency) {
                                        Text("Expert").tag(Proficiency.expert)
                                        Text("Proficient").tag(Proficiency.proficient)
                                        Text("Familiar").tag(Proficiency.familiar)
                                    }
                                    .pickerStyle(.segmented)
                                    .controlSize(.small)
                                    .frame(maxWidth: 200)
                                }

                                // Category picker
                                HStack(spacing: 8) {
                                    Text("Category:")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    Picker("", selection: $editingSkillCategory) {
                                        ForEach(sortedCategories, id: \.self) { cat in
                                            Text(cat).tag(cat)
                                        }
                                        Divider()
                                        Text("New Category...").tag("__custom__")
                                    }
                                    .controlSize(.small)
                                    .frame(maxWidth: 200)

                                    if editingSkillCategory == "__custom__" {
                                        TextField("Category name", text: $editingSkillCustomCategory)
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
                                    startEditing(skill)
                                }

                            // Edit button on hover
                            Button {
                                startEditing(skill)
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

                // Proficiency badge - click to cycle
                Text(skill.proficiency.rawValue.capitalized)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(colorFor(skill.proficiency).opacity(0.15))
                    .foregroundStyle(colorFor(skill.proficiency))
                    .clipShape(Capsule())
                    .onTapGesture {
                        cycleProficiency(skill)
                    }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .onTapGesture {
                // Only expand/collapse if not editing and has variants
                if editingSkillId != skill.id && hasVariants {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if isExpanded {
                            expandedSkills.remove(skill.id)
                        } else {
                            expandedSkills.insert(skill.id)
                        }
                    }
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

    // MARK: - UI Interaction Helpers

    func cycleProficiency(_ skill: Skill) {
        // Freeze current sort order before changing proficiency
        if sortFrozenOrder.isEmpty {
            let allSkills = groupedSkills.values.flatMap { $0 }
            let sorted = allSkills.sorted { $0.proficiency.sortOrder < $1.proficiency.sortOrder }
            sortFrozenOrder = Dictionary(uniqueKeysWithValues: sorted.enumerated().map { ($1.id, $0) })
        }

        switch skill.proficiency {
        case .familiar: skill.proficiency = .proficient
        case .proficient: skill.proficiency = .expert
        case .expert: skill.proficiency = .familiar
        }
        skillStore?.update(skill)

        // Reset debounce timer
        sortUnfreezeTask?.cancel()
        sortUnfreezeTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.35)) {
                sortFrozenOrder = [:]
            }
        }
    }

    func toggleCategory(_ category: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if expandedCategories.contains(category) {
                expandedCategories.remove(category)
            } else {
                expandedCategories.insert(category)
            }
        }
    }

    func commitCategoryRename(from oldCategory: String) {
        let trimmed = renamingCategoryText.trimmingCharacters(in: .whitespacesAndNewlines)
        print("[SkillsBankBrowser] commitCategoryRename called: '\(oldCategory)' -> '\(trimmed)'")
        guard !trimmed.isEmpty, trimmed != oldCategory, let store = skillStore else {
            print("[SkillsBankBrowser] commitCategoryRename: guard failed (empty=\(trimmed.isEmpty), same=\(trimmed == oldCategory), store=\(skillStore != nil))")
            renamingCategory = nil
            return
        }

        let skillsToUpdate = store.skills.filter { $0.category == oldCategory }
        print("[SkillsBankBrowser] Renaming \(skillsToUpdate.count) skills from '\(oldCategory)' to '\(trimmed)'")
        guard let first = skillsToUpdate.first else {
            print("[SkillsBankBrowser] No skills found for category '\(oldCategory)'")
            renamingCategory = nil
            return
        }
        for skill in skillsToUpdate {
            skill.category = trimmed
        }
        store.update(first) // saveContext persists all mutations, changeVersion triggers UI refresh

        // Update expanded state to track the new name
        if expandedCategories.remove(oldCategory) != nil {
            expandedCategories.insert(trimmed)
        }

        renamingCategory = nil
    }

    /// Stable color for a category based on hash of its name.
    func colorForCategory(_ category: String) -> Color {
        let knownColors: [String: Color] = [
            "Programming Languages": .blue,
            "Frameworks & Libraries": .purple,
            "Tools & Platforms": .orange,
            "Tools & Software": .orange,
            "Hardware & Electronics": .red,
            "Fabrication & Manufacturing": .brown,
            "Scientific & Analysis": .green,
            "Methodologies & Processes": .cyan,
            "Writing & Communication": .mint,
            "Communication & Writing": .mint,
            "Research Methods": .pink,
            "Regulatory & Compliance": .gray,
            "Leadership & Management": .teal,
            "Domain Expertise": .indigo,
        ]
        if let known = knownColors[category] { return known }
        // Stable color based on hash for unknown categories
        let palette: [Color] = [.blue, .purple, .orange, .red, .green, .cyan, .mint, .pink, .teal, .indigo]
        let index = abs(category.hashValue) % palette.count
        return palette[index]
    }

    func colorFor(_ proficiency: Proficiency) -> Color {
        switch proficiency {
        case .expert: return .blue
        case .proficient: return .green
        case .familiar: return .orange
        }
    }
}
