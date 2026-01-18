import SwiftUI

// MARK: - Refine Response Type

private struct RefineResponse: Codable {
    struct Refinement: Codable {
        let skillId: String
        let newName: String
    }
    let refinements: [Refinement]
}

/// Skills Bank browser showing skills grouped by category in an expandable list view.
/// Includes LLM-powered tools for deduplication and ATS synonym expansion.
struct SkillsBankBrowser: View {
    let skillStore: SkillStore?
    var llmFacade: LLMFacade?

    @State private var expandedCategories: Set<SkillCategory> = Set(SkillCategory.allCases)
    @State private var expandedSkills: Set<UUID> = []
    @State private var searchText = ""
    @State private var selectedProficiency: Proficiency?

    // Processing state
    @State private var processingService: SkillsProcessingService?
    @State private var isProcessing = false
    @State private var currentOperation: ProcessingOperation?
    @State private var processingMessage = ""
    @State private var processingProgress: Double = 0
    @State private var lastResult: SkillsProcessingResult?
    @State private var showResultAlert = false
    @State private var errorMessage: String?

    // Inline editing state
    @State private var editingSkillId: UUID?
    @State private var editingSkillName: String = ""
    @State private var editingSkillProficiency: Proficiency = .proficient

    // Refine feature state
    @State private var showRefinePopover = false
    @State private var refineInstruction = ""

    // Add skill feature state (inline)
    @State private var addingToCategory: SkillCategory?
    @State private var newSkillName = ""
    @State private var newSkillProficiency: Proficiency = .proficient
    @State private var isAddingSkill = false

    private enum ProcessingOperation {
        case deduplication
        case atsExpansion
        case refine
    }

    /// All skills from the store
    private var allSkills: [Skill] {
        skillStore?.skills ?? []
    }

    private var groupedSkills: [SkillCategory: [Skill]] {
        var skills = allSkills

        // Apply search filter
        if !searchText.isEmpty {
            let search = searchText.lowercased()
            skills = skills.filter { skill in
                skill.canonical.lowercased().contains(search) ||
                skill.atsVariants.contains { $0.lowercased().contains(search) }
            }
        }

        // Apply proficiency filter
        if let proficiency = selectedProficiency {
            skills = skills.filter { $0.proficiency == proficiency }
        }

        return Dictionary(grouping: skills, by: { $0.category })
    }

