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
        preamble: String,
        llmService: any LLMServiceProtocol
    ) async throws -> GeneratedContent {
        guard let targetId = task.targetId else {
            throw GeneratorError.missingContext("No targetId for work task")
        }

        let entry = try findTimelineEntry(id: targetId, in: context)
        let relevantKCs = context.relevantKCs(for: entry)

        let taskContext = buildTaskContext(entry: entry, kcs: relevantKCs)

        let fullPrompt = """
            \(preamble)

            ---

            ## Task: Generate Work Highlights

            Generate compelling bullet point highlights for this work experience.

            ## Context for This Position

            \(taskContext)

            ## Instructions

            Generate 3-4 bullet point highlights for this position.
            Each bullet should:
            - Start with a strong action verb
            - Include specific, quantifiable achievements when possible
            - Be 1-2 sentences (15-25 words)
            - Highlight impact and results, not just duties

            Return your response as JSON in this format:
            {
                "highlights": ["bullet 1", "bullet 2", "bullet 3", "bullet 4"]
            }
            """

        let response = try await llmService.generateJSON(
            systemPrompt: "You are a professional resume writer. Generate impactful work highlights.",
            userPrompt: fullPrompt,
            schema: """
                {
                    "type": "object",
                    "properties": {
                        "highlights": {
                            "type": "array",
                            "items": {"type": "string"},
                            "minItems": 3,
                            "maxItems": 4
                        }
                    },
                    "required": ["highlights"]
                }
                """,
            maxTokens: 500
        )

        let highlights = response["highlights"].arrayValue.map { $0.stringValue }

        return GeneratedContent(
            type: .workHighlights(targetId: targetId, highlights: highlights),
            rawJSON: response
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
        Generate compelling bullet point highlights for a work experience entry.

        Your highlights should:
        - Demonstrate value delivered to the organization
        - Use industry-appropriate terminology
        - Quantify impact where evidence supports it
        - Avoid generic phrases like "responsible for" or "worked on"
        - Be tailored to the candidate's voice and style
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
