//
//  WorkHighlightsGenerator.swift
//  Sprung
//
//  Generator for work experience highlights.
//  Creates one task per job, generating 3-4 bullet point highlights
//  based on timeline entries and relevant knowledge cards.
//

import Foundation
import SwiftyJSON

// MARK: - Response Types

private struct WorkHighlightsResponse: Codable {
    let highlights: [String]
}

/// Generates work experience highlights for resume work section.
/// For each work timeline entry, generates 3-4 impactful bullet points
/// using evidence from knowledge cards.
@MainActor
final class WorkHighlightsGenerator: BaseSectionGenerator {
    override var displayName: String { "Work Highlights" }

    init() {
        super.init(sectionKey: .work)
    }

    // MARK: - Task Creation

    override func createTasks(context: SeedGenerationContext) -> [GenerationTask] {
        let workEntries = context.timelineEntries(for: .work)

        return workEntries.compactMap { entry -> GenerationTask? in
            guard let id = entry["id"].string else { return nil }

            let company = entry["company"].stringValue
            let title = entry["title"].stringValue
            let displayName = company.isEmpty ? title : "\(title) at \(company)"

            return GenerationTask(
                id: UUID(),
                section: .work,
                targetId: id,
                displayName: "Work: \(displayName)",
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
            throw GeneratorError.missingContext("No targetId for work task")
        }

        let entry = try findTimelineEntry(id: targetId, in: context)
        let relevantKCs = context.relevantKCs(for: entry)

        let taskContext = buildTaskContext(entry: entry, kcs: relevantKCs)

        let systemPrompt = "You are a professional resume writer. Generate work highlights based strictly on documented evidence."

        let taskPrompt = """
            ## Task: Generate Work Highlights

            Generate resume bullet points for this position.

            ## Position Context

            \(taskContext)

            ## Requirements

            Generate 3-4 bullet points that:

            1. **Use ONLY facts from the Knowledge Cards** - Every claim must have evidence in the KCs provided above

            2. **Match the candidate's voice** - Write in their style as shown in the writing samples, not generic resume-speak

            3. **Describe work narratively** - Focus on what was built, created, discovered, or accomplished

            4. **Vary sentence structure** - Don't start every bullet the same way

            ## FORBIDDEN

            - Inventing metrics, percentages, or numbers not explicitly stated in KCs
            - Generic phrases: "spearheaded", "leveraged", "drove results", "cross-functional"
            - Vague impact claims: "significantly improved", "enhanced capabilities", "streamlined processes"
            - Formulaic structure: "[Verb] [thing] resulting in [X]% improvement"

            ## Output Format

            Return JSON with 3-4 bullets:
            {
                "highlights": ["First bullet point", "Second bullet point", "Third bullet point", "Fourth bullet point (optional)"]
            }
            """

        let response: WorkHighlightsResponse = try await executeStructuredRequest(
            taskPrompt: taskPrompt,
            systemPrompt: systemPrompt,
            config: config,
            responseType: WorkHighlightsResponse.self,
            schema: [
                "type": "object",
                "properties": [
                    "highlights": ["type": "array", "items": ["type": "string"]]
                ],
                "required": ["highlights"],
                "additionalProperties": false
            ],
            schemaName: "work_highlights"
        )

        return GeneratedContent(
            type: .workHighlights(targetId: targetId, highlights: response.highlights)
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
            throw GeneratorError.missingContext("No targetId for work task")
        }

        let entry = try findTimelineEntry(id: targetId, in: context)
        let relevantKCs = context.relevantKCs(for: entry)
        let taskContext = buildTaskContext(entry: entry, kcs: relevantKCs)
        let regenerationContext = buildRegenerationContext(originalContent: originalContent, feedback: feedback)

        let systemPrompt = "You are a professional resume writer. Generate work highlights based strictly on documented evidence."

        let taskPrompt = """
            ## Task: Revise Work Highlights

            Revise the resume bullet points for this position based on user feedback.

            ## Position Context

            \(taskContext)

            \(regenerationContext)

            ## Requirements

            Generate 3-4 bullet points that:

            1. **Use ONLY facts from the Knowledge Cards** - Every claim must have evidence in the KCs provided above

            2. **Match the candidate's voice** - Write in their style as shown in the writing samples, not generic resume-speak

            3. **Describe work narratively** - Focus on what was built, created, discovered, or accomplished

            4. **Vary sentence structure** - Don't start every bullet the same way

            ## FORBIDDEN

            - Inventing metrics, percentages, or numbers not explicitly stated in KCs
            - Generic phrases: "spearheaded", "leveraged", "drove results", "cross-functional"
            - Vague impact claims: "significantly improved", "enhanced capabilities", "streamlined processes"
            - Formulaic structure: "[Verb] [thing] resulting in [X]% improvement"
            """

        let response: WorkHighlightsResponse = try await executeStructuredRequest(
            taskPrompt: taskPrompt,
            systemPrompt: systemPrompt,
            config: config,
            responseType: WorkHighlightsResponse.self,
            schema: [
                "type": "object",
                "properties": [
                    "highlights": ["type": "array", "items": ["type": "string"]]
                ],
                "required": ["highlights"],
                "additionalProperties": false
            ],
            schemaName: "work_highlights"
        )

        return GeneratedContent(
            type: .workHighlights(targetId: targetId, highlights: response.highlights)
        )
    }

    // MARK: - Apply to Defaults

    override func apply(content: GeneratedContent, to defaults: inout ExperienceDefaults) {
        guard case .workHighlights(let targetId, let highlights) = content.type else {
            Logger.warning("WorkHighlightsGenerator: content type mismatch", category: .ai)
            return
        }

        // Find matching work entry in defaults and update highlights
        if let index = defaults.work.firstIndex(where: { $0.id.uuidString == targetId }) {
            // Convert strings to HighlightDraft
            defaults.work[index].highlights = highlights.map { HighlightDraft(text: $0) }
            Logger.info("Applied \(highlights.count) highlights to work entry: \(targetId)", category: .ai)
        } else {
            Logger.warning("Work entry not found for targetId: \(targetId)", category: .ai)
        }
    }

    // MARK: - Prompt Building

    override func buildSectionPrompt() -> String {
        """
        Generate resume bullet points for a work experience entry.

        Your bullets should:
        - Describe specific work and contributions
        - Use the candidate's natural voice (see writing samples)
        - Include only facts that appear in the Knowledge Cards
        - Frame achievements narratively rather than with fabricated metrics

        Do NOT:
        - Invent percentages or quantitative improvements
        - Use generic corporate/LinkedIn language
        - Write every bullet with the same structure
        """
    }

    private func buildTaskContext(entry: JSON, kcs: [KnowledgeCard]) -> String {
        var lines: [String] = []

        // Position details
        lines.append("### Position Details")
        if let title = entry["title"].string { lines.append("**Title:** \(title)") }
        if let company = entry["company"].string { lines.append("**Company:** \(company)") }
        if let startDate = entry["startDate"].string { lines.append("**Start Date:** \(startDate)") }
        if let endDate = entry["endDate"].string { lines.append("**End Date:** \(endDate)") }
        if let location = entry["location"].string { lines.append("**Location:** \(location)") }
        if let description = entry["description"].string, !description.isEmpty {
            lines.append("\n**Description:** \(description)")
        }

        // Existing highlights (if any, for context)
        if let existingHighlights = entry["highlights"].array, !existingHighlights.isEmpty {
            lines.append("\n### Existing Highlights (from timeline)")
            for highlight in existingHighlights {
                lines.append("- \(highlight.stringValue)")
            }
        }

        // Relevant knowledge cards
        if !kcs.isEmpty {
            lines.append("\n### Relevant Evidence (from Knowledge Cards)")
            for kc in kcs.prefix(5) {
                lines.append("\n**\(kc.title)**")
                // Use facts if available
                let kcFacts = kc.facts
                if !kcFacts.isEmpty {
                    for fact in kcFacts.prefix(3) {
                        lines.append("- \(fact.statement)")
                    }
                }
                // Also include suggested bullets
                let bullets = kc.suggestedBullets
                if !bullets.isEmpty {
                    for bullet in bullets.prefix(2) {
                        lines.append("- \(bullet)")
                    }
                }
            }
        }

        return lines.joined(separator: "\n")
    }
}
