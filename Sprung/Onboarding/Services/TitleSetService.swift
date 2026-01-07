//
//  TitleSetService.swift
//  Sprung
//
//  Generates identity vocabulary and title sets from skill bank data.
//

import Foundation

/// Generates identity vocabulary and title sets from skill bank.
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

    /// Generate initial title sets from skill bank
    func generateInitialTitleSets(from skills: [Skill]) async throws -> TitleSetGenerationResult {
        guard let facade = llmFacade else {
            throw TitleSetError.llmNotConfigured
        }

        let grouped = Dictionary(grouping: skills, by: { $0.category })
        var categoryDescriptions: [String] = []

        for (category, categorySkills) in grouped.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            let topSkills = categorySkills
                .sorted { $0.evidence.count > $1.evidence.count }
                .prefix(15)
                .map { $0.canonical }
            categoryDescriptions.append("\(category.rawValue): \(topSkills.joined(separator: ", "))")
        }

        let prompt = """
        # Identity Title Generation

        ## Skill Categories (evidence of what this person does)

        \(categoryDescriptions.joined(separator: "\n"))

        ## Task

        ### Step 1: Extract Identity Vocabulary

        From the skill categories, identify single-word NOUNS that describe who this person IS:
        - Languages/Frameworks → "Developer", "Programmer", "Engineer"
        - Hardware/Electronics → "Engineer", "Technician", "Builder"
        - Fabrication → "Machinist", "Craftsman", "Maker"
        - Scientific → "Scientist", "Researcher", "Physicist", "Analyst"
        - Leadership/Teaching → "Leader", "Mentor", "Educator", "Instructor"
        - Domain expertise → "Architect", "Designer", "Strategist"

        Extract 10-20 relevant identity nouns with evidence strength (0.0-1.0).

        ### Step 2: Generate Title Sets

        Create 8-12 four-title combinations:
        - Each set has exactly 4 single-word titles
        - Vary rhythm (mix syllable counts)
        - Cover different emphases: technical, research, leadership, balanced
        - Tag with job types each set works for

        ## Output Format

        Return JSON:
        ```json
        {
          "vocabulary": [
            {"id": "uuid", "term": "Physicist", "evidenceStrength": 0.9, "sourceDocumentIds": []}
          ],
          "titleSets": [
            {
              "id": "uuid",
              "titles": ["Physicist", "Developer", "Educator", "Machinist"],
              "emphasis": "balanced",
              "suggestedFor": ["R&D", "interdisciplinary"],
              "isFavorite": false
            }
          ]
        }
        ```
        """

        Logger.info(
            "🏷️ Generating title sets from \(skills.count) skills in \(grouped.count) categories",
            category: .ai
        )

        let result: TitleSetGenerationResult = try await facade.executeStructuredWithDictionarySchema(
            prompt: prompt,
            modelId: modelId,
            as: TitleSetGenerationResult.self,
            schema: TitleSetSchemas.generationSchema,
            schemaName: "title_set_generation",
            maxOutputTokens: 8192,
            backend: .gemini
        )

        Logger.info(
            "🏷️ Generated \(result.vocabulary.count) identity terms and \(result.titleSets.count) title sets",
            category: .ai
        )
        return result
    }

    /// Generate additional title sets from existing vocabulary
    func generateMoreTitleSets(
        vocabulary: [IdentityTerm],
        existingSets: [TitleSet],
        count: Int = 5
    ) async throws -> [TitleSet] {
        guard let facade = llmFacade else {
            throw TitleSetError.llmNotConfigured
        }

        let vocabList = vocabulary.map { $0.term }.joined(separator: ", ")
        let existingList = existingSets.map { $0.titles.joined(separator: ". ") + "." }.joined(separator: "\n")

        let prompt = """
        # Generate More Title Sets

        ## Available Vocabulary
        \(vocabList)

        ## Existing Sets (avoid duplicates)
        \(existingList)

        ## Task
        Generate \(count) NEW four-title combinations that are DIFFERENT from existing sets.
        Vary the emphasis (technical, research, leadership, balanced).

        Return JSON array of TitleSet objects.
        """

        Logger.info("🏷️ Generating \(count) more title sets", category: .ai)

        struct Response: Codable {
            let sets: [TitleSet]
        }

        let response: Response = try await facade.executeStructuredWithDictionarySchema(
            prompt: prompt,
            modelId: modelId,
            as: Response.self,
            schema: TitleSetSchemas.moreSetsSchema,
            schemaName: "more_title_sets",
            maxOutputTokens: 4096,
            backend: .gemini
        )

        return response.sets
    }

    /// Store title sets and vocabulary in guidance store
    func storeTitleSets(
        vocabulary: [IdentityTerm],
        titleSets: [TitleSet],
        in guidanceStore: InferenceGuidanceStore
    ) {
        let attachments = GuidanceAttachments(
            titleSets: titleSets,
            vocabulary: vocabulary
        )

        let guidance = InferenceGuidance(
            nodeKey: "custom.jobTitles",
            displayName: "Identity Titles",
            prompt: """
            SELECT from these pre-validated title sets based on job fit.
            Do NOT generate new titles—pick the best matching set.
            If user has favorited sets, prefer those.

            Return exactly 4 single-word titles as JSON array.
            """,
            attachmentsJSON: attachments.asJSON(),
            source: .auto
        )

        guidanceStore.add(guidance)
        Logger.info(
            "🏷️ Title sets stored in guidance store: \(titleSets.count) sets, \(vocabulary.count) terms",
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
    let vocabulary: [IdentityTerm]
    let titleSets: [TitleSet]
}

// MARK: - Schemas

enum TitleSetSchemas {
    static let generationSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "vocabulary": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "id": ["type": "string"],
                        "term": ["type": "string"],
                        "evidenceStrength": ["type": "number"],
                        "sourceDocumentIds": ["type": "array", "items": ["type": "string"]]
                    ],
                    "required": ["id", "term", "evidenceStrength"]
                ]
            ],
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
        "required": ["vocabulary", "titleSets"]
    ]

    static let moreSetsSchema: [String: Any] = [
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
