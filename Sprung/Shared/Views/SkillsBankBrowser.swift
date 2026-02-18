import SwiftUI

/// Skills Bank browser showing skills grouped by category in an expandable list view.
/// Includes LLM-powered tools for deduplication and ATS synonym expansion.
struct SkillsBankBrowser: View {
    let skillStore: SkillStore?
    var llmFacade: LLMFacade?

    @Environment(ArtifactRecordStore.self) private var artifactRecordStore

    @State var expandedCategories: Set<String> = []
    @State var expandedSkills: Set<UUID> = []
    @State var searchText = ""
    @State var selectedProficiency: Proficiency?

    // Processing state
    @State var processingService: SkillsProcessingService?
    @State var isProcessing = false
    @State var currentOperation: ProcessingOperation?
    @State var processingMessage = ""
    @State var processingProgress: Double = 0
    @State var lastResult: SkillsProcessingResult?
    @State var showResultAlert = false
    @State var errorMessage: String?

    // Curation state
    @State var showCurationReview = false
    @State var curationPlan: SkillCurationPlan?
    @State var isCurating = false

    // Inline editing state
    @State var editingSkillId: UUID?
    @State var editingSkillName: String = ""
    @State var editingSkillProficiency: Proficiency = .proficient
    @State var editingSkillCategory: String = ""
    @State var editingSkillCustomCategory: String = ""

    // Refine feature state
    @State var showRefinePopover = false
    @State var refineInstruction = ""

    // Sort debounce after proficiency cycling
    @State var sortFrozenOrder: [UUID: Int] = [:]
    @State var sortUnfreezeTask: Task<Void, Never>?

    // Add skill feature state (inline)
    @State var addingToCategory: String?
    @State var newSkillName = ""
    @State var newSkillProficiency: Proficiency = .proficient
    @State var isAddingSkill = false

    // New category creation state
    @State var isCreatingCategory = false
    @State var newCategoryName = ""

    // Category rename state
    @State var renamingCategory: String?
    @State var renamingCategoryText = ""

    // Extraction state
    @State var showExtractionSheet = false

    enum ProcessingOperation {
        case deduplication
        case atsExpansion
        case refine
        case curation
        case extraction
    }

    /// All skills from the store
    var allSkills: [Skill] {
        skillStore?.skills ?? []
    }

    var groupedSkills: [String: [Skill]] {
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

    var sortedCategories: [String] {
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

    // MARK: - Filter Bar & Action Buttons

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

    // MARK: - Refine Popover

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

    // MARK: - Processing Overlay

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

    // MARK: - Proficiency Chip

    func proficiencyChip(_ proficiency: Proficiency?, label: String) -> some View {
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

    // MARK: - Empty / No-Match States

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
