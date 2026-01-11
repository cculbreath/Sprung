//
//  ExperienceDefaultsWorkspaceService.swift
//  Sprung
//
//  Manages an ephemeral filesystem workspace for the ExperienceDefaults agent.
//  Exports knowledge cards, skills, timeline, and configuration to files the agent can read.
//  Agent writes experience_defaults.json to output folder.
//

import Foundation
import SwiftyJSON

@MainActor
final class ExperienceDefaultsWorkspaceService {
    private let guidanceStore: InferenceGuidanceStore

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private let decoder = JSONDecoder()

    init(guidanceStore: InferenceGuidanceStore) {
        self.guidanceStore = guidanceStore
    }

    /// Workspace directory path
    private var workspacePath: URL?

    // MARK: - Subdirectory Paths

    private var knowledgeCardsPath: URL? {
        workspacePath?.appendingPathComponent("knowledge_cards")
    }

    private var skillsPath: URL? {
        workspacePath?.appendingPathComponent("skills")
    }

    private var timelinePath: URL? {
        workspacePath?.appendingPathComponent("timeline")
    }

    private var configPath: URL? {
        workspacePath?.appendingPathComponent("config")
    }

    private var guidancePath: URL? {
        workspacePath?.appendingPathComponent("guidance")
    }

    private var outputPath: URL? {
        workspacePath?.appendingPathComponent("output")
    }

    // MARK: - Workspace Lifecycle

    /// Creates a fresh workspace directory with all subdirectories.
    func createWorkspace() throws -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let sprungDir = appSupport.appendingPathComponent("Sprung")
        let workspace = sprungDir.appendingPathComponent("experience-defaults-workspace")

        // Remove existing workspace if present
        if FileManager.default.fileExists(atPath: workspace.path) {
            try FileManager.default.removeItem(at: workspace)
            Logger.info("🗑️ Removed existing experience-defaults workspace", category: .ai)
        }

        // Create workspace and subdirectories
        let subdirs = ["knowledge_cards", "skills", "timeline", "config", "guidance", "output"]
        for subdir in subdirs {
            let path = workspace.appendingPathComponent(subdir)
            try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        }

        workspacePath = workspace
        Logger.info("📁 Created experience-defaults workspace at \(workspace.path)", category: .ai)

