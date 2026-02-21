import Foundation

// MARK: - Refined Knowledge Card Response

/// Structured output response from the LLM when refining a knowledge card.
/// Mirrors the editable fields of KnowledgeCard.
struct RefinedKnowledgeCard: Codable, Sendable {
    let title: String
    let narrative: String
    let cardType: String?
    let dateRange: String?
    let organization: String?
    let location: String?
    let domains: [String]
    let scale: [String]
    let keywords: [String]
    let technologies: [String]
    let outcomes: [String]
    let suggestedBullets: [String]
    let evidenceQuality: String?
    let facts: [RefinedFact]?
    let verbatimExcerpts: [RefinedExcerpt]?
}

struct RefinedFact: Codable, Sendable {
    let category: String
    let statement: String
    let confidence: String?
}

struct RefinedExcerpt: Codable, Sendable {
    let context: String
    let location: String
    let text: String
    let preservationReason: String
}

// MARK: - JSON Schema

enum KCRefinementSchema {

    static var schema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "title": ["type": "string", "description": "Card title"],
                "narrative": ["type": "string", "description": "The narrative content (500-2000 words)"],
                "cardType": cardTypeSchema,
                "dateRange": nullableString("Date range, e.g. '2020-09 to 2024-06'"),
                "organization": nullableString("Company, university, or organization"),
                "location": nullableString("City, State or 'Remote'"),
                "domains": stringArray("Fields of expertise for job matching"),
                "scale": stringArray("Quantified elements: numbers, metrics, scope"),
                "keywords": stringArray("High-level terms for job matching"),
                "technologies": stringArray("Technologies, tools, and frameworks"),
                "outcomes": stringArray("Quantified outcomes"),
                "suggestedBullets": stringArray("Resume bullet templates"),
                "evidenceQuality": nullableString("Evidence quality: 'strong', 'moderate', or 'weak'"),
                "facts": factsSchema,
                "verbatimExcerpts": excerptsSchema
            ] as [String: Any],
            "required": [
                "title", "narrative", "domains", "scale", "keywords",
                "technologies", "outcomes", "suggestedBullets"
            ],
            "additionalProperties": false
        ]
    }

    // MARK: - Schema Helpers

    private static var cardTypeSchema: [String: Any] {
        [
            "type": ["string", "null"],
            "enum": ["employment", "project", "achievement", "education", nil] as [Any?],
            "description": "Card type"
        ] as [String: Any]
    }

    private static func nullableString(_ description: String) -> [String: Any] {
        ["type": ["string", "null"], "description": description]
    }

    private static func stringArray(_ description: String) -> [String: Any] {
        [
            "type": "array",
            "items": ["type": "string"],
            "description": description
        ]
    }

    private static var factsSchema: [String: Any] {
        [
            "type": ["array", "null"],
            "description": "Extracted facts with category and statement",
            "items": [
                "type": "object",
                "properties": [
                    "category": ["type": "string", "description": "Fact category"],
                    "statement": ["type": "string", "description": "Fact statement"],
                    "confidence": ["type": ["string", "null"], "description": "Confidence level"]
                ] as [String: Any],
                "required": ["category", "statement"],
                "additionalProperties": false
            ] as [String: Any]
        ] as [String: Any]
    }

    private static var excerptsSchema: [String: Any] {
        [
            "type": ["array", "null"],
            "description": "Verbatim excerpts preserving voice and context",
            "items": [
                "type": "object",
                "properties": [
                    "context": ["type": "string", "description": "What this excerpt demonstrates"],
                    "location": ["type": "string", "description": "Source document + location"],
                    "text": ["type": "string", "description": "100-500 word verbatim passage"],
                    "preservationReason": ["type": "string", "description": "Why this matters"]
                ] as [String: Any],
                "required": ["context", "location", "text", "preservationReason"],
                "additionalProperties": false
            ] as [String: Any]
        ] as [String: Any]
    }
}
