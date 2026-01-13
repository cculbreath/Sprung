//
//  TitleSetService.swift
//  Sprung
//
//  Generates identity title sets from skill bank data.
//

import Foundation

/// Generates identity title sets from skill bank.
/// Called during Phase 4 for interactive curation.
@MainActor
final class TitleSetService {
    private var llmFacade: LLMFacade?

    private var modelId: String {
        UserDefaults.standard.string(forKey: "titleSetModelId") ?? DefaultModels.gemini
    }

    init(llmFacade: LLMFacade?) {
        self.llmFacade = llmFacade
    }

    func updateLLMFacade(_ facade: LLMFacade?) {
        self.llmFacade = facade
    }

    // MARK: - Skill Bank Formatting

    /// Format skills into a readable context string for prompts
    private func formatSkillsContext(from skills: [Skill]) -> String {
        let grouped = Dictionary(grouping: skills, by: { $0.category })
        var sections: [String] = []

        for (category, categorySkills) in grouped.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            let skillList = categorySkills
                .sorted { $0.evidence.count > $1.evidence.count }
                .prefix(20)
                .map { skill in
                    let evidenceCount = skill.evidence.count
                    return evidenceCount > 1 ? "\(skill.canonical) (\(evidenceCount))" : skill.canonical
                }
            sections.append("**\(category.rawValue)**: \(skillList.joined(separator: ", "))")
        }