        return workspace
    }

    /// Deletes the workspace directory and all contents.
    func deleteWorkspace() throws {
        guard let workspace = workspacePath else { return }

        if FileManager.default.fileExists(atPath: workspace.path) {
            try FileManager.default.removeItem(at: workspace)
            Logger.info("🗑️ Deleted experience-defaults workspace", category: .ai)
        }

        workspacePath = nil
    }

    // MARK: - Export Data

    /// Exports all data needed by the agent to the workspace.
    func exportData(
        knowledgeCards: [KnowledgeCard],
        skills: [Skill],
        timelineEntries: [JSON],
        enabledSections: [String],
        customFields: [CustomFieldDefinition],
        selectedTitles: [String]? = nil
    ) throws {
        guard workspacePath != nil else {
            throw WorkspaceError.workspaceNotCreated
        }

        try exportKnowledgeCards(knowledgeCards)
        try exportSkills(skills)
        try exportTimeline(timelineEntries)
        try exportConfig(enabledSections: enabledSections, customFields: customFields, selectedTitles: selectedTitles)
        let includeTitleSets = customFields.contains { $0.key.lowercased() == "custom.jobtitles" }
        try exportGuidance(includeTitleSets: includeTitleSets)

        // Compute KC counts by type for OVERVIEW.md
        var kcCountsByType: [String: Int] = [:]
        for card in knowledgeCards {
            let cardType = card.cardType?.rawValue ?? "other"
            kcCountsByType[cardType, default: 0] += 1
        }

        try writeOverviewDocument(
            kcCount: knowledgeCards.count,
            skillCount: skills.count,
            timelineCount: timelineEntries.count,
            enabledSections: enabledSections,
            includeTitleSets: includeTitleSets,
            selectedTitles: selectedTitles,
            kcCountsByType: kcCountsByType
        )
    }

    /// Exports knowledge cards with index summary and by-type organization
    private func exportKnowledgeCards(_ cards: [KnowledgeCard]) throws {
        guard let kcDir = knowledgeCardsPath else { throw WorkspaceError.workspaceNotCreated }

        // Create by_type subdirectories
        let byTypeDir = kcDir.appendingPathComponent("by_type")
        let cardTypes = ["employment", "education", "project", "achievement", "other"]
        for cardType in cardTypes {
            let typeDir = byTypeDir.appendingPathComponent(cardType)
            try FileManager.default.createDirectory(at: typeDir, withIntermediateDirectories: true)
        }

        var indexEntries: [[String: Any]] = []
        var typeCounts: [String: Int] = [:]

        for card in cards {
            let cardType = card.cardType?.rawValue ?? "other"

            // Write full card to flat {uuid}.json
            let cardFile = kcDir.appendingPathComponent("\(card.id.uuidString).json")
            let cardData = try encoder.encode(card)
            try cardData.write(to: cardFile)

            // Also write to by_type/{type}/{uuid}.json for organized access
            let typeDir = byTypeDir.appendingPathComponent(cardType)
            let typeCardFile = typeDir.appendingPathComponent("\(card.id.uuidString).json")
            try cardData.write(to: typeCardFile)

            // Track counts
            typeCounts[cardType, default: 0] += 1

            // Build summary for index
            let summary: [String: Any] = [
                "id": card.id.uuidString,
                "cardType": cardType,
                "title": card.title,
                "organization": card.organization ?? "",
                "dateRange": card.dateRange ?? "",
                "narrativePreview": String(card.narrative.prefix(200)),
                "factsCount": card.facts.count,
                "technologies": Array(card.technologies.prefix(8)),
                "suggestedBulletsCount": card.suggestedBullets.count,
                "location": card.location ?? ""
            ]
            indexEntries.append(summary)
        }

        // Write main index
        let indexFile = kcDir.appendingPathComponent("index.json")
        let indexPayload: [String: Any] = [
            "totalCount": cards.count,
            "byType": typeCounts,
            "cards": indexEntries
        ]
        let indexData = try JSONSerialization.data(withJSONObject: indexPayload, options: [.prettyPrinted, .sortedKeys])
        try indexData.write(to: indexFile)

        // Write per-type index files for quick access
        for cardType in cardTypes {
            let typeCards = indexEntries.filter { ($0["cardType"] as? String) == cardType }
            if !typeCards.isEmpty {
                let typeIndexFile = byTypeDir.appendingPathComponent(cardType).appendingPathComponent("index.json")
                let typeIndexData = try JSONSerialization.data(withJSONObject: [
                    "cardType": cardType,
                    "count": typeCards.count,
                    "cards": typeCards
                ], options: [.prettyPrinted, .sortedKeys])
                try typeIndexData.write(to: typeIndexFile)
            }
        }

        Logger.info("📤 Exported \(cards.count) knowledge cards to workspace (by type: \(typeCounts))", category: .ai)
    }

    /// Exports skills with summary
    private func exportSkills(_ skills: [Skill]) throws {
        guard let skillsDir = skillsPath else { throw WorkspaceError.workspaceNotCreated }

        // Group skills by category for the summary
        var skillsByCategory: [String: [[String: Any]]] = [:]

        for skill in skills {
            let category = skill.category.rawValue
            let skillSummary: [String: Any] = [
                "id": skill.id.uuidString,
                "canonical": skill.canonical,
                "proficiency": skill.proficiency.rawValue,
                "ats_variants": skill.atsVariants,
                "evidence_count": skill.evidence.count,
                "last_used": skill.lastUsed ?? ""
            ]
            skillsByCategory[category, default: []].append(skillSummary)
        }

        // Write full skills array
        let allSkillsFile = skillsDir.appendingPathComponent("all_skills.json")
        let skillsData = try encoder.encode(skills)
        try skillsData.write(to: allSkillsFile)

        // Write summary by category
        let summaryFile = skillsDir.appendingPathComponent("summary.json")
        let summaryData = try JSONSerialization.data(withJSONObject: [
            "total_count": skills.count,
            "by_category": skillsByCategory
        ], options: [.prettyPrinted, .sortedKeys])
        try summaryData.write(to: summaryFile)

        Logger.info("📤 Exported \(skills.count) skills to workspace", category: .ai)
    }

    /// Exports timeline entries
    private func exportTimeline(_ entries: [JSON]) throws {
        guard let timelineDir = timelinePath else { throw WorkspaceError.workspaceNotCreated }

        // Write each entry as a separate file
        for (index, entry) in entries.enumerated() {
            let entryId = entry["id"].stringValue.isEmpty ? "entry_\(index)" : entry["id"].stringValue
            let entryFile = timelineDir.appendingPathComponent("\(entryId).json")
            let entryData = try entry.rawData(options: [.prettyPrinted, .sortedKeys])
            try entryData.write(to: entryFile)
        }

        // Write index with all entries
        let indexFile = timelineDir.appendingPathComponent("index.json")
        let indexData = try JSON(entries).rawData(options: [.prettyPrinted, .sortedKeys])
        try indexData.write(to: indexFile)

        Logger.info("📤 Exported \(entries.count) timeline entries to workspace", category: .ai)
    }

    /// Exports configuration (enabled sections, custom fields, selected titles)
    private func exportConfig(
        enabledSections: [String],
        customFields: [CustomFieldDefinition],
        selectedTitles: [String]?
    ) throws {
        guard let configDir = configPath else { throw WorkspaceError.workspaceNotCreated }

        // Enabled sections
        let sectionsFile = configDir.appendingPathComponent("enabled_sections.json")
        let sectionsData = try JSONSerialization.data(withJSONObject: enabledSections, options: [.prettyPrinted])
        try sectionsData.write(to: sectionsFile)

        // Custom fields
        let customFieldsFile = configDir.appendingPathComponent("custom_fields.json")
        let customFieldsArray = customFields.map { field -> [String: String] in
            ["key": field.key, "description": field.description]
        }
        let customFieldsData = try JSONSerialization.data(withJSONObject: customFieldsArray, options: [.prettyPrinted])
        try customFieldsData.write(to: customFieldsFile)

        // Selected titles (if provided)
        if let titles = selectedTitles {
            let titlesFile = configDir.appendingPathComponent("selected_titles.json")
            let titlesData = try JSONSerialization.data(withJSONObject: titles, options: [.prettyPrinted])
            try titlesData.write(to: titlesFile)
            Logger.info("📤 Exported selected titles: \(titles.joined(separator: ", "))", category: .ai)
        }

        Logger.info("📤 Exported config to workspace", category: .ai)
    }

    /// Exports guidance (voice profile + title sets)
    private func exportGuidance(includeTitleSets: Bool) throws {
        guard let guidanceDir = guidancePath else { throw WorkspaceError.workspaceNotCreated }

        let voiceProfile = guidanceStore.voiceProfile() ?? VoiceProfile()
        let voiceData = try encoder.encode(voiceProfile)
        try voiceData.write(to: guidanceDir.appendingPathComponent("voice_profile.json"))

        if includeTitleSets {
            let titleSets = guidanceStore.titleSets()
            let vocabulary = guidanceStore.identityVocabulary()
            struct TitleGuidanceExport: Codable {
                let titleSets: [TitleSet]
                let vocabulary: [IdentityTerm]

                enum CodingKeys: String, CodingKey {
                    case titleSets = "title_sets"
                    case vocabulary
                }
            }
            let titlePayload = TitleGuidanceExport(titleSets: titleSets, vocabulary: vocabulary)
            let titleData = try encoder.encode(titlePayload)
            try titleData.write(to: guidanceDir.appendingPathComponent("title_sets.json"))
        }

        let guidanceIndex = guidanceStore.allGuidance
            .filter { includeTitleSets || $0.nodeKey.lowercased() != "custom.jobtitles" }
            .map { guidance in
                [
                    "node_key": guidance.nodeKey,
                    "display_name": guidance.displayName,
                    "prompt": guidance.prompt
                ]
            }
        let indexData = try JSONSerialization.data(
            withJSONObject: ["guidance": guidanceIndex],
            options: [.prettyPrinted, .sortedKeys]
        )
        try indexData.write(to: guidanceDir.appendingPathComponent("index.json"))

        Logger.info("📤 Exported guidance to workspace", category: .ai)
    }

    /// Writes an overview document the agent can read first
    private func writeOverviewDocument(
        kcCount: Int,
        skillCount: Int,
        timelineCount: Int,
        enabledSections: [String],
        includeTitleSets: Bool,
        selectedTitles: [String]?,
        kcCountsByType: [String: Int] = [:]
    ) throws {
        guard let workspace = workspacePath else { throw WorkspaceError.workspaceNotCreated }

        let voiceProfile = guidanceStore.voiceProfile() ?? VoiceProfile()
        let guidanceIntro = includeTitleSets
            ? "Voice profile and title sets have been pre-generated. Read these FIRST:"
            : "Voice profile has been pre-generated. Read this FIRST:"

        // If titles are pre-selected, use them directly; otherwise agent picks from curated sets
        let titleSetsSection: String
        if let titles = selectedTitles {
            titleSetsSection = """
            ### Identity Titles (PRE-SELECTED)
            The orchestrator has already selected the best title set for broad applicability:
            **\(titles.joined(separator: " • "))**

            Use these exact titles in `config/selected_titles.json` for the custom.jobTitles field.
            Do NOT pick different titles from guidance/title_sets.json.
            """
        } else if includeTitleSets {
            titleSetsSection = """
            ### Title Sets (`guidance/title_sets.json`)
            User has curated identity title options. SELECT the best-fit set based on:
            - Job type match (suggested_for field)
            - User favorites (is_favorite: true)
            """
        } else {
            titleSetsSection = ""
        }

        let titleInstruction: String
        if selectedTitles != nil {
            titleInstruction = "custom.jobTitles is enabled: use the pre-selected titles from config/selected_titles.json."
        } else if includeTitleSets {
            titleInstruction = "custom.jobTitles is enabled: select titles from guidance/title_sets.json."
        } else {
            titleInstruction = "custom.jobTitles is NOT enabled: do not output identity titles."
        }

        // Build KC type breakdown string
        var kcTypeBreakdown = ""
        if !kcCountsByType.isEmpty {
            let sortedTypes = kcCountsByType.sorted { $0.value > $1.value }
            let breakdownParts = sortedTypes.map { "\($0.key): \($0.value)" }
            kcTypeBreakdown = " (\(breakdownParts.joined(separator: ", ")))"
        }

        let overview = """
        # Experience Defaults Workspace

        ## Your Task
        Generate high-quality, generally applicable resume content from the collected evidence.
        This content will be the default for all resumes, customized per-job later.

        ## Guidance (REQUIRED READING)

        \(guidanceIntro)

        ### Voice Profile (`guidance/voice_profile.json`)
        - Enthusiasm level: \(voiceProfile.enthusiasm.displayName)
        - First person: \(voiceProfile.useFirstPerson)
        - Connective style: \(voiceProfile.connectiveStyle)
        - Aspirational phrases: \(voiceProfile.aspirationalPhrases.joined(separator: ", "))
        - AVOID these phrases: \(voiceProfile.avoidPhrases.joined(separator: ", "))

        \(titleSetsSection)

        \(titleInstruction)

        ## Available Data

        ### Knowledge Cards (\(kcCount) cards)\(kcTypeBreakdown)
        Location: `knowledge_cards/`

        **Organized by type for efficient access:**
        - `index.json` - Summary of ALL cards with cardType, title, organization, narrativePreview
        - `by_type/employment/` - KCs for work history (use for work highlights)
        - `by_type/education/` - KCs for education entries
        - `by_type/project/` - KCs for projects section
        - `by_type/achievement/` - KCs for awards, publications, certificates
        - `{uuid}.json` - Direct access to any card by ID

        **Workflow for KCs:**
        1. Read `index.json` to see all available cards and their types
        2. For work section: read `by_type/employment/index.json` for relevant KCs
        3. Read individual KC files when you need full narrative details

        ### Skills Bank (\(skillCount) skills)
        Location: `skills/`
        - `summary.json` - Skills grouped by category with counts
        - `all_skills.json` - Full skill details including evidence

        ### Timeline Entries (\(timelineCount) entries)
        Location: `timeline/`
        - `index.json` - All timeline entries (work, education, projects, etc.)

        ### Configuration
        Location: `config/`
        - `enabled_sections.json` - Sections to include: \(enabledSections.joined(separator: ", "))
        - `custom_fields.json` - Custom fields defined by user (if any)

        ## Section-by-Section Workflow

        Process ONE section at a time to manage context:

        ### Step 1: Configuration
        1. Read this OVERVIEW.md (done!)
        2. Read `guidance/voice_profile.json`
        3. Read `config/enabled_sections.json`
        4. Read `config/custom_fields.json`

        ### Step 2: Work Section (if enabled)
        1. Read `knowledge_cards/by_type/employment/index.json`
        2. For each work timeline entry, find matching KCs by organization
        3. Read full KCs to extract specific details for bullets
        4. Generate 3-4 high-quality highlights per entry

        ### Step 3: Other Sections
        - Education: Use timeline + `by_type/education/` KCs
        - Projects: Use `by_type/project/` KCs
        - Skills: Use `skills/summary.json`, create 3-6 dynamic categories
        - Awards/Certs/Publications: Use `by_type/achievement/` KCs

        ### Step 4: Write Output
        Write to `output/experience_defaults.json`

        ## Work Highlights: Quality Standards

        Each work bullet MUST:

        **1. Be Generally Applicable**
        BAD: "Optimized database queries for e-commerce checkout"
        GOOD: "Optimized critical database queries, reducing response times by 60%"

        **2. Include Specific Evidence from KCs**
        BAD: "Improved system performance significantly"
        GOOD: "Reduced API latency from 800ms to 120ms through query optimization"

        **3. Show Problem-Solving**
        BAD: "Developed automated testing framework"
        GOOD: "Noticed manual testing consuming 40% of sprint time - built framework that cut cycles from 2 days to 4 hours"

        **4. Quantify When Possible**
        BAD: "Handled large-scale data processing"
        GOOD: "Processed 2TB of sensor data daily, identifying 12% more defects"

        ## Output Schema

        Write valid JSON to `output/experience_defaults.json`:

        ```json
        {
          "isWorkEnabled": true,
          "work": [
            {
              "name": "Company Name",
              "position": "Job Title",
              "location": "City, State",
              "startDate": "YYYY-MM",
              "endDate": "YYYY-MM",
              "highlights": [
                "High-quality bullet with specifics",
                "Another bullet with metrics"
              ]
            }
          ],
          "isSkillsEnabled": true,
          "skills": [
            {
              "name": "Category Name",
              "level": "Expert",
              "keywords": ["Skill1", "Skill2"]
            }
          ],
          "custom.objective": "5-6 sentence objective statement",
          "custom.jobTitles": ["Title1", "Title2", "Title3", "Title4"]
        }
        ```

        Include only enabled sections. Use simple string arrays for highlights and keywords.

        When done, call `complete_generation` with a summary of what was generated.
        """

        let overviewFile = workspace.appendingPathComponent("OVERVIEW.md")
        try overview.write(to: overviewFile, atomically: true, encoding: .utf8)

        Logger.info("📤 Wrote OVERVIEW.md to workspace", category: .ai)
    }

    // MARK: - Import Output

    /// Reads the generated experience_defaults.json from the output folder
    func importOutput() throws -> JSON {
        guard let outputDir = outputPath else {
            throw WorkspaceError.workspaceNotCreated
        }

        let outputFile = outputDir.appendingPathComponent("experience_defaults.json")
        guard FileManager.default.fileExists(atPath: outputFile.path) else {
            throw WorkspaceError.outputNotFound
        }

        let data = try Data(contentsOf: outputFile)
        return try JSON(data: data)
    }

    /// Returns the workspace path for the agent
    func getWorkspacePath() -> URL? {
        workspacePath
    }

    // MARK: - Errors

    enum WorkspaceError: Error, LocalizedError {
        case workspaceNotCreated
        case outputNotFound

        var errorDescription: String? {
            switch self {
            case .workspaceNotCreated:
                return "Workspace has not been created"
            case .outputNotFound:
                return "Agent did not produce output/experience_defaults.json"
            }
        }
    }
}
