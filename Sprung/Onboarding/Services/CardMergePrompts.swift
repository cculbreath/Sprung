//
//  CardMergePrompts.swift
//  Sprung
//
//  Prompt builder for cross-document card merging.
//

import Foundation
import SwiftOpenAI
import SwiftyJSON

/// Builds prompts for cross-document card merging
enum CardMergePrompts {

    // MARK: - JSONSchema for OpenAI Strict Structured Output

    /// JSONSchema for MergedCardInventory using OpenAI's strict schema enforcement
    /// GPT-5 supports 128K output tokens and guarantees schema compliance
    static let openAISchema: JSONSchema = {
        // Source reference (used in primary_source and supporting_sources)
        let sourceReferenceSchema = SchemaGenerator.object(
            description: "Document source reference",
            properties: [
                "document_id": SchemaGenerator.string(description: "Document identifier"),
                "evidence_locations": SchemaGenerator.array(
                    of: SchemaGenerator.string(),
                    description: "Locations in document where evidence was found"
                )
            ],
            required: ["document_id", "evidence_locations"]
        )

        // Supporting source (extends source reference with "adds" field)
        let supportingSourceSchema = SchemaGenerator.object(
            description: "Supporting document source",
            properties: [
                "document_id": SchemaGenerator.string(description: "Document identifier"),
                "evidence_locations": SchemaGenerator.array(
                    of: SchemaGenerator.string(),
                    description: "Locations in document"
                ),
                "adds": SchemaGenerator.array(
                    of: SchemaGenerator.string(),
                    description: "What this source uniquely contributes"
                )
            ],
            required: ["document_id", "evidence_locations", "adds"]
        )

        // Merged card schema
        let mergedCardSchema = SchemaGenerator.object(
            description: "Merged knowledge card",
            properties: [
                "card_id": SchemaGenerator.string(description: "Unique UUID for this merged card"),
                "card_type": SchemaGenerator.string(
                    description: "Type of knowledge card",
                    enumValues: ["employment", "project", "skill", "achievement", "education"]
                ),
                "title": SchemaGenerator.string(description: "Descriptive title for the card"),
                "primary_source": sourceReferenceSchema,
                "supporting_sources": SchemaGenerator.array(
                    of: supportingSourceSchema,
                    description: "Additional document sources"
                ),
                "combined_key_facts": SchemaGenerator.array(
                    of: SchemaGenerator.string(),
                    description: "All unique facts from all sources (max 5)"
                ),
                "combined_technologies": SchemaGenerator.array(
                    of: SchemaGenerator.string(),
                    description: "All technologies mentioned (max 5)"
                ),
                "combined_outcomes": SchemaGenerator.array(
                    of: SchemaGenerator.string(),
                    description: "All quantified outcomes (max 3)"
                ),
                "date_range": SchemaGenerator.string(description: "Time period if applicable"),
                "evidence_quality": SchemaGenerator.string(
                    description: "Overall evidence quality",
                    enumValues: ["strong", "moderate", "weak"]
                ),
                "extraction_priority": SchemaGenerator.string(
                    description: "Priority for knowledge card extraction",
                    enumValues: ["high", "medium", "low"]
                )
            ],
            required: ["card_id", "card_type", "title", "primary_source", "supporting_sources",
                      "combined_key_facts", "combined_technologies", "combined_outcomes",
                      "date_range", "evidence_quality", "extraction_priority"]
        )

        // Documentation gap schema
        let gapSchema = SchemaGenerator.object(
            description: "Documentation gap",
            properties: [
                "card_title": SchemaGenerator.string(description: "Title of card with gap"),
                "gap_type": SchemaGenerator.string(
                    description: "Type of gap",
                    enumValues: ["missing_primary_source", "insufficient_detail", "no_quantified_outcomes"]
                ),
                "current_evidence": SchemaGenerator.string(description: "Current evidence summary"),
                "recommended_docs": SchemaGenerator.array(
                    of: SchemaGenerator.string(),
                    description: "Recommended documents to fill gap"
                )
            ],
            required: ["card_title", "gap_type", "current_evidence", "recommended_docs"]
        )

        // Cards by type stats
        let cardsByTypeSchema = SchemaGenerator.object(
            description: "Count of cards by type",
            properties: [
                "employment": SchemaGenerator.integer(description: "Employment card count"),
                "project": SchemaGenerator.integer(description: "Project card count"),
                "skill": SchemaGenerator.integer(description: "Skill card count"),
                "achievement": SchemaGenerator.integer(description: "Achievement card count"),
                "education": SchemaGenerator.integer(description: "Education card count")
            ],
            required: ["employment", "project", "skill", "achievement", "education"]
        )

        // Stats schema
        let statsSchema = SchemaGenerator.object(
            description: "Merge statistics",
            properties: [
                "total_input_cards": SchemaGenerator.integer(description: "Total cards before merge"),
                "merged_output_cards": SchemaGenerator.integer(description: "Cards after merge"),
                "cards_by_type": cardsByTypeSchema,
                "strong_evidence": SchemaGenerator.integer(description: "Cards with strong evidence"),
                "needs_more_evidence": SchemaGenerator.integer(description: "Cards needing more evidence")
            ],
            required: ["total_input_cards", "merged_output_cards", "cards_by_type",
                      "strong_evidence", "needs_more_evidence"]
        )

        // Top-level schema
        return SchemaGenerator.object(
            description: "Merged card inventory from cross-document analysis",
            properties: [
                "generated_at": SchemaGenerator.string(description: "ISO8601 timestamp"),
                "stats": statsSchema,
                "gaps": SchemaGenerator.array(of: gapSchema, description: "Documentation gaps identified"),
                "merged_cards": SchemaGenerator.array(
                    of: mergedCardSchema,
                    description: "Deduplicated cards from all documents"
                )
            ],
            required: ["generated_at", "stats", "gaps", "merged_cards"]
        )
    }()

    // MARK: - Prompt Builder

    /// Build the merge prompt for multiple document inventories
    /// - Parameters:
    ///   - inventories: Array of DocumentInventory from all documents
    ///   - timeline: Optional skeleton timeline for employment context
    /// - Returns: Formatted prompt string
    static func mergePrompt(
        inventories: [DocumentInventory],
        timeline: JSON?
    ) -> String {
        // Encode inventories to JSON string
        let inventoriesJSON: String
        if let data = try? JSONEncoder().encode(inventories),
           let jsonString = String(data: data, encoding: .utf8) {
            inventoriesJSON = jsonString
        } else {
            inventoriesJSON = "[]"
        }

        // Convert timeline to string
        let timelineJSON: String
        if let timeline = timeline {
            timelineJSON = timeline.rawString() ?? "{}"
        } else {
            timelineJSON = "{}"
        }

        return PromptLibrary.substitute(
            template: PromptLibrary.crossDocumentMergeTemplate,
            replacements: [
                "INVENTORIES_JSON": inventoriesJSON,
                "TIMELINE_JSON": timelineJSON
            ]
        )
    }
}