        return sections.joined(separator: "\n")
    }

    // MARK: - Title Set Generation

    /// Generate initial title sets from skill bank
    func generateInitialTitleSets(from skills: [Skill]) async throws -> TitleSetGenerationResult {
        guard let facade = llmFacade else {
            throw TitleSetError.llmNotConfigured
        }

        let skillsContext = formatSkillsContext(from: skills)

        let prompt = """
        # Identity Title Generation

        You are creating professional identity titles for a resume header. These titles appear prominently
        at the top of the resume and should capture who this person IS professionally.

        ## Applicant's Skill Bank
        (Numbers in parentheses indicate evidence strength - higher means more documented experience)

        \(skillsContext)

        ## Task

        Generate exactly 20 unique title sets. Each set contains exactly 4 professional titles that
        together paint a picture of this person's professional identity.

        ### Title Format Rules
        - Titles can be 1-2 words (e.g., "Physicist", "Software Developer", "Data Scientist")
        - IMPORTANT: Each set of 4 titles must have AT MOST 2 two-word entries (0, 1, or 2 are acceptable; 3 or 4 is NOT)
        - Use professional role nouns, not adjectives or verbs
        - Good examples: "Engineer", "Developer", "Scientist", "Architect", "Software Engineer", "Research Scientist"
        - Bad examples: "Experienced", "Leading", "Building" (these are adjectives/verbs, not identity nouns)

        ### Diversity Requirements
        - Vary the emphasis across sets: technical, research, leadership, balanced
        - Balance single-word and two-word titles, but never more than 2 two-word titles per set
        - Don't repeat the same title in the same position across all sets
        - Create sets suitable for different job types (R&D, engineering, management, etc.)

        ## Output Format

        Return JSON with this structure:
        ```json
        {
          "titleSets": [
            {
              "id": "unique-uuid",
              "titles": ["Physicist", "Software Developer", "Educator", "Maker"],
              "emphasis": "balanced",
              "suggestedFor": ["R&D", "interdisciplinary roles"],
              "isFavorite": false
            }
          ]
        }
        ```

        Generate 20 diverse, high-quality title sets.
        """

        Logger.info(
            "🏷️ Generating title sets from \(skills.count) skills",
            category: .ai
        )

        let result: TitleSetGenerationResult = try await facade.executeStructuredWithDictionarySchema(
            prompt: prompt,
            modelId: modelId,
            as: TitleSetGenerationResult.self,
            schema: TitleSetSchemas.generationSchema,
            schemaName: "title_set_generation",
            maxOutputTokens: 16384,
            backend: .gemini
        )

        Logger.info(
            "🏷️ Generated \(result.titleSets.count) title sets",
            category: .ai
        )
        return result
    }

    /// Generate additional title sets
    func generateMoreTitleSets(
        skills: [Skill],
        existingSets: [TitleSet],
        favoritedSets: [TitleSet] = [],
        count: Int = 20
    ) async throws -> [TitleSet] {
        guard let facade = llmFacade else {
            throw TitleSetError.llmNotConfigured
        }

        let skillsContext = formatSkillsContext(from: skills)
        let recentSets = existingSets.suffix(30)
        let existingList = recentSets.map { "- \($0.titles.joined(separator: " | "))" }.joined(separator: "\n")

        let preferencesSection: String
        if !favoritedSets.isEmpty {
            let favList = favoritedSets.map { "- \($0.titles.joined(separator: " | "))" }.joined(separator: "\n")
            preferencesSection = """

            ## User's Favorited Sets (generate similar styles)
            The user has selected these as favorites - use them as guidance:
            \(favList)
            """
        } else {
            preferencesSection = ""
        }

        let prompt = """
        # Generate More Title Sets

        ## Applicant's Skill Bank
        \(skillsContext)

        ## Existing Sets (DO NOT duplicate these)
        \(existingList)
        \(preferencesSection)

        ## Task
        Generate exactly \(count) NEW and UNIQUE title sets.

        ### Title Format Rules
        - Titles can be 1-2 words (e.g., "Physicist", "Software Developer", "Data Scientist")
        - IMPORTANT: Each set of 4 titles must have AT MOST 2 two-word entries (0, 1, or 2 are acceptable; 3 or 4 is NOT)
        - Use professional role nouns that describe who this person IS
        - Each set has exactly 4 titles

        ### Requirements
        - Every set must be DIFFERENT from all existing sets above
        - Vary the emphasis (technical, research, leadership, balanced)
        - Create interesting combinations that highlight different aspects of this person's background
        \(favoritedSets.isEmpty ? "" : "- Generate sets similar in style to the user's favorited sets")

        Return JSON with "sets" array containing \(count) unique TitleSet objects.
        """

        Logger.info("🏷️ Generating \(count) more title sets", category: .ai)

        struct Response: Codable {
            let sets: [TitleSet]
        }

        let response: Response = try await facade.executeStructuredWithDictionarySchema(
            prompt: prompt,
            modelId: modelId,
            as: Response.self,
            schema: TitleSetSchemas.setsOnlySchema,
            schemaName: "more_title_sets",
            maxOutputTokens: 16384,
            backend: .gemini
        )

        return response.sets
    }

    /// Generate title sets with user guidance/comment
    func generateWithGuidance(
        guidance: String,
        skills: [Skill],
        existingSets: [TitleSet],
        favoritedSets: [TitleSet] = [],
        count: Int = 10
    ) async throws -> [TitleSet] {
        guard let facade = llmFacade else {
            throw TitleSetError.llmNotConfigured
        }

        let skillsContext = formatSkillsContext(from: skills)
        let recentSets = existingSets.suffix(30)
        let existingList = recentSets.map { "- \($0.titles.joined(separator: " | "))" }.joined(separator: "\n")

        let preferencesSection: String
        if !favoritedSets.isEmpty {
            let favList = favoritedSets.map { "- \($0.titles.joined(separator: " | "))" }.joined(separator: "\n")
            preferencesSection = """

            ## User's Favorited Sets (style reference)
            \(favList)
            """
        } else {
            preferencesSection = ""
        }

        let prompt = """
        # Generate Title Sets with User Guidance

        ## USER'S REQUEST (HIGHEST PRIORITY - FOLLOW THIS)
        "\(guidance)"

        The user's guidance above is your PRIMARY directive. If they request specific titles, USE THEM.
        If they say to avoid certain words, DO NOT use those words. Their request overrides all other considerations.

        ## Applicant's Skill Bank (for context)
        \(skillsContext)

        ## Existing Sets (DO NOT duplicate these)
        \(existingList)
        \(preferencesSection)

        ## Task
        Generate exactly \(count) NEW title sets that SATISFY THE USER'S REQUEST above.

        ### Title Format Rules
        - Titles can be 1-2 words (e.g., "Physicist", "Software Developer", "Data Scientist")
        - IMPORTANT: Each set of 4 titles must have AT MOST 2 two-word entries (0, 1, or 2 are acceptable; 3 or 4 is NOT)
        - Use professional role nouns
        - Each set has exactly 4 titles

        ### Requirements
        - MOST IMPORTANT: Follow the user's guidance - if they want specific titles, include them
        - If user says to avoid certain terms, DO NOT use those terms in ANY set
        - You MAY use titles not derived from the skill bank if the user requests them
        - Each set must be different from existing sets
        - Vary emphasis where appropriate

        Return JSON with "sets" array containing \(count) unique TitleSet objects.
        """

        Logger.info("🏷️ Generating \(count) title sets with guidance: \(guidance.prefix(50))...", category: .ai)

        struct Response: Codable {
            let sets: [TitleSet]
        }

        let response: Response = try await facade.executeStructuredWithDictionarySchema(
            prompt: prompt,
            modelId: modelId,
            as: Response.self,
            schema: TitleSetSchemas.setsOnlySchema,
            schemaName: "guided_title_sets",
            maxOutputTokens: 16384,
            backend: .gemini
        )

        return response.sets
    }

    /// Generate title sets that include a user-specified title
    func generateWithSpecifiedTitle(
        specifiedTitle: String,
        skills: [Skill],
        existingSets: [TitleSet],
        count: Int = 5
    ) async throws -> [TitleSet] {
        guard let facade = llmFacade else {
            throw TitleSetError.llmNotConfigured
        }

        let skillsContext = formatSkillsContext(from: skills)
        let recentSets = existingSets.suffix(20)
        let existingList = recentSets.map { "- \($0.titles.joined(separator: " | "))" }.joined(separator: "\n")

        let prompt = """
        # Generate Title Sets with Required Title

        ## REQUIRED TITLE (must appear in every set)
        "\(specifiedTitle)"

        ## Applicant's Skill Bank (for context)
        \(skillsContext)

        ## Existing Sets (DO NOT duplicate these)
        \(existingList)

        ## Task
        Generate exactly \(count) NEW title sets where EVERY set includes "\(specifiedTitle)".

        ### Title Format Rules
        - Titles can be 1-2 words (e.g., "Physicist", "Software Developer")
        - IMPORTANT: Each set of 4 titles must have AT MOST 2 two-word entries (0, 1, or 2 are acceptable; 3 or 4 is NOT)
        - Each set has exactly 4 titles
        - "\(specifiedTitle)" MUST be one of the 4 titles in every set

        ### Requirements
        - EVERY set MUST include "\(specifiedTitle)"
        - Vary the position of "\(specifiedTitle)" across sets (sometimes 1st, 2nd, 3rd, or 4th)
        - The other 3 titles should complement "\(specifiedTitle)" well
        - Vary the emphasis across sets
        - Each set must be different from existing sets

        Return JSON with "sets" array containing \(count) unique TitleSet objects.
        """

        Logger.info("🏷️ Generating \(count) title sets with required title: \(specifiedTitle)", category: .ai)

        struct Response: Codable {
            let sets: [TitleSet]
        }

        let response: Response = try await facade.executeStructuredWithDictionarySchema(
            prompt: prompt,
            modelId: modelId,
            as: Response.self,
            schema: TitleSetSchemas.setsOnlySchema,
            schemaName: "custom_title_sets",
            maxOutputTokens: 16384,
            backend: .gemini
        )

        return response.sets
    }

    /// Store title sets in guidance store
    func storeTitleSets(
        titleSets: [TitleSet],
        in guidanceStore: InferenceGuidanceStore
    ) {
        let attachments = GuidanceAttachments(
            titleSets: titleSets,
            vocabulary: []
        )

        let guidance = InferenceGuidance(
            nodeKey: "custom.jobTitles",
            displayName: "Identity Titles",
            prompt: """
            SELECT from these pre-validated title sets based on job fit.
            Do NOT generate new titles—pick the best matching set.
            If user has favorited sets, prefer those.

            Return exactly 4 titles as JSON array.
            """,
            attachmentsJSON: attachments.asJSON(),
            source: .auto
        )

        guidanceStore.add(guidance)
        Logger.info(
            "🏷️ Title sets stored in guidance store: \(titleSets.count) sets",
            category: .ai
        )
    }

    enum TitleSetError: Error, LocalizedError {
        case llmNotConfigured

        var errorDescription: String? {
            switch self {
            case .llmNotConfigured:
                return "LLM facade not configured"
            }
        }
    }
}

