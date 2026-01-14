//
//  EducationGenerator.swift
//  Sprung
//
//  Generator for education section content.
//  Creates one task per education entry, generating descriptions
//  and relevant coursework.
//

import Foundation
import SwiftyJSON

// MARK: - Response Types

private struct EducationResponse: Codable {
    let description: String
    let courses: [String]
}

/// Generates education section content.
/// For each education timeline entry, generates description and coursework.
@MainActor
final class EducationGenerator: BaseSectionGenerator {
    override var displayName: String { "Education" }

    init() {
        super.init(sectionKey: .education)
    }

    // MARK: - Task Creation

    override func createTasks(context: SeedGenerationContext) -> [GenerationTask] {
        let eduEntries = context.timelineEntries(for: .education)

        return eduEntries.compactMap { entry -> GenerationTask? in
            guard let id = entry["id"].string else { return nil }

            let institution = entry["institution"].stringValue
            let studyType = entry["studyType"].stringValue
            let displayName = institution.isEmpty ? studyType : "\(studyType) at \(institution)"

            return GenerationTask(
                id: UUID(),
                section: .education,
                targetId: id,
                displayName: "Education: \(displayName)",
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
            throw GeneratorError.missingContext("No targetId for education task")
        }

        let entry = try findTimelineEntry(id: targetId, in: context)
        let relevantKCs = context.relevantKCs(for: entry)

        let taskContext = buildTaskContext(entry: entry, kcs: relevantKCs, skills: context.skills)

        let systemPrompt = "You are a professional resume writer. Generate education content based strictly on documented evidence."

        let taskPrompt = """
            ## Task: Generate Education Content

            Generate content for this education entry based on documented evidence.

            ## Context for This Entry

            \(taskContext)

            ## Requirements

            Generate:
            1. A brief description (1-2 sentences) highlighting the educational experience
            2. A list of 3-5 relevant courses that demonstrate skills valuable to employers

            ## CONSTRAINTS

            1. Use ONLY facts from the provided Knowledge Cards
            2. Do NOT invent metrics, percentages, or quantitative claims
            3. Match the candidate's writing voice from the samples
            4. Avoid generic resume phrases

            ## FORBIDDEN

            - Fabricated numbers ("increased by X%", "reduced by Y%")
            - Generic phrases ("spearheaded", "leveraged", "drove")
            - Vague claims ("significantly improved", "enhanced")

            Return your response as JSON:
            {
                "description": "Brief description of the educational experience",
                "courses": ["Course 1", "Course 2", "Course 3"]
            }
            """

        let response: EducationResponse = try await executeStructuredRequest(
            taskPrompt: taskPrompt,
            systemPrompt: systemPrompt,
            config: config,
            responseType: EducationResponse.self,
            schema: [
                "type": "object",
                "properties": [
                    "description": ["type": "string"],
                    "courses": ["type": "array", "items": ["type": "string"]]
                ],
                "required": ["description", "courses"]
            ],
            schemaName: "education"
        )

        return GeneratedContent(
            type: .educationDescription(
                targetId: targetId,
                description: response.description,
                courses: response.courses
            )
        )
    }

    // MARK: - Apply to Defaults

    override func apply(content: GeneratedContent, to defaults: inout ExperienceDefaults) {
        guard case .educationDescription(let targetId, let description, let courses) = content.type else {
            Logger.warning("EducationGenerator: content type mismatch", category: .ai)
            return
        }

        if let index = defaults.education.firstIndex(where: { $0.id.uuidString == targetId }) {
            // Convert strings to CourseDraft
            // Note: EducationExperienceDraft doesn't have a description property,
            // so we only update courses. Description is logged for reference.
            defaults.education[index].courses = courses.map { CourseDraft(name: $0) }
            Logger.info("Applied education content (\(courses.count) courses) to entry: \(targetId). Description: \(description.prefix(50))...", category: .ai)
        } else {
            Logger.warning("Education entry not found for targetId: \(targetId)", category: .ai)
        }
    }

    // MARK: - Context Building

    private func buildTaskContext(entry: JSON, kcs: [KnowledgeCard], skills: [Skill]) -> String {
        var lines: [String] = []

        // Education details
        lines.append("### Education Details")
        if let institution = entry["institution"].string { lines.append("**Institution:** \(institution)") }
        if let studyType = entry["studyType"].string { lines.append("**Degree Type:** \(studyType)") }
        if let area = entry["area"].string { lines.append("**Field of Study:** \(area)") }
        if let startDate = entry["startDate"].string { lines.append("**Start Date:** \(startDate)") }
        if let endDate = entry["endDate"].string { lines.append("**End Date:** \(endDate)") }
        if let score = entry["score"].string { lines.append("**GPA/Score:** \(score)") }

        // Existing courses (if any)
        if let existingCourses = entry["courses"].array, !existingCourses.isEmpty {
            lines.append("\n### Known Courses")
            for course in existingCourses {
                lines.append("- \(course.stringValue)")
            }
        }

        // Relevant skills that might have been developed during education
        let relevantSkills = skills.filter { skill in
            skill.canonical.lowercased().contains("programming") ||
            skill.canonical.lowercased().contains("analysis") ||
            skill.canonical.lowercased().contains("research")
        }

        if !relevantSkills.isEmpty {
            lines.append("\n### Related Skills (from skill bank)")
            for skill in relevantSkills.prefix(10) {
                lines.append("- \(skill.canonical)")
            }
        }

        // Relevant knowledge cards
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
