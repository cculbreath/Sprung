//
//  TitleOptionsGenerator.swift
//  Sprung
//
//  Generator for professional title sets.
//  Creates 3-5 title set variations the user can choose from.
//

import Foundation

// MARK: - Response Types

private struct TitleSetsResponse: Codable {
    let sets: [TitleSetDTO]

    struct TitleSetDTO: Codable {
        let titles: [String]  // Exactly 4 titles
        let emphasis: String  // technical, research, leadership, balanced
        let suggestedFor: [String]
    }
}

/// Generates professional title sets for resume header.
/// Analyzes experience to suggest 3-5 appropriate title combinations.
@MainActor
final class TitleOptionsGenerator: BaseSectionGenerator {
    override var displayName: String { "Professional Titles" }

    init() {
        super.init(sectionKey: .custom)
    }

    // MARK: - Task Creation

    /// Creates a single task for title generation (aggregate operation)
    override func createTasks(context: SeedGenerationContext) -> [GenerationTask] {
        return [
            GenerationTask(
                id: UUID(),
                section: .custom,
                targetId: nil,
                displayName: "Generate Title Options",
                status: .pending
            )
        ]
    }

    // MARK: - Execution

    override func execute(
        task: GenerationTask,
        context: SeedGenerationContext,
        config: GeneratorExecutionConfig
    ) async throws -> GeneratedContent {
        let taskContext = buildTaskContext(context: context)

        let systemPrompt = """
            You are an expert resume writer crafting professional title sets.
            """

        let taskPrompt = """
            ## Task: Generate Professional Title Sets

            Create 3-5 title sets for the resume header. Each set should have exactly 4 titles
            that work together as a cohesive professional identity.

            ## Context

            \(taskContext)

            ## Instructions

            1. Generate 3-5 distinct title sets, each with exactly 4 titles
            2. Each title should be a single word or short phrase (1-3 words max)
            3. Titles should reflect the candidate's expertise areas
            4. Include sets with different emphasis (technical, leadership, research)
            5. Suggest what job types each set works well for

            Example format for titles array: ["Physicist", "Developer", "Educator", "Innovator"]

            Return JSON with your title sets.
            """

        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "sets": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": [
                            "titles": ["type": "array", "items": ["type": "string"]],
                            "emphasis": ["type": "string"],
                            "suggestedFor": ["type": "array", "items": ["type": "string"]]
                        ],
                        "required": ["titles", "emphasis", "suggestedFor"]
                    ]
                ]
            ],
            "required": ["sets"]
        ]

        let response: TitleSetsResponse = try await executeStructuredRequest(
            taskPrompt: taskPrompt,
            systemPrompt: systemPrompt,
            config: config,
            responseType: TitleSetsResponse.self,
            schema: schema,
            schemaName: "title_sets"
        )

        let titleSets = response.sets.map { dto -> TitleSet in
            let emphasis = TitleEmphasis(rawValue: dto.emphasis.lowercased()) ?? .balanced
            return TitleSet(
                titles: dto.titles,
                emphasis: emphasis,
                suggestedFor: dto.suggestedFor
            )
        }

        return GeneratedContent(
            type: .titleSets(titleSets)
        )
    }

    // MARK: - Apply to Defaults

    override func apply(content: GeneratedContent, to defaults: inout ExperienceDefaults) {
        guard case .titleSets(let titleSets) = content.type else {
            Logger.warning("TitleOptionsGenerator: content type mismatch", category: .ai)
            return
        }

        // Title sets are stored in InferenceGuidance, not ExperienceDefaults
        // This apply method is a no-op since titles are handled separately
        Logger.info("Generated \(titleSets.count) title sets (stored separately)", category: .ai)
    }

    // MARK: - Context Building

    private func buildTaskContext(context: SeedGenerationContext) -> String {
        var lines: [String] = []

        // Recent job titles
        let workEntries = context.timelineEntries(for: .work)
        if !workEntries.isEmpty {
            lines.append("### Recent Positions")
            for entry in workEntries.prefix(5) {
                let title = entry["title"].stringValue
                let company = entry["company"].stringValue
                if !title.isEmpty {
                    lines.append("- \(title)\(company.isEmpty ? "" : " at \(company)")")
                }
            }
        }

        // Top skills
        if !context.skills.isEmpty {
            lines.append("\n### Top Skills")
            let topSkills = context.skills.prefix(15).map { $0.canonical }
            lines.append(topSkills.joined(separator: ", "))
        }

        // Education
        let eduEntries = context.timelineEntries(for: .education)
        if !eduEntries.isEmpty {
            lines.append("\n### Education")
            for entry in eduEntries.prefix(2) {
                let studyType = entry["studyType"].stringValue
                let area = entry["area"].stringValue
                if !studyType.isEmpty || !area.isEmpty {
                    lines.append("- \(studyType) in \(area)")
                }
            }
        }

        // Existing summary if available
        if !context.applicantProfile.summary.isEmpty {
            lines.append("\n### Current Summary")
            lines.append(context.applicantProfile.summary)
        }

        return lines.joined(separator: "\n")
    }
}
