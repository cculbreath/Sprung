//
//  NarrativeDeduplicationService.swift
//  Sprung
//
//  Service for intelligent deduplication of narrative knowledge cards.
//  Uses a single LLM call to canonicalize all cards at once.
//

import Foundation

/// Service for intelligent deduplication of narrative knowledge cards.
/// Uses a single LLM call to identify duplicates and synthesize merged cards.
actor NarrativeDeduplicationService {
    private var llmFacade: LLMFacade?

    private var modelId: String {
        UserDefaults.standard.string(forKey: "narrativeDedupeModelId")
            ?? "openai/gpt-4.1"  // Default to high-quality model for merge decisions
    }

    init(llmFacade: LLMFacade?) {
        self.llmFacade = llmFacade
        Logger.info("🔀 NarrativeDeduplicationService initialized", category: .ai)
    }

    func updateLLMFacade(_ facade: LLMFacade?) {
        self.llmFacade = facade
    }

    // MARK: - Public API

    /// Canonicalize narrative cards - identify duplicates and merge them.
    /// Uses a single LLM call with ALL cards for semantic understanding.
    func deduplicateCards(_ cards: [KnowledgeCard]) async throws -> DeduplicationResult {
        guard !cards.isEmpty else {
            return DeduplicationResult(cards: [], mergeLog: [])
        }

        guard let facade = llmFacade else {
            throw DeduplicationError.llmNotConfigured
        }

        Logger.info("🔀 Canonicalizing \(cards.count) cards with single LLM call", category: .ai)
        Logger.info("🔀 Using model: \(modelId) via OpenRouter", category: .ai)

        let prompt = buildCanonicalizePrompt(cards)

        let response: CanonicalizationResponse = try await facade.executeStructuredWithDictionarySchema(
            prompt: prompt,
            modelId: modelId,
            as: CanonicalizationResponse.self,
            schema: Self.canonicalizationSchema,
            schemaName: "canonicalization",
            maxOutputTokens: 65536,  // Large output for full narratives
            backend: .openRouter
        )

        // Convert response to DeduplicationResult
        let mergeLog = response.mergeLog.map { entry in
            MergeLogEntry(
                action: entry.action == "merged" ? .merged : .kept,
                inputCards: entry.inputCardIds,
                outputCard: entry.outputCardId,
                reasoning: entry.reasoning
            )
        }

        Logger.info("🔀 Canonicalization complete: \(cards.count) → \(response.cards.count) cards", category: .ai)
        Logger.info("🔀 Stats: \(response.statistics.cardsMerged) merged in \(response.statistics.mergeGroups) groups", category: .ai)

        return DeduplicationResult(cards: response.cards, mergeLog: mergeLog)
    }

    // MARK: - Prompt Building

    private func buildCanonicalizePrompt(_ cards: [KnowledgeCard]) -> String {
        let cardsJSON = formatCardsAsJSON(cards)
        return PromptLibrary.substitute(
            template: PromptLibrary.narrativeCanonicalizeTemplate,
            replacements: ["CARDS_JSON": cardsJSON]
        )
    }

    private func formatCardsAsJSON(_ cards: [KnowledgeCard]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(cards),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }

    // MARK: - JSON Schema
    // Reuses KnowledgeCard schema structure from KCExtractionPrompts

    /// Card item schema matching KnowledgeCard structure
    private static let cardItemSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "id": ["type": "string", "description": "UUID for the card"],
            "card_type": [
                "type": "string",
                "enum": ["employment", "project", "achievement", "education"]
            ],
            "title": ["type": "string"],
            "narrative": ["type": "string", "description": "Full narrative (500-2000 words)"],
            "organization": ["type": "string", "description": "Organization name, or empty string if N/A"],
            "date_range": ["type": "string", "description": "Date range like '2018-2021', or empty string if N/A"],
            "extractable": [
                "type": "object",
                "properties": [
                    "domains": ["type": "array", "items": ["type": "string"]],
                    "scale": ["type": "array", "items": ["type": "string"]],
                    "keywords": ["type": "array", "items": ["type": "string"]]
                ],
                "required": ["domains", "scale", "keywords"]
            ],
            "evidence_anchors": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "document_id": ["type": "string"],
                        "location": ["type": "string"],
                        "verbatim_excerpt": ["type": "string"]
                    ],
                    "required": ["document_id", "location"]
                ]
            ],
            "related_card_ids": [
                "type": "array",
                "items": ["type": "string"]
            ]
        ],
        "required": ["id", "card_type", "title", "narrative", "organization", "date_range", "extractable", "evidence_anchors", "related_card_ids"]
    ]

    static let canonicalizationSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "cards": [
                "type": "array",
                "description": "The canonical set of cards after deduplication",
                "items": cardItemSchema
            ],
            "merge_log": [
                "type": "array",
                "description": "Log of all merge decisions",
                "items": [
                    "type": "object",
                    "properties": [
                        "action": ["type": "string", "enum": ["merged", "kept"]],
                        "input_card_ids": [
                            "type": "array",
                            "items": ["type": "string"],
                            "description": "IDs of input cards that were processed"
                        ],
                        "output_card_id": [
                            "type": "string",
                            "description": "ID of the resulting card"
                        ],
                        "reasoning": [
                            "type": "string",
                            "description": "Explanation for merge, empty for kept cards"
                        ]
                    ],
                    "required": ["action", "input_card_ids", "output_card_id", "reasoning"]
                ]
            ],
            "statistics": [
                "type": "object",
                "properties": [
                    "input_count": ["type": "integer"],
                    "output_count": ["type": "integer"],
                    "cards_merged": ["type": "integer"],
                    "merge_groups": ["type": "integer"]
                ],
                "required": ["input_count", "output_count", "cards_merged", "merge_groups"]
            ]
        ],
        "required": ["cards", "merge_log", "statistics"]
    ]

    enum DeduplicationError: Error, LocalizedError {
        case llmNotConfigured
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .llmNotConfigured: return "LLM facade not configured"
            case .invalidResponse: return "Invalid response from LLM"
            }
        }
    }
}

// MARK: - Response Types

/// Response from LLM canonicalization call
struct CanonicalizationResponse: Codable {
    let cards: [KnowledgeCard]
    let mergeLog: [CanonicalizationLogEntry]
    let statistics: CanonicalizationStats

    enum CodingKeys: String, CodingKey {
        case cards
        case mergeLog = "merge_log"
        case statistics
    }
}

/// Log entry for canonicalization decisions
struct CanonicalizationLogEntry: Codable {
    let action: String                   // "merged" or "kept"
    let inputCardIds: [String]           // Source card IDs
    let outputCardId: String             // Resulting card ID
    let reasoning: String                // Empty for kept cards

    enum CodingKeys: String, CodingKey {
        case action
        case inputCardIds = "input_card_ids"
        case outputCardId = "output_card_id"
        case reasoning
    }
}

struct CanonicalizationStats: Codable {
    let inputCount: Int
    let outputCount: Int
    let cardsMerged: Int
    let mergeGroups: Int

    enum CodingKeys: String, CodingKey {
        case inputCount = "input_count"
        case outputCount = "output_count"
        case cardsMerged = "cards_merged"
        case mergeGroups = "merge_groups"
    }
}

// MARK: - Result Types (kept from original)

struct DeduplicationResult {
    let cards: [KnowledgeCard]
    let mergeLog: [MergeLogEntry]
}

struct MergeLogEntry {
    enum Action: String {
        case kept
        case keptSeparate
        case merged
        case error
    }

    let action: Action
    let inputCards: [String]
    let outputCard: String?
    let reasoning: String
}
