//
//  ProjectsGenerator.swift
//  Sprung
//
//  Special generator for projects section with two-phase workflow:
//  1. Discovery: Analyze KCs and timeline for project-worthy content
//  2. Curation: User approves/rejects proposed projects
//  3. Generation: Create descriptions for approved projects
//

import Foundation
import SwiftyJSON

// MARK: - Response Types

private struct ProjectProposalsResponse: Codable {
    let proposals: [Proposal]

    struct Proposal: Codable {
        let name: String
        let description: String
        let rationale: String
    }
}

private struct ProjectResponse: Codable {
    let description: String
    let highlights: [String]
    let keywords: [String]
}

/// Proposal for a project discovered from evidence
struct ProjectProposal: Identifiable, Equatable {
    let id: UUID
    let name: String
    let description: String
    let rationale: String
    let sourceType: SourceType
    let sourceId: String?
    var isApproved: Bool = false

    enum SourceType: String, Codable {
        case timeline       // From existing timeline project entry
        case knowledgeCard  // Extracted from a KC
        case skillBank      // Inferred from skills
        case llmProposed    // LLM identified from context
    }
}

/// Generates projects section content with discovery workflow.
/// Unlike standard generators, this has a multi-phase process:
/// 1. discoverProjects() - Analyzes context and proposes projects
/// 2. User curates the proposals (UI)
/// 3. createTasks(for:) - Creates tasks for approved projects
/// 4. execute() - Generates content for each project
@MainActor
final class ProjectsGenerator: BaseSectionGenerator {
    override var displayName: String { "Projects" }

    init() {
        super.init(sectionKey: .projects)
    }

    // MARK: - Phase 1: Discovery

    /// Discover potential projects from the generation context.
    /// Returns proposals that the user can approve/reject.
    func discoverProjects(
        context: SeedGenerationContext,
        llmFacade: LLMFacade,
        modelId: String,
        backend: LLMFacade.Backend,
        preamble: String
    ) async throws -> [ProjectProposal] {
        var proposals: [ProjectProposal] = []

        // 1. Add existing timeline project entries
        let timelineProjects = context.timelineEntries(for: .projects)
        for entry in timelineProjects {
            let proposal = ProjectProposal(
                id: UUID(),
                name: entry["name"].stringValue,
                description: entry["description"].stringValue,
                rationale: "Existing project from your timeline",
                sourceType: .timeline,
                sourceId: entry["id"].string,
                isApproved: true  // Pre-approve timeline entries
            )
            proposals.append(proposal)
        }

        // 2. Extract project-worthy content from KCs typed as projects
        let projectKCs = context.projectKnowledgeCards
        for kc in projectKCs {
            let proposal = ProjectProposal(
                id: UUID(),
                name: kc.title,
                description: String(kc.narrative.prefix(200)) + "...",
                rationale: "Project identified in your knowledge cards",
                sourceType: .knowledgeCard,
                sourceId: kc.id.uuidString,
                isApproved: false
            )
            proposals.append(proposal)
        }

        // 3. Use LLM to discover additional projects from ALL evidence (uses cached preamble)
        let llmProposals = try await discoverProjectsViaLLM(
            context: context,
            llmFacade: llmFacade,
            modelId: modelId,
            backend: backend,
            preamble: preamble
        )
        proposals.append(contentsOf: llmProposals)

        return proposals
    }

