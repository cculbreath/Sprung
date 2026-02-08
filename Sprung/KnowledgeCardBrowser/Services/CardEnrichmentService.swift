//
//  CardEnrichmentService.swift
//  Sprung
//
//  Enriches KnowledgeCards with structured fact extraction.
//  Fact extraction uses Gemini structured output.
//

import Foundation

/// Service that enriches knowledge cards with structured facts.
actor CardEnrichmentService {
    private let llmFacade: LLMFacade

    init(llmFacade: LLMFacade) {
        self.llmFacade = llmFacade
    }

    // MARK: - Public API

    /// Enrich a single card with structured fact extraction.
    /// - Parameters:
    ///   - card: The card to enrich (must have narrative content)
    ///   - sourceText: Source document text for evidence extraction
    func enrichCard(
        _ card: KnowledgeCard,
        sourceText: String
    ) async throws {
        try await extractFacts(for: card, sourceText: sourceText)
    }

    // MARK: - Fact Extraction

    private func extractFacts(for card: KnowledgeCard, sourceText: String) async throws {
        let modelId = try getModelId(key: "kcExtractionModelId", operation: "Fact Extraction")

        let prompt = buildFactExtractionPrompt(card: card, sourceText: sourceText)

        let result: FactExtractionResult = try await llmFacade.executeStructuredWithDictionarySchema(
            prompt: prompt,
            modelId: modelId,
            as: FactExtractionResult.self,
            schema: Self.factExtractionSchema,
            schemaName: "fact_extraction",
            maxOutputTokens: 32768,
            backend: .gemini
        )

        // Write results to card fields
        await MainActor.run {
            if !result.facts.isEmpty {
                card.facts = result.facts
            }
            if !result.suggestedBullets.isEmpty {
                card.suggestedBullets = result.suggestedBullets
            }
            if !result.outcomes.isEmpty {
                if let data = try? JSONEncoder().encode(result.outcomes),
                   let json = String(data: data, encoding: .utf8) {
                    card.outcomesJSON = json
                }
            }
            if !result.technologies.isEmpty {
                card.technologies = result.technologies
            }
            if !result.verbatimExcerpts.isEmpty {
                card.verbatimExcerpts = result.verbatimExcerpts
            }
        }

        Logger.info("CardEnrichmentService: Extracted \(result.facts.count) facts, \(result.suggestedBullets.count) bullets for \(card.title)", category: .ai)
    }

    // MARK: - Helpers

    private func getModelId(key: String, operation: String) throws -> String {
        guard let modelId = UserDefaults.standard.string(forKey: key), !modelId.isEmpty else {
            throw ModelConfigurationError.modelNotConfigured(
                settingKey: key,
                operationName: operation
            )
        }
        return modelId
    }

    // MARK: - Prompt Building

    private func buildFactExtractionPrompt(card: KnowledgeCard, sourceText: String) -> String {
        """
        You are a FACT EXTRACTION agent. Extract STRUCTURED FACTS from the source text for the \
        knowledge card described below.

        ## Card Information

        **Title**: \(card.title)
        **Type**: \(card.cardType?.displayName ?? "General")
        **Organization**: \(card.organization ?? "Not specified")
        **Time Period**: \(card.dateRange ?? "Not specified")

        **Card Narrative** (for context on what to extract):
        \(card.narrative)

        ## Fact Categories

        Extract facts into these categories:

        | Category | Description |
        |----------|-------------|
        | `technical_decision` | Design choice WITH rationale |
        | `problem_solved` | TECHNICAL/DOMAIN root cause + resolution |
        | `capability_built` | System, tool, or process created |
        | `artifact_produced` | Tangible deliverable |
        | `responsibility` | Role, scope, authority |
        | `scope_indicator` | Scale/complexity evidence |
        | `collaboration` | Team/stakeholder interaction |
        | `recognition` | External validation |
        | `context` | Situation, constraints, environment |

        ## Resume Fitness Filter

        Every extracted fact should pass this test: "Would including this on a resume help the \
        applicant get an interview?"

        **Extract:** Technical decisions, research findings, measurable outcomes, scope/scale \
        evidence, skills demonstrated, recognition received, capabilities built, qualitative \
        significance of results.

        **Do NOT extract:** Performance criticisms, negative feedback, interpersonal conflicts, \
        self-assessments of weakness, failure admissions, anything a hiring manager would \
        perceive as a red flag.

        ## Output Fields

        ### facts[]
        Raw evidence with source attribution. One fact per entry. Include:
        - `category`: One of the categories above
        - `statement`: The factual observation
        - `confidence`: "high", "medium", or "low"
        - `source`: Object with `artifact_id` (use "source_doc"), `location` (section/paragraph), \
        `verbatim_quote` (30-100 chars from source)

        ### suggested_bullets[]
        3-5 resume bullet TEMPLATES with [BRACKETED_PLACEHOLDERS] for customization. \
        Combine related facts into impact-oriented statements. Adapt style to work type \
        (research vs corporate vs academic).

        ### outcomes[]
        What CHANGED because of this work. Qualitative is fine. Focus on the delta, not the activity.

        ### technologies[]
        All technologies, tools, frameworks, and methodologies demonstrated.

        ### verbatim_excerpts[]
        1-3 passages (100-500 words each) worth preserving verbatim. Each with:
        - `context`: What this excerpt demonstrates
        - `location`: Where in the source
        - `text`: The verbatim passage
        - `preservation_reason`: Why this matters

        ## Source Document

        ---
        \(sourceText.prefix(150_000))
        ---

        Extract facts now.
        """
    }

    // MARK: - JSON Schema for Gemini Structured Output

    static let factExtractionSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "facts": [
                "type": "array",
                "description": "Extracted facts with source attribution",
                "items": [
                    "type": "object",
                    "properties": [
                        "category": [
                            "type": "string",
                            "enum": ["technical_decision", "problem_solved", "capability_built",
                                     "artifact_produced", "responsibility", "scope_indicator",
                                     "collaboration", "recognition", "context"],
                            "description": "Fact category"
                        ],
                        "statement": [
                            "type": "string",
                            "description": "The factual observation"
                        ],
                        "confidence": [
                            "type": "string",
                            "enum": ["high", "medium", "low"],
                            "description": "Evidence quality"
                        ],
                        "source": [
                            "type": "object",
                            "properties": [
                                "artifact_id": ["type": "string"],
                                "location": ["type": "string"],
                                "verbatim_quote": ["type": "string"]
                            ],
                            "required": ["artifact_id", "location"]
                        ]
                    ],
                    "required": ["category", "statement", "confidence"]
                ]
            ],
            "suggested_bullets": [
                "type": "array",
                "description": "Resume bullet templates with [PLACEHOLDERS]",
                "items": ["type": "string"]
            ],
            "outcomes": [
                "type": "array",
                "description": "What changed because of this work",
                "items": ["type": "string"]
            ],
            "technologies": [
                "type": "array",
                "description": "Technologies, tools, and frameworks",
                "items": ["type": "string"]
            ],
            "verbatim_excerpts": [
                "type": "array",
                "description": "Passages worth preserving verbatim",
                "items": [
                    "type": "object",
                    "properties": [
                        "context": ["type": "string"],
                        "location": ["type": "string"],
                        "text": ["type": "string"],
                        "preservation_reason": ["type": "string"]
                    ],
                    "required": ["context", "location", "text", "preservation_reason"]
                ]
            ]
        ],
        "required": ["facts", "suggested_bullets", "outcomes", "technologies", "verbatim_excerpts"]
    ]
}

// MARK: - Result Types

private struct FactExtractionResult: Codable, Sendable {
    let facts: [KnowledgeCardFact]
    let suggestedBullets: [String]
    let outcomes: [String]
    let technologies: [String]
    let verbatimExcerpts: [VerbatimExcerpt]

    enum CodingKeys: String, CodingKey {
        case facts
        case suggestedBullets = "suggested_bullets"
        case outcomes
        case technologies
        case verbatimExcerpts = "verbatim_excerpts"
    }
}
