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
        modelId: String
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

        // 2. Extract project-worthy content from KCs
        let projectKCs = context.projectKnowledgeCards
        for kc in projectKCs {
            let proposal = ProjectProposal(
                id: UUID(),
                name: kc.title,
                description: kc.narrative.prefix(200) + "...",
                rationale: "Project identified in your knowledge cards",
                sourceType: .knowledgeCard,
                sourceId: kc.id.uuidString,
                isApproved: false
            )
            proposals.append(proposal)
        }

        // 3. Use LLM to propose additional projects from context
        let llmProposals = try await discoverProjectsViaLLM(context: context, llmFacade: llmFacade, modelId: modelId)
        proposals.append(contentsOf: llmProposals)

        return proposals
    }

    private func discoverProjectsViaLLM(
        context: SeedGenerationContext,
        llmFacade: LLMFacade,
        modelId: String
    ) async throws -> [ProjectProposal] {
        let systemPrompt = "You are a resume expert identifying impactful projects from a candidate's experience."

        let prompt = """
            Analyze the candidate's background and identify potential projects that would strengthen their resume.

            ## Available Evidence

            ### Knowledge Cards
            \(context.knowledgeCards.prefix(10).map { "- \($0.title): \($0.narrative.prefix(100))..." }.joined(separator: "\n"))

            ### Skills
            \(context.skills.prefix(20).map { $0.canonical }.joined(separator: ", "))

            ### Work Experience
            \(context.workEntries.prefix(5).map { "\($0["title"].stringValue) at \($0["company"].stringValue)" }.joined(separator: "\n"))

            ## Instructions

            Identify 2-4 potential projects that:
            - Demonstrate technical skills or leadership
            - Could be highlighted on a resume
            - Are supported by the evidence above

            Return JSON:
            {
                "proposals": [
                    {
                        "name": "Project name",
                        "description": "Brief description",
                        "rationale": "Why this would be valuable on a resume"
                    }
                ]
            }
            """

        let response: ProjectProposalsResponse = try await llmFacade.executeStructuredWithDictionarySchema(
            prompt: "\(systemPrompt)\n\n\(prompt)",
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
                            "required": ["name", "description", "rationale"]
                        ]
                    ]
                ],
                "required": ["proposals"]
            ],
            schemaName: "project_proposals"
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
        preamble: String,
        llmFacade: LLMFacade,
        modelId: String
    ) async throws -> GeneratedContent {
        guard let targetId = task.targetId else {
            throw GeneratorError.missingContext("No targetId for project task")
        }

        // Try to find in timeline first
        let entry = context.getTimelineEntry(id: targetId)
        let taskContext = buildTaskContext(entry: entry, context: context)

        let systemPrompt = "You are a professional resume writer creating impactful project descriptions."

        let fullPrompt = """
            \(preamble)

            ---

            ## Task: Generate Project Content

            Create compelling content for this project entry.

            ## Context

            \(taskContext)

            ## Instructions

            Generate:
            1. A description (2-3 sentences) explaining the project's purpose and your role
            2. 2-4 highlights showing key achievements or contributions
            3. Relevant keywords/technologies

            Return JSON:
            {
                "description": "Project description",
                "highlights": ["highlight 1", "highlight 2"],
                "keywords": ["keyword1", "keyword2"]
            }
            """

        let response: ProjectResponse = try await llmFacade.executeStructuredWithDictionarySchema(
            prompt: "\(systemPrompt)\n\n\(fullPrompt)",
            modelId: modelId,
            as: ProjectResponse.self,
            schema: [
                "type": "object",
                "properties": [
                    "description": ["type": "string"],
                    "highlights": ["type": "array", "items": ["type": "string"]],
                    "keywords": ["type": "array", "items": ["type": "string"]]
                ],
                "required": ["description", "highlights", "keywords"]
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

    private func buildTaskContext(entry: JSON?, context: SeedGenerationContext) -> String {
        var lines: [String] = []

        if let entry = entry {
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