    private func discoverProjectsViaLLM(
        context: SeedGenerationContext,
        llmFacade: LLMFacade,
        modelId: String,
        backend: LLMFacade.Backend,
        preamble: String
    ) async throws -> [ProjectProposal] {
        // Build list of existing timeline projects to avoid duplicates
        let existingProjects = context.projectEntries
        let existingProjectsList = existingProjects.isEmpty
            ? "None currently in timeline"
            : existingProjects.map { "- \($0["name"].stringValue)" }.joined(separator: "\n")

        // Build list of project-typed KCs (these are already being proposed separately)
        let projectKCs = context.projectKnowledgeCards
        let projectKCsList = projectKCs.isEmpty
            ? "None"
            : projectKCs.map { "- \($0.title)" }.joined(separator: "\n")

        // The preamble contains full KC content via prompt caching.
        // This task prompt focuses specifically on discovering NEW projects.
        let taskPrompt = """
            ## Task: Discover Resume-Worthy Projects

            Review ALL Knowledge Cards in the preamble above and identify projects that should be added to the resume.

            ### Already Captured (DO NOT suggest these)

            **Existing Timeline Projects:**
            \(existingProjectsList)

            **Project-typed Knowledge Cards (already being proposed):**
            \(projectKCsList)

            ### What to Look For

            Search the Knowledge Cards for project-worthy work that is NOT yet captured:

            1. **Technical initiatives** within employment KCs - systems built, tools created, infrastructure deployed
            2. **Significant deliverables** - product launches, platform migrations, major features shipped
            3. **Research outputs** - papers, prototypes, novel implementations
            4. **Independent work** - open source contributions, side projects, hackathon builds
            5. **Cross-functional efforts** - process improvements, team tools, documentation systems

            ### Requirements for Each Proposal

            - Must have clear evidence in a Knowledge Card (cite the specific KC)
            - Must be distinct from existing timeline projects and project KCs
            - Must be substantial enough to warrant a standalone resume entry
            - Must demonstrate skills or impact relevant to job searching

            ### Output

            Propose 0-4 new projects. If no qualifying projects are found, return an empty array.

            Return JSON:
            {
                "proposals": [
                    {
                        "name": "Concise project name",
                        "description": "2-3 sentence description based on KC evidence",
                        "rationale": "Why this deserves a project entry, citing which KC contains the evidence"
                    }
                ]
            }
            """

        // Combine cached preamble (with full KC content) with task-specific prompt
        let fullPrompt = """
            \(preamble)

            ---

            \(taskPrompt)
            """

        let response: ProjectProposalsResponse = try await llmFacade.executeStructuredWithDictionarySchema(
            prompt: fullPrompt,
            modelId: modelId,
            as: ProjectProposalsResponse.self,
            schema: [
                "type": "object",
                "properties": [
                    "proposals": [
                        "type": "array",
                        "items": [
                            "type": "object",
                            "properties": [
                                "name": ["type": "string"],
                                "description": ["type": "string"],
                                "rationale": ["type": "string"]
                            ],
                            "required": ["name", "description", "rationale"],
                            "additionalProperties": false
                        ]
                    ]
                ],
                "required": ["proposals"],
                "additionalProperties": false
            ],
            schemaName: "project_proposals",
            backend: backend
        )

        return response.proposals.map { item in
            ProjectProposal(
                id: UUID(),
                name: item.name,
                description: item.description,
                rationale: item.rationale,
                sourceType: .llmProposed,
                sourceId: nil,
                isApproved: false
            )
        }
    }

    // MARK: - Phase 2: Task Creation (for approved projects)

    /// Create tasks for approved projects only.
    /// Call this after user has curated the proposals.
    func createTasks(for approvedProjects: [ProjectProposal], context: SeedGenerationContext) -> [GenerationTask] {
        approvedProjects.map { proposal in
            GenerationTask(
                id: UUID(),
                section: .projects,
                targetId: proposal.id.uuidString,
                displayName: "Project: \(proposal.name)",
                generatorType: "ProjectsGenerator",
                status: .pending
            )
        }
    }

    /// Standard createTasks uses timeline entries only.
    /// For full discovery workflow, use discoverProjects() + createTasks(for:)
    override func createTasks(context: SeedGenerationContext) -> [GenerationTask] {
        let projectEntries = context.timelineEntries(for: .projects)

        return projectEntries.compactMap { entry -> GenerationTask? in
            guard let id = entry["id"].string else { return nil }

            let name = entry["name"].stringValue

            return GenerationTask(
                id: UUID(),
                section: .projects,
                targetId: id,
                displayName: "Project: \(name)",
                status: .pending
            )
        }
    }

