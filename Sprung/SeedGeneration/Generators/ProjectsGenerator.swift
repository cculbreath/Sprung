//
//  ProjectsGenerator.swift
//  Sprung
//
//  Generator for projects section content.
//  Creates one task per timeline project entry, generating a description,
//  highlights, and keywords from Knowledge Card evidence. Projects are
//  curated during the onboarding interview; this generator only populates
//  them — it never proposes new entries.
//

import Foundation
import SwiftyJSON

// MARK: - Response Types

private struct ProjectResponse: Codable {
    let description: String
    let highlights: [String]
    let keywords: [String]
}

/// Generates content for the project entries curated during onboarding.
@MainActor
final class ProjectsGenerator: BaseSectionGenerator {
    override var displayName: String { "Projects" }

    init() {
        super.init(sectionKey: .projects)
    }

    // MARK: - Task Creation

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

    // MARK: - Execution

    override func execute(
        task: GenerationTask,
        context: SeedGenerationContext,
        config: GeneratorExecutionConfig
    ) async throws -> GeneratedContent {
        guard let targetId = task.targetId else {
            throw GeneratorError.missingContext("No targetId for project task")
        }

        let entry = try findTimelineEntry(id: targetId, in: context)
        let taskContext = buildTaskContext(entry: entry, context: context)

        let systemPrompt = "You are a professional resume writer. Generate project content based strictly on documented evidence."

        let taskPrompt = """
            ## Task: Generate Project Content

            Generate content for this project entry based on documented evidence.

            ## Context

            \(taskContext)
            \(voiceCueBlock(context))

            ## Requirements

            Generate:
            1. A description (2-3 sentences) explaining the project's purpose and your role
            2. 2-\(config.options.maxHighlightsPerEntry) highlights showing key achievements or contributions
            3. Relevant keywords/technologies

            ## CONSTRAINTS

            1. Use ONLY facts from the provided Knowledge Cards
            2. Do NOT invent metrics, percentages, or quantitative claims
            3. Match the candidate's writing voice from the samples
            4. Avoid generic resume phrases
            \(config.options.bulletConstraintText)

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

        let entry = try findTimelineEntry(id: targetId, in: context)
        let taskContext = buildTaskContext(entry: entry, context: context)
        let regenerationContext = buildRegenerationContext(originalContent: originalContent, feedback: feedback)

        let systemPrompt = "You are a professional resume writer. Generate project content based strictly on documented evidence."

        let taskPrompt = """
            ## Task: Revise Project Content

            Revise the content for this project entry based on user feedback.

            ## Context

            \(taskContext)
            \(voiceCueBlock(context))

            \(regenerationContext)

            ## Requirements

            Generate:
            1. A description (2-3 sentences) explaining the project's purpose and your role
            2. 2-\(config.options.maxHighlightsPerEntry) highlights showing key achievements or contributions
            3. Relevant keywords/technologies

            ## CONSTRAINTS

            1. Use ONLY facts from the provided Knowledge Cards
            2. Do NOT invent metrics, percentages, or quantitative claims
            3. Match the candidate's writing voice from the samples
            4. Avoid generic resume phrases
            \(config.options.bulletConstraintText)
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

    private func buildTaskContext(entry: JSON, context: SeedGenerationContext) -> String {
        var lines: [String] = []

        let projectName = entry["name"].stringValue

        lines.append("### Project Details")
        if !projectName.isEmpty { lines.append("**Name:** \(projectName)") }
        if let description = entry["description"].string, !description.isEmpty { lines.append("**Description:** \(description)") }
        if let startDate = entry["startDate"].string, !startDate.isEmpty { lines.append("**Start Date:** \(startDate)") }
        if let endDate = entry["endDate"].string, !endDate.isEmpty { lines.append("**End Date:** \(endDate)") }
        if let url = entry["url"].string, !url.isEmpty { lines.append("**URL:** \(url)") }

        if let existingHighlights = entry["highlights"].array, !existingHighlights.isEmpty {
            lines.append("\n### Existing Highlights")
            for highlight in existingHighlights {
                lines.append("- \(highlight.stringValue)")
            }
        }

        // Pull KC evidence matching the project by name so highlights are
        // grounded in documented facts rather than the entry stub alone.
        if !projectName.isEmpty {
            let relevantKCs = context.knowledgeCards.filter { kc in
                kc.narrative.localizedCaseInsensitiveContains(projectName) ||
                kc.title.localizedCaseInsensitiveContains(projectName)
            }
            if !relevantKCs.isEmpty {
                lines.append("\n### Relevant Knowledge Cards")
                for kc in relevantKCs.prefix(3) {
                    lines.append("\n#### \(kc.title)")
                    lines.append(String(kc.narrative.prefix(500)) + (kc.narrative.count > 500 ? "..." : ""))
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
