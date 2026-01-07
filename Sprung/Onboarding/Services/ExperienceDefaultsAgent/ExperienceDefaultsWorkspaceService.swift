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

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private let decoder = JSONDecoder()

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
        let subdirs = ["knowledge_cards", "skills", "timeline", "config", "output"]
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
        customFields: [CustomFieldDefinition]
    ) throws {
        guard workspacePath != nil else {
            throw WorkspaceError.workspaceNotCreated
        }

        try exportKnowledgeCards(knowledgeCards)
        try exportSkills(skills)
        try exportTimeline(timelineEntries)
        try exportConfig(enabledSections: enabledSections, customFields: customFields)
        try writeOverviewDocument(
            kcCount: knowledgeCards.count,
            skillCount: skills.count,
            timelineCount: timelineEntries.count,
            enabledSections: enabledSections
        )
    }

    /// Exports knowledge cards with index summary
    private func exportKnowledgeCards(_ cards: [KnowledgeCard]) throws {
        guard let kcDir = knowledgeCardsPath else { throw WorkspaceError.workspaceNotCreated }

        var indexEntries: [[String: Any]] = []

        for card in cards {
            // Write full card to {uuid}.json
            let cardFile = kcDir.appendingPathComponent("\(card.id.uuidString).json")
            let cardData = try encoder.encode(card)
            try cardData.write(to: cardFile)

            // Build summary for index
            let summary: [String: Any] = [
                "id": card.id.uuidString,
                "card_type": card.cardType?.rawValue ?? "other",
                "title": card.title,
                "organization": card.organization ?? "",
                "date_range": card.dateRange ?? "",
                "narrative_preview": String(card.narrative.prefix(150)),
                "facts_count": card.facts.count,
                "technologies": Array(card.technologies.prefix(5))
            ]
            indexEntries.append(summary)
        }

        // Write index
        let indexFile = kcDir.appendingPathComponent("index.json")
        let indexData = try JSONSerialization.data(withJSONObject: indexEntries, options: [.prettyPrinted, .sortedKeys])
        try indexData.write(to: indexFile)

        Logger.info("📤 Exported \(cards.count) knowledge cards to workspace", category: .ai)
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

    /// Exports configuration (enabled sections, custom fields)
    private func exportConfig(enabledSections: [String], customFields: [CustomFieldDefinition]) throws {
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

        Logger.info("📤 Exported config to workspace", category: .ai)
    }

    /// Writes an overview document the agent can read first
    private func writeOverviewDocument(
        kcCount: Int,
        skillCount: Int,
        timelineCount: Int,
        enabledSections: [String]
    ) throws {
        guard let workspace = workspacePath else { throw WorkspaceError.workspaceNotCreated }

        let overview = """
        # Experience Defaults Workspace

        ## Your Task
        Generate resume-ready content for the Experience Editor based on the collected evidence.

        ## Available Data

        ### Knowledge Cards (\(kcCount) cards)
        Location: `knowledge_cards/`
        - `index.json` - Summary of all cards (id, title, organization, date_range, narrative_preview)
        - Individual card files: `{uuid}.json` - Full card with facts, bullets, technologies, outcomes

        ### Skills Bank (\(skillCount) skills)
        Location: `skills/`
        - `summary.json` - Skills grouped by category with counts
        - `all_skills.json` - Full skill details including evidence

        ### Timeline Entries (\(timelineCount) entries)
        Location: `timeline/`
        - `index.json` - All timeline entries (work, education, projects, etc.)
        - Individual entry files for details

        ### Configuration
        Location: `config/`
        - `enabled_sections.json` - Sections to include: \(enabledSections.joined(separator: ", "))
        - `custom_fields.json` - Custom fields defined by user (if any)

        ## Output Requirements

        Write your output to: `output/experience_defaults.json`

        The output should be a JSON object with these sections (only include enabled ones):
        - `work`: Array of work entries with 3-4 bullet highlights each
        - `education`: Array of education entries with highlights
        - `projects`: Array of 2-5 selected projects with summaries
        - `skills`: Object with 5 categories, 25-35 total skills
        - `volunteer`, `awards`, `certificates`, `publications`: As applicable

        ## Workflow

        1. Read `knowledge_cards/index.json` to understand what evidence exists
        2. Read `timeline/index.json` to see the career structure
        3. Read `config/enabled_sections.json` to know which sections to generate
        4. For each timeline entry, find matching KCs and generate content
        5. For skills, read `skills/summary.json` and curate top 25-35
        6. Write final output to `output/experience_defaults.json`

        ## Quality Guidelines

        - Work highlights: 3-4 bullets per entry, start with action verbs, include quantified impact
        - Projects: 2-5 selected, 2-3 sentence summaries, list technologies
        - Skills: 25-35 total in 5 categories, no duplicates, every skill has KC evidence

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