    // MARK: - Phase 3: Execution

    override func execute(
        task: GenerationTask,
        context: SeedGenerationContext,
        config: GeneratorExecutionConfig
    ) async throws -> GeneratedContent {
        guard let targetId = task.targetId else {
            throw GeneratorError.missingContext("No targetId for project task")
        }

        // Try to find in timeline first, then check ExperienceDefaults store
        let entry = context.getTimelineEntry(id: targetId)
        let taskContext = buildTaskContext(entry: entry, targetId: targetId, context: context, store: config.experienceDefaultsStore)

        let systemPrompt = "You are a professional resume writer. Generate project content based strictly on documented evidence."

        let taskPrompt = """
            ## Task: Generate Project Content

            Generate content for this project entry based on documented evidence.

            ## Context

            \(taskContext)

            ## Requirements

            Generate:
            1. A description (2-3 sentences) explaining the project's purpose and your role
            2. 2-4 highlights showing key achievements or contributions
            3. Relevant keywords/technologies

            ## CONSTRAINTS

            1. Use ONLY facts from the provided Knowledge Cards
            2. Do NOT invent metrics, percentages, or quantitative claims
            3. Match the candidate's writing voice from the samples
            4. Avoid generic resume phrases

            ## FORBIDDEN

            - Fabricated numbers ("increased by X%", "reduced by Y%")
            - Generic phrases ("spearheaded", "leveraged", "drove")
            - Vague claims ("significantly improved", "enhanced")

            Return JSON:
            {
                "description": "Project description",
                "highlights": ["highlight 1", "highlight 2"],
                "keywords": ["keyword1", "keyword2"]
            }
            """

        let response: ProjectResponse = try await executeStructuredRequest(
            taskPrompt: taskPrompt,
            systemPrompt: systemPrompt,
            config: config,
            responseType: ProjectResponse.self,
            schema: [
                "type": "object",
                "properties": [
                    "description": ["type": "string"],
                    "highlights": ["type": "array", "items": ["type": "string"]],
                    "keywords": ["type": "array", "items": ["type": "string"]]
                ],
                "required": ["description", "highlights", "keywords"],
                "additionalProperties": false
            ],
            schemaName: "project"
        )

        return GeneratedContent(
            type: .projectDescription(
                targetId: targetId,
                description: response.description,
                highlights: response.highlights,
                keywords: response.keywords
            )
        )
    }

    // MARK: - Regeneration

    override func regenerate(
        task: GenerationTask,
        originalContent: GeneratedContent,
        feedback: String?,
        context: SeedGenerationContext,
        config: GeneratorExecutionConfig
    ) async throws -> GeneratedContent {
        guard let targetId = task.targetId else {
            throw GeneratorError.missingContext("No targetId for project task")
        }

        let entry = context.getTimelineEntry(id: targetId)
        let taskContext = buildTaskContext(entry: entry, targetId: targetId, context: context, store: config.experienceDefaultsStore)
        let regenerationContext = buildRegenerationContext(originalContent: originalContent, feedback: feedback)

        let systemPrompt = "You are a professional resume writer. Generate project content based strictly on documented evidence."

        let taskPrompt = """
            ## Task: Revise Project Content

            Revise the content for this project entry based on user feedback.

            ## Context

            \(taskContext)

            \(regenerationContext)

            ## Requirements

            Generate:
            1. A description (2-3 sentences) explaining the project's purpose and your role
            2. 2-4 highlights showing key achievements or contributions
            3. Relevant keywords/technologies

            ## CONSTRAINTS

            1. Use ONLY facts from the provided Knowledge Cards
            2. Do NOT invent metrics, percentages, or quantitative claims
            3. Match the candidate's writing voice from the samples
            4. Avoid generic resume phrases
            """

        let response: ProjectResponse = try await executeStructuredRequest(
            taskPrompt: taskPrompt,
            systemPrompt: systemPrompt,
            config: config,
            responseType: ProjectResponse.self,
            schema: [
                "type": "object",
                "properties": [
                    "description": ["type": "string"],
                    "highlights": ["type": "array", "items": ["type": "string"]],
                    "keywords": ["type": "array", "items": ["type": "string"]]
                ],
                "required": ["description", "highlights", "keywords"],
                "additionalProperties": false
            ],
            schemaName: "project"
        )

        return GeneratedContent(
            type: .projectDescription(
                targetId: targetId,
                description: response.description,
                highlights: response.highlights,
                keywords: response.keywords
            )
        )
    }

