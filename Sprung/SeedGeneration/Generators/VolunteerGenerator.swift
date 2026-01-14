//
//  VolunteerGenerator.swift
//  Sprung
//
//  Generator for volunteer experience section content.
//  Creates one task per volunteer entry, generating descriptions and highlights.
//

import Foundation
import SwiftyJSON

// MARK: - Response Types

private struct VolunteerResponse: Codable {
    let summary: String
    let highlights: [String]
}

/// Generates volunteer experience content.
/// For each volunteer timeline entry, generates description and highlights.
@MainActor
final class VolunteerGenerator: BaseSectionGenerator {
    override var displayName: String { "Volunteer Experience" }

    init() {
        super.init(sectionKey: .volunteer)
    }

    // MARK: - Task Creation

    override func createTasks(context: SeedGenerationContext) -> [GenerationTask] {
        let volunteerEntries = context.timelineEntries(for: .volunteer)

        return volunteerEntries.compactMap { entry -> GenerationTask? in
            guard let id = entry["id"].string else { return nil }

            let organization = entry["organization"].stringValue
            let position = entry["position"].stringValue
            let displayName = organization.isEmpty ? position : "\(position) at \(organization)"

            return GenerationTask(
                id: UUID(),
                section: .volunteer,
                targetId: id,
                displayName: "Volunteer: \(displayName)",
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
            throw GeneratorError.missingContext("No targetId for volunteer task")
        }

        let entry = try findTimelineEntry(id: targetId, in: context)
        let relevantKCs = context.relevantKCs(for: entry)

        let taskContext = buildTaskContext(entry: entry, kcs: relevantKCs)

        let systemPrompt = "You are a professional resume writer. Generate volunteer experience content that showcases leadership and impact."

        let taskPrompt = """
            ## Task: Generate Volunteer Experience Content

            Generate compelling content for this volunteer experience that demonstrates
            leadership, impact, and transferable skills.

            ## Context for This Entry

            \(taskContext)

            ## Instructions

            Generate:
            1. A summary (1-2 sentences) describing the volunteer role and its impact
            2. 2-3 highlight bullets showcasing achievements and contributions

            Return your response as JSON:
            {
                "summary": "Brief summary of the volunteer experience",
                "highlights": ["Highlight 1", "Highlight 2", "Highlight 3"]
            }
            """

        let response: VolunteerResponse = try await executeStructuredRequest(
            taskPrompt: taskPrompt,
            systemPrompt: systemPrompt,
            config: config,
            responseType: VolunteerResponse.self,
            schema: [
                "type": "object",
                "properties": [
                    "summary": ["type": "string"],
                    "highlights": ["type": "array", "items": ["type": "string"]]
                ],
                "required": ["summary", "highlights"]
            ],
            schemaName: "volunteer"
        )

        return GeneratedContent(
            type: .volunteerDescription(
                targetId: targetId,
                summary: response.summary,
                highlights: response.highlights
            )
        )
    }

    // MARK: - Apply to Defaults

    override func apply(content: GeneratedContent, to defaults: inout ExperienceDefaults) {
        guard case .volunteerDescription(let targetId, let summary, let highlights) = content.type else {
            Logger.warning("VolunteerGenerator: content type mismatch", category: .ai)
            return
        }

        if let index = defaults.volunteer.firstIndex(where: { $0.id.uuidString == targetId }) {
            defaults.volunteer[index].summary = summary
            // Convert strings to VolunteerHighlightDraft
            defaults.volunteer[index].highlights = highlights.map { VolunteerHighlightDraft(text: $0) }
            Logger.info("Applied volunteer content to entry: \(targetId)", category: .ai)
        } else {
            Logger.warning("Volunteer entry not found for targetId: \(targetId)", category: .ai)
        }
    }

    // MARK: - Context Building

    private func buildTaskContext(entry: JSON, kcs: [KnowledgeCard]) -> String {
        var lines: [String] = []

        lines.append("### Volunteer Details")
        if let organization = entry["organization"].string { lines.append("**Organization:** \(organization)") }
        if let position = entry["position"].string { lines.append("**Position:** \(position)") }
        if let startDate = entry["startDate"].string { lines.append("**Start Date:** \(startDate)") }
        if let endDate = entry["endDate"].string { lines.append("**End Date:** \(endDate)") }
        if let url = entry["url"].string { lines.append("**URL:** \(url)") }
        if let summary = entry["summary"].string, !summary.isEmpty {
            lines.append("\n**Summary:** \(summary)")
        }

        if let existingHighlights = entry["highlights"].array, !existingHighlights.isEmpty {
            lines.append("\n### Existing Highlights")
            for highlight in existingHighlights {
                lines.append("- \(highlight.stringValue)")
            }
        }

        if !kcs.isEmpty {
            lines.append("\n### Relevant Evidence")
            for kc in kcs.prefix(3) {
                lines.append("\n**\(kc.title)**")
                let kcFacts = kc.facts
                if !kcFacts.isEmpty {
                    for fact in kcFacts.prefix(2) {
                        lines.append("- \(fact.statement)")
                    }
                }
            }
        }

        return lines.joined(separator: "\n")
    }
}
