//
//  ObjectiveGenerator.swift
//  Sprung
//
//  Generator for professional objective/summary.
//  Creates a single task that generates a compelling 3-5 sentence
//  professional summary based on the full context.
//
//  Note: The professional summary is stored in ApplicantProfileDraft.summary,
//  not in ExperienceDefaults. This generator produces content that will be
//  applied to the applicant profile.
//

import Foundation
import SwiftyJSON

// MARK: - Response Types

private struct ObjectiveResponse: Codable {
    let summary: String
}

/// Generates professional objective/summary for resume.
/// Creates a single task producing a 3-5 sentence summary.
@MainActor
final class ObjectiveGenerator: BaseSectionGenerator {
    override var displayName: String { "Professional Summary" }

    init() {
        super.init(sectionKey: .work)  // Placeholder - objective doesn't have its own section key
    }

    // MARK: - Task Creation

    override func createTasks(context: SeedGenerationContext) -> [GenerationTask] {
        // Single task for the objective
        [GenerationTask(
            id: UUID(),
            section: .work, // Placeholder
            targetId: "objective",
            displayName: "Professional Summary",
            status: .pending
        )]
    }

    // MARK: - Execution

    override func execute(
        task: GenerationTask,
        context: SeedGenerationContext,
        preamble: String,
        llmFacade: LLMFacade,
        modelId: String
    ) async throws -> GeneratedContent {
        let taskContext = buildTaskContext(context: context)

        let systemPrompt = "You are a professional resume writer. Generate a compelling professional summary."

        let fullPrompt = """
            \(preamble)

            ---

            ## Task: Generate Professional Summary

            Create a compelling professional summary (also called an objective statement)
            that will appear at the top of the resume.

            ## Context

            \(taskContext)

            ## Instructions

            Generate a professional summary that:
            - Is 3-5 sentences (60-100 words)
            - Highlights the candidate's core value proposition
            - Mentions key skills and areas of expertise
            - Conveys professional identity and career focus
            - Uses first person implied (no "I" or "my")
            - Matches the candidate's voice and communication style

            Return your response as JSON:
            {
                "summary": "The professional summary text"
            }
            """

        let response: ObjectiveResponse = try await llmFacade.executeStructuredWithDictionarySchema(
            prompt: "\(systemPrompt)\n\n\(fullPrompt)",
            modelId: modelId,
            as: ObjectiveResponse.self,
            schema: [
                "type": "object",
                "properties": [
                    "summary": ["type": "string"]
                ],
                "required": ["summary"]
            ],
            schemaName: "objective"
        )

        return GeneratedContent(
            type: .objective(summary: response.summary)
        )
    }

    // MARK: - Apply to Defaults

    override func apply(content: GeneratedContent, to defaults: inout ExperienceDefaults) {
        // Note: Professional summary is stored in ApplicantProfileDraft, not ExperienceDefaults
        // The orchestrator should handle updating the profile separately
        guard case .objective(let summary) = content.type else {
            Logger.warning("ObjectiveGenerator: content type mismatch", category: .ai)
            return
        }
        Logger.info("Generated professional summary: \(summary.prefix(50))...", category: .ai)
        // The actual application to ApplicantProfile happens elsewhere
    }

    // MARK: - Context Building

    private func buildTaskContext(context: SeedGenerationContext) -> String {
        var lines: [String] = []

        // Profile summary
        lines.append("### Candidate Profile")
        let profile = context.applicantProfile
        if !profile.name.isEmpty { lines.append("**Name:** \(profile.name)") }

        // Build location string from components
        var locationParts: [String] = []
        if !profile.city.isEmpty { locationParts.append(profile.city) }
        if !profile.state.isEmpty { locationParts.append(profile.state) }
        if !locationParts.isEmpty {
            lines.append("**Location:** \(locationParts.joined(separator: ", "))")
        }

        // Dossier insights
        if let dossier = context.dossier {
            if let jobContext = dossier["jobSearchContext"].string, !jobContext.isEmpty {
                lines.append("\n### Job Search Focus")
                lines.append(jobContext)
            }

            if let strengths = dossier["strengthsToEmphasize"].string, !strengths.isEmpty {
                lines.append("\n### Key Strengths")
                let truncated = String(strengths.prefix(500))
                lines.append(truncated + (strengths.count > 500 ? "..." : ""))
            }
        }

        // Recent work experience (for context)
        let workEntries = context.workEntries
        if !workEntries.isEmpty {
            lines.append("\n### Recent Experience")
            for entry in workEntries.prefix(3) {
                let title = entry["title"].stringValue
                let company = entry["company"].stringValue
                if !title.isEmpty || !company.isEmpty {
                    lines.append("- \(title)\(!company.isEmpty ? " at \(company)" : "")")
                }
            }
        }

        // Top skills
        if !context.skills.isEmpty {
            lines.append("\n### Top Skills")
            let topSkills = context.skills.prefix(10).map { $0.canonical }
            lines.append(topSkills.joined(separator: ", "))
        }

        return lines.joined(separator: "\n")
    }
}
