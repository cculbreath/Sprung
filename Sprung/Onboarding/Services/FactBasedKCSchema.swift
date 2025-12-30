//
//  FactBasedKCSchema.swift
//  Sprung
//
//  Strict JSON schema for fact-based knowledge card extraction.
//  Uses OpenAI structured output with guaranteed schema compliance.
//

import Foundation
import SwiftOpenAI

/// Schema definitions for fact-based knowledge card extraction
enum FactBasedKCSchema {

    // MARK: - JSONSchema for OpenAI Strict Structured Output

    /// JSONSchema for fact-based knowledge card using OpenAI's strict schema enforcement
    static let openAISchema: JSONSchema = {
        // Source attribution schema
        let sourceSchema = SchemaGenerator.object(
            description: "Source attribution with verbatim quote",
            properties: [
                "artifact_id": SchemaGenerator.string(description: "Document identifier"),
                "location": SchemaGenerator.string(description: "Location in document (e.g., 'paragraph 3', 'metrics section')"),
                "verbatim_quote": SchemaGenerator.string(description: "Exact text from source (30-100 chars)")
            ],
            required: ["artifact_id", "location", "verbatim_quote"]
        )

        // Individual fact schema
        let factSchema = SchemaGenerator.object(
            description: "Single extracted fact with attribution",
            properties: [
                "category": SchemaGenerator.string(
                    description: "Fact category",
                    enumValues: ["responsibility", "achievement", "technology", "metric", "scope", "context", "recognition"]
                ),
                "statement": SchemaGenerator.string(description: "The extracted fact as a concise statement"),
                "confidence": SchemaGenerator.string(
                    description: "Evidence quality",
                    enumValues: ["high", "medium", "low"]
                ),
                "source": sourceSchema
            ],
            required: ["category", "statement", "confidence", "source"]
        )

        // Top-level schema
        return SchemaGenerator.object(
            description: "Fact-based knowledge card with source attribution",
            properties: [
                "card_id": SchemaGenerator.string(description: "UUID for this card"),
                "card_type": SchemaGenerator.string(
                    description: "Type of knowledge card",
                    enumValues: ["employment", "project", "skill", "achievement", "education"]
                ),
                "title": SchemaGenerator.string(description: "Card title"),
                "facts": SchemaGenerator.array(
                    of: factSchema,
                    description: "All extracted facts with source attribution"
                ),
                "suggested_bullets": SchemaGenerator.array(
                    of: SchemaGenerator.string(),
                    description: "3-5 resume bullet templates combining related facts"
                ),
                "technologies": SchemaGenerator.array(
                    of: SchemaGenerator.string(),
                    description: "Technologies, tools, and frameworks mentioned"
                ),
                "date_range": SchemaGenerator.string(description: "Time period if applicable"),
                "sources_used": SchemaGenerator.array(
                    of: SchemaGenerator.string(),
                    description: "List of artifact IDs used"
                )
            ],
            required: ["card_id", "card_type", "title", "facts", "suggested_bullets",
                      "technologies", "date_range", "sources_used"]
        )
    }()

    // MARK: - Swift Types for Decoding

    /// Decoded fact-based knowledge card
    struct FactBasedKnowledgeCard: Codable {
        let cardId: String
        let cardType: String
        let title: String
        let facts: [ExtractedFact]
        let suggestedBullets: [String]
        let technologies: [String]
        let dateRange: String
        let sourcesUsed: [String]

        enum CodingKeys: String, CodingKey {
            case cardId = "card_id"
            case cardType = "card_type"
            case title
            case facts
            case suggestedBullets = "suggested_bullets"
            case technologies
            case dateRange = "date_range"
            case sourcesUsed = "sources_used"
        }
    }

    /// Individual extracted fact
    struct ExtractedFact: Codable {
        let category: FactCategory
        let statement: String
        let confidence: ConfidenceLevel
        let source: SourceAttribution

        enum FactCategory: String, Codable {
            case responsibility
            case achievement
            case technology
            case metric
            case scope
            case context
            case recognition
        }

        enum ConfidenceLevel: String, Codable {
            case high
            case medium
            case low
        }
    }

    /// Source attribution for a fact
    struct SourceAttribution: Codable {
        let artifactId: String
        let location: String
        let verbatimQuote: String

        enum CodingKeys: String, CodingKey {
            case artifactId = "artifact_id"
            case location
            case verbatimQuote = "verbatim_quote"
        }
    }
}
