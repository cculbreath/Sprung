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

    @Environment(ArtifactRecordStore.self) private var artifactRecordStore

    @State private var expandedCategories: Set<String> = []
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

    // Curation state
    @State private var showCurationReview = false
    @State private var curationPlan: SkillCurationPlan?
    @State private var isCurating = false

    // Inline editing state
    @State private var editingSkillId: UUID?
    @State private var editingSkillName: String = ""
    @State private var editingSkillProficiency: Proficiency = .proficient
    @State private var editingSkillCategory: String = ""
    @State private var editingSkillCustomCategory: String = ""

    // Refine feature state
    @State private var showRefinePopover = false
    @State private var refineInstruction = ""

    // Sort debounce after proficiency cycling
    @State private var sortFrozenOrder: [UUID: Int] = [:]
    @State private var sortUnfreezeTask: Task<Void, Never>?

    // Add skill feature state (inline)
    @State private var addingToCategory: String?
    @State private var newSkillName = ""
    @State private var newSkillProficiency: Proficiency = .proficient
    @State private var isAddingSkill = false

    // New category creation state
    @State private var isCreatingCategory = false
    @State private var newCategoryName = ""

    // Category rename state
    @State private var renamingCategory: String?
    @State private var renamingCategoryText = ""

    // Extraction state
    @State private var showExtractionSheet = false

    private enum ProcessingOperation {
        case deduplication
        case atsExpansion
        case refine
        case curation
        case extraction
    }

    /// All skills from the store
    private var allSkills: [Skill] {
        skillStore?.skills ?? []
    }

    private var groupedSkills: [String: [Skill]] {
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

    private var sortedCategories: [String] {
        var categories = Set(groupedSkills.keys)
        // Include the new category being added to (even if empty)
        if let adding = addingToCategory {
            categories.insert(adding)
        }
        return categories.sorted()
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

                            // New category creation
                            if isCreatingCategory {
                                newCategoryRow
                            } else {
                                Button {
                                    isCreatingCategory = true
                                    newCategoryName = ""
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "plus.circle")
                                            .font(.caption)
                                        Text("New Category")
                                            .font(.caption.weight(.medium))
                                    }
                                    .foregroundStyle(.secondary)
                                    .padding(.vertical, 4)
                                }
                                .buttonStyle(.plain)
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
        .onAppear {
            // Expand all categories by default
            expandedCategories = Set(sortedCategories)
        }
        .onChange(of: allSkills.count) {
            // Keep expanding new categories as they appear
            expandedCategories.formUnion(sortedCategories)
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
        .sheet(isPresented: $showCurationReview) {
            if let plan = curationPlan, let store = skillStore, let facade = llmFacade {
                SkillCurationReviewView(plan: plan, skillStore: store, llmFacade: facade) {
                    showCurationReview = false
                    curationPlan = nil
                }
            }
        }
        .sheet(isPresented: $showExtractionSheet) {
            if let store = skillStore, let facade = llmFacade {
                SkillExtractionSheet(
                    skillStore: store,
                    llmFacade: facade,
                    artifactRecordStore: artifactRecordStore,
                    onComplete: { extractedCount, ranPostProcessing, extractionCurationPlan in
                        lastResult = SkillsProcessingResult(
                            operation: "Extraction",
                            skillsProcessed: extractedCount,
                            skillsModified: extractedCount,
                            details: "Extracted \(extractedCount) skills from artifacts\(ranPostProcessing ? " (with post-processing)" : "")"
                        )
                        showResultAlert = true
                        if let plan = extractionCurationPlan {
                            curationPlan = plan
                            showCurationReview = true
                        }
                    }
                )
            }
        }
    }

    // MARK: - Inline Add Skill

    private func startAddingSkill(to category: String) {
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

    private func inlineAddSkillRow(for category: String) -> some View {
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

                // Action buttons (show if we have facade; Extract always visible)
                if llmFacade != nil {
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
            // Extract from artifacts button (always visible)
            Button(action: { showExtractionSheet = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text.magnifyingglass")
                    Text("Extract")
                }
                .font(.caption.weight(.medium))
            }
            .buttonStyle(.bordered)
            .disabled(isProcessing)
            .help("Extract skills from archived documents. Select artifacts and run AI-powered skill extraction.")

            // Processing buttons (only when skills exist)
            if !allSkills.isEmpty {

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
            .help("Find and merge semantically equivalent skills (e.g., \"JavaScript\" and \"Javascript\"). Applies changes immediately.")

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
            .help("Generate ATS-friendly synonyms for each skill (e.g., \"JavaScript\" → JS, ECMAScript). Synonyms are included in resumes to improve keyword matching.")

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
            .help("Rename skills using your own instructions (e.g., \"Limit to 3 words\", \"Use industry abbreviations\"). Opens a prompt where you describe the changes.")
            .popover(isPresented: $showRefinePopover, arrowEdge: .bottom) {
                refinePopoverContent
            }

            // Curate Skills button
            Button(action: curateSkills) {
                HStack(spacing: 6) {
                    if currentOperation == .curation {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 12, height: 12)
                    } else {
                        Image(systemName: "slider.horizontal.3")
                    }
                    Text("Curate")
                }
                .font(.caption.weight(.medium))
            }
            .buttonStyle(.bordered)
            .disabled(isProcessing)
            .help("Comprehensive AI review: merges duplicates, rebalances categories, and flags overly granular entries. Presents a plan for your approval before making changes.")

            } // end if !allSkills.isEmpty
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

    // MARK: - New Category Creation

    private var newCategoryRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder.badge.plus")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            TextField("Category name…", text: $newCategoryName)
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

    private func commitNewCategory() {
        let trimmed = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isCreatingCategory = false
        newCategoryName = ""
        expandedCategories.insert(trimmed)
        startAddingSkill(to: trimmed)
    }

    // MARK: - Inline Editing

    private func startEditing(_ skill: Skill) {
        editingSkillId = skill.id
        editingSkillName = skill.canonical
        editingSkillProficiency = skill.proficiency
        editingSkillCategory = skill.category
        editingSkillCustomCategory = ""
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
        editingSkillCategory = ""
        editingSkillCustomCategory = ""
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

    private func categorySection(_ category: String) -> some View {
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
                                        Text("New Category…").tag("__custom__")
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

    private func cycleProficiency(_ skill: Skill) {
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

    private func toggleCategory(_ category: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if expandedCategories.contains(category) {
                expandedCategories.remove(category)
            } else {
                expandedCategories.insert(category)
            }
        }
    }

    private func commitCategoryRename(from oldCategory: String) {
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
    private func colorForCategory(_ category: String) -> Color {
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

    // MARK: - Curation

    private func curateSkills() {
        guard let skillStore = skillStore, let facade = llmFacade else { return }

        isProcessing = true
        currentOperation = .curation
        processingMessage = "Analyzing skills for curation..."
        processingProgress = 0

        Task {
            do {
                let service = SkillBankCurationService(skillStore: skillStore, llmFacade: facade)
                let plan = try await service.generateCurationPlan()

                await MainActor.run {
                    self.curationPlan = plan
                    isProcessing = false
                    currentOperation = nil

                    if plan.isEmpty {
                        lastResult = SkillsProcessingResult(
                            operation: "Curation",
                            skillsProcessed: skillStore.skills.count,
                            skillsModified: 0,
                            details: "No curation changes suggested"
                        )
                        showResultAlert = true
                    } else {
                        showCurationReview = true
                    }
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

    private func colorFor(_ proficiency: Proficiency) -> Color {
        switch proficiency {
        case .expert: return .blue
        case .proficient: return .green
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