    private var sortedCategories: [SkillCategory] {
        SkillCategory.allCases.filter { groupedSkills[$0]?.isEmpty == false }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Filter bar with action buttons
                filterBar

                if skillStore == nil || allSkills.isEmpty {
                    emptyState
                } else if groupedSkills.isEmpty {
                    noMatchesState
                } else {
                    // Skills list
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(sortedCategories, id: \.self) { category in
                                categorySection(category)
                            }
                        }
                        .padding(20)
                    }
                }
            }
            .disabled(isProcessing)
            .blur(radius: isProcessing ? 2 : 0)

            // Processing overlay
            if isProcessing {
                processingOverlay
            }
        }
        .alert("Processing Complete", isPresented: $showResultAlert) {
            Button("OK") { }
        } message: {
            if let result = lastResult {
                Text("\(result.details)")
            } else if let error = errorMessage {
                Text("Error: \(error)")
            }
        }
    }

    // MARK: - Inline Add Skill

    private func startAddingSkill(to category: SkillCategory) {
        addingToCategory = category
        newSkillName = ""
        newSkillProficiency = .proficient
        // Ensure category is expanded
        expandedCategories.insert(category)
    }

    private func cancelAddingSkill() {
        addingToCategory = nil
        newSkillName = ""
        newSkillProficiency = .proficient
        isAddingSkill = false
    }

    private func commitNewSkill() {
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
                    Logger.warning("⚠️ Failed to generate ATS variants for new skill: \(error.localizedDescription)", category: .ai)
                    // Skill was still added, just without ATS variants
                }
            }

            await MainActor.run {
                cancelAddingSkill()
            }
        }
    }

    private func inlineAddSkillRow(for category: SkillCategory) -> some View {
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

    private var filterBar: some View {
        VStack(spacing: 10) {
            // Search field with action buttons
            HStack(spacing: 12) {
                // Search field
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search skills...", text: $searchText)
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                // Action buttons (only show if we have skills and facade)
                if !allSkills.isEmpty && llmFacade != nil {
                    actionButtons
                }
            }

            // Proficiency filter chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    proficiencyChip(nil, label: "All")
                    ForEach([Proficiency.expert, .proficient, .familiar], id: \.self) { level in
                        proficiencyChip(level, label: level.rawValue.capitalized)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            // Consolidate duplicates button
            Button(action: consolidateDuplicates) {
                HStack(spacing: 6) {
                    if currentOperation == .deduplication {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 12, height: 12)
                    } else {
                        Image(systemName: "arrow.triangle.merge")
                    }
                    Text("Dedupe")
                }
                .font(.caption.weight(.medium))
            }
            .buttonStyle(.bordered)
            .disabled(isProcessing)
            .help("Use AI to identify and merge duplicate skills")

            // Add ATS variants button
            Button(action: expandATSVariants) {
                HStack(spacing: 6) {
                    if currentOperation == .atsExpansion {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 12, height: 12)
                    } else {
                        Image(systemName: "text.badge.plus")
                    }
                    Text("ATS Expand")
                }
                .font(.caption.weight(.medium))
            }
            .buttonStyle(.bordered)
            .disabled(isProcessing)
            .help("Use AI to add ATS-friendly synonym variants to all skills")

            // Refine/cleanup button with popover
            Button {
                showRefinePopover = true
            } label: {
                HStack(spacing: 6) {
                    if currentOperation == .refine {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 12, height: 12)
                    } else {
                        Image(systemName: "wand.and.stars")
                    }
                    Text("Refine")
                }
                .font(.caption.weight(.medium))
            }
            .buttonStyle(.bordered)
            .disabled(isProcessing)
            .help("Use AI to refine skill names with custom instructions")
            .popover(isPresented: $showRefinePopover, arrowEdge: .bottom) {
                refinePopoverContent
            }
        }
    }

    private var refinePopoverContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Refine Skill Names")
                    .font(.headline)

                Text("Enter instructions for how skill names should be refined.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Instructions")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("e.g., Limit to 3 words or fewer", text: $refineInstruction, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(Color(.textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.quaternary, lineWidth: 1)
                    )
                    .lineLimit(3...5)
            }

            Text("Examples: \"Use industry-standard abbreviations\", \"Remove vendor names\", \"Capitalize consistently\"")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            HStack {
                Button("Cancel") {
                    showRefinePopover = false
                    refineInstruction = ""
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Refine All Skills") {
                    showRefinePopover = false
                    refineSkills()
                }
                .buttonStyle(.borderedProminent)
                .disabled(refineInstruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 340)
    }

    private var processingOverlay: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)

            Text(processingMessage)
                .font(.headline)

            if processingProgress > 0 {
                ProgressView(value: processingProgress)
                    .frame(width: 200)
            }
        }
        .padding(32)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Processing Actions

    private func consolidateDuplicates() {
        guard let skillStore = skillStore, let facade = llmFacade else { return }

        isProcessing = true
        currentOperation = .deduplication
        processingMessage = "Analyzing skills for duplicates..."
        processingProgress = 0

        Task {
            do {
                let service = SkillsProcessingService(skillStore: skillStore, facade: facade)
                processingService = service

                // Monitor progress
                let progressTask = Task {
                    while !Task.isCancelled {
                        await MainActor.run {
                            if case .processing(let msg) = service.status {
                                processingMessage = msg
                            }
                            processingProgress = service.progress
                        }
                        try? await Task.sleep(for: .milliseconds(100))
                    }
                }

                let result = try await service.consolidateDuplicates()
                progressTask.cancel()

                await MainActor.run {
                    lastResult = result
                    isProcessing = false
                    currentOperation = nil
                    showResultAlert = true
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isProcessing = false
                    currentOperation = nil
                    showResultAlert = true
                }
            }
        }
    }

    private func expandATSVariants() {
        guard let skillStore = skillStore, let facade = llmFacade else { return }

        isProcessing = true
        currentOperation = .atsExpansion
        processingMessage = "Generating ATS synonyms..."
        processingProgress = 0

        Task {
            do {
                let service = SkillsProcessingService(skillStore: skillStore, facade: facade)
                processingService = service

                // Monitor progress
                let progressTask = Task {
                    while !Task.isCancelled {
                        await MainActor.run {
                            if case .processing(let msg) = service.status {
                                processingMessage = msg
                            }
                            processingProgress = service.progress
                        }
                        try? await Task.sleep(for: .milliseconds(100))
                    }
                }

                let result = try await service.expandATSSynonyms()
                progressTask.cancel()

                await MainActor.run {
                    lastResult = result
                    isProcessing = false
                    currentOperation = nil
                    showResultAlert = true
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isProcessing = false
                    currentOperation = nil
                    showResultAlert = true
                }
            }
        }
    }

    private func refineSkills() {
        guard let skillStore = skillStore, let facade = llmFacade else { return }
        let instruction = refineInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty else { return }

        isProcessing = true
        currentOperation = .refine
        processingMessage = "Refining skill names..."
        processingProgress = 0

        Task {
            do {
                let allSkills = skillStore.skills
                let totalSkills = allSkills.count

                // Build the prompt with all skills
                let skillList = allSkills.enumerated().map { index, skill in
                    "\(index + 1). \(skill.id.uuidString): \(skill.canonical)"
                }.joined(separator: "\n")

                let prompt = """
                    You are a professional resume skills editor. Refine the following skill names according to this instruction:

                    **Instruction:** \(instruction)

                    **Skills to refine:**
                    \(skillList)

                    For each skill, provide the refined name. If a skill name already meets the criteria, keep it unchanged.

                    Return a JSON object with a "refinements" array containing objects with "skillId" and "newName" fields.
                    Only include skills whose names should change.
                    """

                let schema: [String: Any] = [
                    "type": "object",
                    "properties": [
                        "refinements": [
                            "type": "array",
                            "items": [
                                "type": "object",
                                "properties": [
                                    "skillId": ["type": "string"],
                                    "newName": ["type": "string"]
                                ],
                                "required": ["skillId", "newName"]
                            ]
                        ]
                    ],
                    "required": ["refinements"]
                ]

                guard let modelId = UserDefaults.standard.string(forKey: "skillsProcessingModelId"), !modelId.isEmpty else {
                    throw SkillsProcessingError.llmNotConfigured
                }

                processingMessage = "AI is refining \(totalSkills) skills..."

                let response: RefineResponse = try await facade.executeStructuredWithDictionarySchema(
                    prompt: prompt,
                    modelId: modelId,
                    as: RefineResponse.self,
                    schema: schema,
                    schemaName: "skill_refinements",
                    backend: .gemini,
                    thinkingLevel: "low"  // Use low thinking for simple transformations to reduce token usage
                )

                // Apply refinements
                var modifiedCount = 0
                for refinement in response.refinements {
                    if let skillUUID = UUID(uuidString: refinement.skillId),
                       let skill = skillStore.skill(withId: skillUUID) {
                        let newName = refinement.newName.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !newName.isEmpty && newName != skill.canonical {
                            skill.canonical = newName
                            skillStore.update(skill)
                            modifiedCount += 1
                        }
                    }
                }

                await MainActor.run {
                    lastResult = SkillsProcessingResult(
                        operation: "Refine",
                        skillsProcessed: totalSkills,
                        skillsModified: modifiedCount,
                        details: "Refined \(modifiedCount) of \(totalSkills) skill names"
                    )
                    isProcessing = false
                    currentOperation = nil
                    refineInstruction = ""
                    showResultAlert = true
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isProcessing = false
                    currentOperation = nil
                    showResultAlert = true
                }
            }
        }
    }

    // MARK: - Inline Editing

    private func startEditing(_ skill: Skill) {
        editingSkillId = skill.id
        editingSkillName = skill.canonical
        editingSkillProficiency = skill.proficiency
    }

    private func commitEdit() {
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
        if didChange {
            skillStore?.update(skill)
        }

        cancelEdit()
    }

    private func deleteEditingSkill() {
        guard let skillId = editingSkillId,
              let skill = skillStore?.skill(withId: skillId) else {
            cancelEdit()
            return
        }
        skillStore?.delete(skill)
        cancelEdit()
    }

    private func cancelEdit() {
        editingSkillId = nil
        editingSkillName = ""
    }

    // MARK: - Existing UI Components

    private func proficiencyChip(_ proficiency: Proficiency?, label: String) -> some View {
        let isSelected = selectedProficiency == proficiency
        let count: Int
        if let proficiency = proficiency {
            count = allSkills.filter { $0.proficiency == proficiency }.count
        } else {
            count = allSkills.count
        }

        return Button(action: { selectedProficiency = proficiency }) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.caption.weight(isSelected ? .semibold : .regular))
                if count > 0 {
                    Text("\(count)")
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(isSelected ? Color.white.opacity(0.2) : Color.secondary.opacity(0.15)))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? Color.orange : Color(nsColor: .controlBackgroundColor))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func categorySection(_ category: SkillCategory) -> some View {
        let skills = groupedSkills[category] ?? []
        let isExpanded = expandedCategories.contains(category)

        return VStack(alignment: .leading, spacing: 0) {
            // Category header
            HStack(spacing: 0) {
                Button(action: { toggleCategory(category) }) {
                    HStack {
                        Image(systemName: iconFor(category))
                            .font(.title3)
                            .foregroundStyle(colorFor(category))
                            .frame(width: 24)

                        Text(category.rawValue)
                            .font(.headline)

                        Text("(\(skills.count))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)

                // Add skill button
                Button {
                    startAddingSkill(to: category)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(colorFor(category))
                }
                .buttonStyle(.plain)
                .help("Add skill to \(category.rawValue)")
                .padding(.trailing, 4)
                .disabled(addingToCategory != nil)
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))

            // Skills list (when expanded)
            if isExpanded {
                VStack(spacing: 1) {
                    ForEach(skills.sorted { $0.proficiency.sortOrder < $1.proficiency.sortOrder }) { skill in
                        skillRow(skill)
                    }

                    // Inline add row when adding to this category
                    if addingToCategory == category {
                        inlineAddSkillRow(for: category)
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

    private func skillRow(_ skill: Skill) -> some View {
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
                }

                VStack(alignment: .leading, spacing: 4) {
                    // Skill name with proficiency dot - editable
                    HStack(spacing: 6) {
                        if hasVariants {
                            // Use editing value when editing this skill
                            Circle()
                                .fill(colorFor(editingSkillId == skill.id ? editingSkillProficiency : skill.proficiency))
                                .frame(width: 8, height: 8)
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

                // Proficiency badge
                Text(skill.proficiency.rawValue.capitalized)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(colorFor(skill.proficiency).opacity(0.15))
                    .foregroundStyle(colorFor(skill.proficiency))
                    .clipShape(Capsule())
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

                    FlowLayout(spacing: 6) {
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

    private func toggleCategory(_ category: SkillCategory) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if expandedCategories.contains(category) {
                expandedCategories.remove(category)
            } else {
                expandedCategories.insert(category)
            }
        }
    }

    private func iconFor(_ category: SkillCategory) -> String {
        switch category {
        case .languages: return "chevron.left.forwardslash.chevron.right"
        case .frameworks: return "square.stack.3d.up"
        case .tools: return "wrench.and.screwdriver"
        case .hardware: return "cpu"
        case .fabrication: return "hammer"
        case .scientific: return "flask"
        case .soft: return "person.2"
        case .domain: return "building.2"
        }
    }

    private func colorFor(_ category: SkillCategory) -> Color {
        switch category {
        case .languages: return .blue
        case .frameworks: return .purple
        case .tools: return .orange
        case .hardware: return .red
        case .fabrication: return .brown
        case .scientific: return .green
        case .soft: return .teal
        case .domain: return .indigo
        }
    }

    private func colorFor(_ proficiency: Proficiency) -> Color {
        switch proficiency {
        case .expert: return .green
        case .proficient: return .blue
        case .familiar: return .orange
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "star.slash")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("No Skills Bank")
                .font(.title3.weight(.medium))
            Text("Complete document ingestion to build your skills bank")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noMatchesState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text("No Matching Skills")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Try adjusting your search or filters")
                .font(.callout)
                .foregroundStyle(.tertiary)
            Button("Clear Filters") {
                searchText = ""
                selectedProficiency = nil
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Flow Layout for ATS Variant Tags

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        return layout(sizes: sizes, containerWidth: proposal.width ?? .infinity).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let offsets = layout(sizes: sizes, containerWidth: bounds.width).offsets

        for (subview, offset) in zip(subviews, offsets) {
            subview.place(at: CGPoint(x: bounds.minX + offset.x, y: bounds.minY + offset.y), proposal: .unspecified)
        }
    }

    private func layout(sizes: [CGSize], containerWidth: CGFloat) -> (offsets: [CGPoint], size: CGSize) {
        var offsets: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxWidth: CGFloat = 0

        for size in sizes {
            if currentX + size.width > containerWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            offsets.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            maxWidth = max(maxWidth, currentX)
        }

        return (offsets, CGSize(width: maxWidth, height: currentY + lineHeight))
    }
}
