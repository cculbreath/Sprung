//
//  SkillsGroupingGenerator.swift
//  Sprung
//
//  Generator for organizing skills into themed groups.
//  Creates 4-6 skill categories from the skill bank for resume display.
//

import Foundation

// MARK: - Response Types

private struct SkillGroupsResponse: Codable {
    let groups: [SkillGroupDTO]

    struct SkillGroupDTO: Codable {
        let name: String
        let skills: [String]
    }
}

/// Generates skill groupings for resume display.
/// Takes the flat skill bank and organizes into 4-6 themed categories.
@MainActor
final class SkillsGroupingGenerator: BaseSectionGenerator {
    override var displayName: String { "Skills" }

    init() {
        super.init(sectionKey: .skills)
    }

    // MARK: - Task Creation

    /// Creates a single task for skill grouping (aggregate operation)
    override func createTasks(context: SeedGenerationContext) -> [GenerationTask] {
        guard !context.skills.isEmpty else {
            return []
        }

        return [
            GenerationTask(
                id: UUID(),
                section: .skills,
                targetId: nil,
                displayName: "Organize Skills into Categories",
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
        let skillList = context.skills.map { $0.canonical }

        let systemPrompt = """
            You are an expert resume writer organizing skills into clear, impactful categories.
            """

        let taskPrompt = """
            ## Task: Organize Skills into Categories

            Create 4-6 skill categories that would look professional on a resume.

            ## Available Skills

            \(skillList.joined(separator: ", "))

            ## Instructions

            1. Group related skills into 4-6 categories
            2. Each category should have a clear, professional name
            3. Each category should contain 4-8 skills
            4. Use only skills from the list above - do not invent new skills
            5. Order skills within each group by relevance/importance
            6. Categories should cover different aspects (e.g., Technical, Leadership, Tools, etc.)

            Return JSON in this exact format:
            {
                "groups": [
                    {
                        "name": "Category Name",
                        "skills": ["skill1", "skill2", "skill3"]
                    }
                ]
            }
            """

        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "groups": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": [
                            "name": ["type": "string"],
                            "skills": ["type": "array", "items": ["type": "string"]]
                        ],
                        "required": ["name", "skills"],
                        "additionalProperties": false
                    ]
                ]
            ],
            "required": ["groups"],
            "additionalProperties": false
        ]

        let response: SkillGroupsResponse = try await executeStructuredRequest(
            taskPrompt: taskPrompt,
            systemPrompt: systemPrompt,
            config: config,
            responseType: SkillGroupsResponse.self,
            schema: schema,
            schemaName: "skill_groups"
        )

        let skillGroups = response.groups.map { group in
            SkillGroup(name: group.name, keywords: group.skills)
        }

        return GeneratedContent(
            type: .skillGroups(skillGroups)
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
        let skillList = context.skills.map { $0.canonical }
        let regenerationContext = buildRegenerationContext(originalContent: originalContent, feedback: feedback)

        let systemPrompt = "You are an expert resume writer organizing skills into clear, impactful categories."

        let taskPrompt = """
            ## Task: Revise Skill Categories

            Revise the skill categories based on user feedback.

            ## Available Skills

            \(skillList.joined(separator: ", "))

            \(regenerationContext)

            ## Instructions

            1. Group related skills into 4-6 categories
            2. Each category should have a clear, professional name
            3. Each category should contain 4-8 skills
            4. Use only skills from the list above - do not invent new skills
            5. Order skills within each group by relevance/importance
            6. Categories should cover different aspects (e.g., Technical, Leadership, Tools, etc.)
            """

        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "groups": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": [
                            "name": ["type": "string"],
                            "skills": ["type": "array", "items": ["type": "string"]]
                        ],
                        "required": ["name", "skills"],
                        "additionalProperties": false
                    ]
                ]
            ],
            "required": ["groups"],
            "additionalProperties": false
        ]

        let response: SkillGroupsResponse = try await executeStructuredRequest(
            taskPrompt: taskPrompt,
            systemPrompt: systemPrompt,
            config: config,
            responseType: SkillGroupsResponse.self,
            schema: schema,
            schemaName: "skill_groups"
        )

        let skillGroups = response.groups.map { group in
            SkillGroup(name: group.name, keywords: group.skills)
        }

        return GeneratedContent(
            type: .skillGroups(skillGroups)
        )
    }

    // MARK: - Apply to Defaults

    override func apply(content: GeneratedContent, to defaults: inout ExperienceDefaults) {
        guard case .skillGroups(let groups) = content.type else {
            Logger.warning("SkillsGroupingGenerator: content type mismatch", category: .ai)
            return
        }

        // Convert to SkillExperienceDraft format
        defaults.skills = groups.map { group in
            SkillExperienceDraft(
                name: group.name,
                keywords: group.keywords.map { KeywordDraft(keyword: $0) }
            )
        }

        Logger.info("Applied \(groups.count) skill groups to defaults", category: .ai)
    }
}
