//
//  GuidanceGenerationService.swift
//  Sprung
//
//  Service for generating inference guidance from onboarding data.
//  Creates identity vocabulary, title sets, and voice profiles.
//

import Foundation

/// Service for generating inference guidance during onboarding
actor GuidanceGenerationService {
    private var llmFacade: LLMFacade?

    private var modelId: String {
        // Flash for speed - good enough for extraction tasks
        UserDefaults.standard.string(forKey: "guidanceExtractionModelId") ?? "gemini-2.5-flash"
    }

    init(llmFacade: LLMFacade?) {
        self.llmFacade = llmFacade
        Logger.info("📝 GuidanceGenerationService initialized", category: .ai)
    }

    func updateLLMFacade(_ facade: LLMFacade?) {
        self.llmFacade = facade
    }

    // MARK: - Main Generation Entry Point

    /// Generate all guidance from processed documents
    /// Called after document processing completes
    @MainActor
    func generateAllGuidance(
        narrativeCards: [KnowledgeCard],
        writingSamples: [String],
        guidanceStore: InferenceGuidanceStore
    ) async throws {

        // 1. Extract identity vocabulary
        let vocabulary = try await extractIdentityVocabulary(from: narrativeCards)

        // 2. Generate title sets from vocabulary
        let titleSets = try await generateTitleSets(from: vocabulary)

        // 3. Extract voice profile from writing samples
        let voiceProfile = try await extractVoiceProfile(from: writingSamples)

        // 4. Create guidance records
        // Title guidance
        let titleAttachments = GuidanceAttachments(
            titleSets: titleSets,
            vocabulary: vocabulary
        )

        let titleGuidance = InferenceGuidance(
            nodeKey: "custom.jobTitles",
            displayName: "Identity Titles",
            prompt: """
            SELECT from these pre-validated title sets based on job fit.
            Do NOT generate new titles—pick the best matching set.
            If user has favorited sets, prefer those.

            Available sets:
            {ATTACHMENTS}

            Return exactly 4 single-word titles as JSON array.
            """,
            attachmentsJSON: titleAttachments.asJSON(),
            source: .auto
        )
        guidanceStore.add(titleGuidance)

        // Objective guidance
        let objectiveAttachments = GuidanceAttachments(voiceProfile: voiceProfile)

        let objectiveGuidance = InferenceGuidance(
            nodeKey: "objective",
            displayName: "Objective Voice",
            prompt: """
            Voice profile for objective statement:
            - Enthusiasm: \(voiceProfile.enthusiasm.displayName)
            - Person: \(voiceProfile.useFirstPerson ? "First person (I built, I discovered)" : "Third person")
            - Connectives: \(voiceProfile.connectiveStyle)
            - Aspirational phrases: \(voiceProfile.aspirationalPhrases.joined(separator: ", "))
            - NEVER use: \(voiceProfile.avoidPhrases.joined(separator: ", "))

            Structure:
            1. Where you've been (1-2 sentences)
            2. What draws you to THIS role (1-2 sentences)
            3. What you want to build (1-2 sentences)

            Voice samples:
            {ATTACHMENTS}
            """,
            attachmentsJSON: objectiveAttachments.asJSON(),
            source: .auto
        )
        guidanceStore.add(objectiveGuidance)

        Logger.info("✅ Generated inference guidance: \(vocabulary.count) terms, \(titleSets.count) sets", category: .ai)
    }

    // MARK: - Extraction Methods

    /// Extract identity vocabulary from narrative cards
    func extractIdentityVocabulary(from cards: [KnowledgeCard]) async throws -> [IdentityTerm] {
        guard let facade = llmFacade else { throw GuidanceError.llmNotConfigured }
        guard !cards.isEmpty else { return [] }

        let cardSummaries = cards.map { "**\($0.title)**: \(String($0.narrative.prefix(300)))..." }
            .joined(separator: "\n\n")

        let prompt = PromptLibrary.substitute(
            template: PromptLibrary.identityVocabularyTemplate,
            replacements: ["NARRATIVE_CARDS": cardSummaries]
        )

        Logger.info("📝 Extracting identity vocabulary from \(cards.count) cards", category: .ai)

        let jsonString = try await facade.generateStructuredJSON(
            prompt: prompt,
            modelId: modelId,
            maxOutputTokens: 4096,
            jsonSchema: GuidanceSchemas.identityVocabularySchema
        )

        guard let data = jsonString.data(using: .utf8) else {
            throw GuidanceError.parseError("Failed to convert response to data")
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        struct Response: Codable {
            let terms: [IdentityTerm]
        }

        let response = try decoder.decode(Response.self, from: data)
        Logger.info("📝 Extracted \(response.terms.count) identity terms", category: .ai)
        return response.terms
    }

    /// Generate title sets from vocabulary
    func generateTitleSets(from vocabulary: [IdentityTerm]) async throws -> [TitleSet] {
        guard let facade = llmFacade else { throw GuidanceError.llmNotConfigured }
        guard !vocabulary.isEmpty else { return [] }

        // Only use strong terms
        let strongTerms = vocabulary
            .filter { $0.evidenceStrength >= 0.5 }
            .sorted { $0.evidenceStrength > $1.evidenceStrength }

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let termsJSON = try encoder.encode(strongTerms)

        let prompt = PromptLibrary.substitute(
            template: PromptLibrary.titleSetGenerationTemplate,
            replacements: ["VOCABULARY_JSON": String(data: termsJSON, encoding: .utf8) ?? "[]"]
        )

        Logger.info("📝 Generating title sets from \(strongTerms.count) terms", category: .ai)

        let jsonString = try await facade.generateStructuredJSON(
            prompt: prompt,
            modelId: modelId,
            maxOutputTokens: 8192,
            jsonSchema: GuidanceSchemas.titleSetSchema
        )

        guard let data = jsonString.data(using: .utf8) else {
            throw GuidanceError.parseError("Failed to convert response to data")
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        struct Response: Codable {
            let sets: [TitleSet]
        }

        let response = try decoder.decode(Response.self, from: data)
        Logger.info("📝 Generated \(response.sets.count) title sets", category: .ai)
        return response.sets
    }

    /// Extract voice profile from writing samples
    func extractVoiceProfile(from samples: [String]) async throws -> VoiceProfile {
        guard let facade = llmFacade else { throw GuidanceError.llmNotConfigured }

        // If no samples, return default profile
        guard !samples.isEmpty else {
            return VoiceProfile()
        }

        let samplesText = samples.joined(separator: "\n\n---\n\n")

        let prompt = PromptLibrary.substitute(
            template: PromptLibrary.voiceProfileTemplate,
            replacements: ["WRITING_SAMPLES": samplesText]
        )

        Logger.info("📝 Extracting voice profile from \(samples.count) samples", category: .ai)

        let jsonString = try await facade.generateStructuredJSON(
            prompt: prompt,
            modelId: modelId,
            maxOutputTokens: 4096,
            jsonSchema: GuidanceSchemas.voiceProfileSchema
        )

        guard let data = jsonString.data(using: .utf8) else {
            throw GuidanceError.parseError("Failed to convert response to data")
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let profile = try decoder.decode(VoiceProfile.self, from: data)
        Logger.info("📝 Extracted voice profile: \(profile.enthusiasm.displayName), \(profile.connectiveStyle)", category: .ai)
        return profile
    }

    // MARK: - Error Types

    enum GuidanceError: Error, LocalizedError {
        case llmNotConfigured
        case parseError(String)

        var errorDescription: String? {
            switch self {
            case .llmNotConfigured:
                return "LLM facade not configured"
            case .parseError(let message):
                return "Parse error: \(message)"
            }
        }
    }
}

// MARK: - JSON Schemas

/// JSON Schemas for structured output
enum GuidanceSchemas {
    /// Schema for identity vocabulary extraction
    static let identityVocabularySchema: [String: Any] = [
        "type": "object",
        "properties": [
            "terms": [
                "type": "array",
                "description": "Identity terms extracted from narratives",
                "items": [
                    "type": "object",
                    "properties": [
                        "id": [
                            "type": "string",
                            "description": "Unique identifier (UUID format)"
                        ],
                        "term": [
                            "type": "string",
                            "description": "Single-word identity noun (e.g., Physicist, Developer)"
                        ],
                        "evidence_strength": [
                            "type": "number",
                            "description": "Confidence score 0.0-1.0"
                        ],
                        "source_document_ids": [
                            "type": "array",
                            "items": ["type": "string"],
                            "description": "Document IDs where term appears"
                        ]
                    ],
                    "required": ["id", "term", "evidence_strength"]
                ]
            ]
        ],
        "required": ["terms"]
    ]

    /// Schema for title set generation
    static let titleSetSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "sets": [
                "type": "array",
                "description": "Generated title sets",
                "items": [
                    "type": "object",
                    "properties": [
                        "id": [
                            "type": "string",
                            "description": "Unique identifier (UUID format)"
                        ],
                        "titles": [
                            "type": "array",
                            "items": ["type": "string"],
                            "description": "Exactly 4 single-word titles"
                        ],
                        "emphasis": [
                            "type": "string",
                            "enum": ["technical", "research", "leadership", "balanced"],
                            "description": "Primary emphasis of the set"
                        ],
                        "suggested_for": [
                            "type": "array",
                            "items": ["type": "string"],
                            "description": "Job types this set is good for"
                        ],
                        "is_favorite": [
                            "type": "boolean",
                            "description": "Whether user has favorited this set"
                        ]
                    ],
                    "required": ["id", "titles", "emphasis"]
                ]
            ]
        ],
        "required": ["sets"]
    ]

    /// Schema for voice profile extraction
    static let voiceProfileSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "enthusiasm": [
                "type": "string",
                "enum": ["measured", "moderate", "high"],
                "description": "Overall enthusiasm level in writing"
            ],
            "use_first_person": [
                "type": "boolean",
                "description": "Whether the writer uses first person (I/we)"
            ],
            "connective_style": [
                "type": "string",
                "description": "How ideas are connected (causal, sequential, contrastive)"
            ],
            "aspirational_phrases": [
                "type": "array",
                "items": ["type": "string"],
                "description": "Phrases used to express goals and aspirations"
            ],
            "avoid_phrases": [
                "type": "array",
                "items": ["type": "string"],
                "description": "Corporate buzzwords the writer avoids"
            ],
            "sample_excerpts": [
                "type": "array",
                "items": ["type": "string"],
                "description": "Verbatim excerpts showing voice (20-50 words each)"
            ]
        ],
        "required": ["enthusiasm", "use_first_person", "connective_style"]
    ]
}