    // MARK: - Apply to Defaults

    override func apply(content: GeneratedContent, to defaults: inout ExperienceDefaults) {
        guard case .projectDescription(let targetId, let description, let highlights, let keywords) = content.type else {
            Logger.warning("ProjectsGenerator: content type mismatch", category: .ai)
            return
        }

        if let index = defaults.projects.firstIndex(where: { $0.id.uuidString == targetId }) {
            defaults.projects[index].description = description
            defaults.projects[index].highlights = highlights.map { ProjectHighlightDraft(text: $0) }
            defaults.projects[index].keywords = keywords.map { KeywordDraft(keyword: $0) }
            Logger.info("Applied project content to entry: \(targetId)", category: .ai)
        } else {
            Logger.warning("Project entry not found for targetId: \(targetId)", category: .ai)
        }
    }

    // MARK: - Context Building

    private func buildTaskContext(
        entry: JSON?,
        targetId: String?,
        context: SeedGenerationContext,
        store: ExperienceDefaultsStore?
    ) -> String {
        var lines: [String] = []

        if let entry = entry {
            // Timeline entry exists - use it
            lines.append("### Project Details")
            if let name = entry["name"].string { lines.append("**Name:** \(name)") }
            if let description = entry["description"].string { lines.append("**Description:** \(description)") }
            if let startDate = entry["startDate"].string { lines.append("**Start Date:** \(startDate)") }
            if let endDate = entry["endDate"].string { lines.append("**End Date:** \(endDate)") }
            if let url = entry["url"].string { lines.append("**URL:** \(url)") }

            if let existingHighlights = entry["highlights"].array, !existingHighlights.isEmpty {
                lines.append("\n### Existing Highlights")
                for highlight in existingHighlights {
                    lines.append("- \(highlight.stringValue)")
                }
            }
        } else if let targetId = targetId,
                  let store = store,
                  let projectUUID = UUID(uuidString: targetId),
                  let project = store.currentDefaults().projects.first(where: { $0.id == projectUUID }) {
            // Found in ExperienceDefaults (single source of truth)
            lines.append("### Project Details")
            lines.append("**Name:** \(project.name)")
            if !project.description.isEmpty {
                lines.append("**Description:** \(project.description)")
            }
            if !project.startDate.isEmpty { lines.append("**Start Date:** \(project.startDate)") }
            if !project.endDate.isEmpty { lines.append("**End Date:** \(project.endDate)") }
            if !project.url.isEmpty { lines.append("**URL:** \(project.url)") }

            // Search for relevant KCs by project name
            let relevantKCs = context.knowledgeCards.filter { kc in
                kc.narrative.localizedCaseInsensitiveContains(project.name) ||
                kc.title.localizedCaseInsensitiveContains(project.name)
            }
            if !relevantKCs.isEmpty {
                lines.append("\n### Relevant Knowledge Cards")
                for kc in relevantKCs.prefix(3) {
                    lines.append("\n#### \(kc.title)")
                    lines.append(String(kc.narrative.prefix(500)) + (kc.narrative.count > 500 ? "..." : ""))
                }
            }
        } else {
            lines.append("### Project Details")
            lines.append("**WARNING:** No project details available for this task (targetId: \(targetId ?? "nil")).")
        }

        // Include relevant skills
        if !context.skills.isEmpty {
            lines.append("\n### Available Skills")
            let topSkills = context.skills.prefix(15).map { $0.canonical }
            lines.append(topSkills.joined(separator: ", "))
        }

        return lines.joined(separator: "\n")
    }
}