// MARK: - Result Types

struct TitleSetGenerationResult: Codable {
    let titleSets: [TitleSet]

    // For backward compatibility, provide empty vocabulary
    var vocabulary: [IdentityTerm] { [] }
}

// MARK: - Schemas

enum TitleSetSchemas {
    static let generationSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "titleSets": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "id": ["type": "string"],
                        "titles": ["type": "array", "items": ["type": "string"]],
                        "emphasis": ["type": "string", "enum": ["technical", "research", "leadership", "balanced"]],
                        "suggestedFor": ["type": "array", "items": ["type": "string"]],
                        "isFavorite": ["type": "boolean"]
                    ],
                    "required": ["id", "titles", "emphasis"]
                ]
            ]
        ],
        "required": ["titleSets"]
    ]

    static let setsOnlySchema: [String: Any] = [
        "type": "object",
        "properties": [
            "sets": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "id": ["type": "string"],
                        "titles": ["type": "array", "items": ["type": "string"]],
                        "emphasis": ["type": "string", "enum": ["technical", "research", "leadership", "balanced"]],
                        "suggestedFor": ["type": "array", "items": ["type": "string"]],
                        "isFavorite": ["type": "boolean"]
                    ],
                    "required": ["id", "titles", "emphasis"]
                ]
            ]
        ],
        "required": ["sets"]
    ]
}
