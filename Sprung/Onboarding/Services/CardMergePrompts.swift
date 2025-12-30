//
//  CardMergePrompts.swift
//  Sprung
//
//  Prompt builder for cross-document card merging.
//

import Foundation
import SwiftyJSON

/// Builds prompts for cross-document card merging
enum CardMergePrompts {

    // MARK: - JSON Schema for Gemini Structured Output

    /// JSON Schema for MergedCardInventory to enable Gemini structured output mode
    static let jsonSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "merged_cards": [
                "type": "array",
                "description": "Deduplicated cards from all documents",
                "items": [
                    "type": "object",
                    "properties": [
                        "card_id": [
                            "type": "string",
                            "description": "Unique UUID for this merged card"
                        ],
                        "card_type": [
                            "type": "string",
                            "enum": ["employment", "project", "skill", "achievement", "education"],
                            "description": "Type of knowledge card"
                        ],
                        "title": [
                            "type": "string",
                            "description": "Descriptive title for the card"
                        ],
                        "primary_source": [
                            "type": "object",
                            "description": "Primary document source for this card",
                            "properties": [
                                "document_id": ["type": "string"],
                                "evidence_locations": [
                                    "type": "array",
                                    "items": ["type": "string"]
                                ]
                            ],
                            "required": ["document_id", "evidence_locations"]
                        ],
                        "supporting_sources": [
                            "type": "array",
                            "description": "Additional document sources",
                            "items": [
                                "type": "object",
                                "properties": [
                                    "document_id": ["type": "string"],
                                    "evidence_locations": [
                                        "type": "array",
                                        "items": ["type": "string"]
                                    ],
                                    "adds": [
                                        "type": "array",
                                        "items": ["type": "string"],
                                        "description": "What this source uniquely contributes"
                                    ]
                                ],
                                "required": ["document_id", "evidence_locations", "adds"]
                            ]
                        ],
                        "combined_key_facts": [
                            "type": "array",
                            "items": ["type": "string"],
                            "description": "All unique facts from all sources"
                        ],
                        "combined_technologies": [
                            "type": "array",
                            "items": ["type": "string"],
                            "description": "All technologies mentioned"
                        ],
                        "combined_outcomes": [
                            "type": "array",
                            "items": ["type": "string"],
                            "description": "All quantified outcomes"
                        ],
                        "date_range": [
                            "type": "string",
                            "description": "Time period if applicable"
                        ],
                        "evidence_quality": [
                            "type": "string",
                            "enum": ["strong", "moderate", "weak"],
                            "description": "Overall evidence quality"
                        ],
                        "extraction_priority": [
                            "type": "string",
                            "enum": ["high", "medium", "low"],
                            "description": "Priority for knowledge card extraction"
                        ]
                    ],
                    "required": ["card_id", "card_type", "title", "primary_source", "supporting_sources",
                                 "combined_key_facts", "combined_technologies", "combined_outcomes",
                                 "evidence_quality", "extraction_priority"]
                ]
            ],
            "gaps": [
                "type": "array",
                "description": "Documentation gaps identified",
                "items": [
                    "type": "object",
                    "properties": [
                        "card_title": ["type": "string"],
                        "gap_type": [
                            "type": "string",
                            "enum": ["missing_primary_source", "insufficient_detail", "no_quantified_outcomes"]
                        ],
                        "current_evidence": ["type": "string"],
                        "recommended_docs": [
                            "type": "array",
                            "items": ["type": "string"]
                        ]
                    ],
                    "required": ["card_title", "gap_type", "current_evidence", "recommended_docs"]
                ]
            ],
            "stats": [
                "type": "object",
                "description": "Merge statistics",
                "properties": [
                    "total_input_cards": ["type": "integer"],
                    "merged_output_cards": ["type": "integer"],
                    "cards_by_type": [
                        "type": "object",
                        "description": "Count of cards by type",
                        "properties": [
                            "employment": ["type": "integer", "description": "Count of employment cards"],
                            "project": ["type": "integer", "description": "Count of project cards"],
                            "skill": ["type": "integer", "description": "Count of skill cards"],
                            "achievement": ["type": "integer", "description": "Count of achievement cards"],
                            "education": ["type": "integer", "description": "Count of education cards"]
                        ],
                        "required": ["employment", "project", "skill", "achievement", "education"]
                    ],
                    "strong_evidence": ["type": "integer"],
                    "needs_more_evidence": ["type": "integer"]
                ],
                "required": ["total_input_cards", "merged_output_cards", "cards_by_type",
                             "strong_evidence", "needs_more_evidence"]
            ],
            "generated_at": [
                "type": "string",
                "description": "ISO8601 timestamp"
            ]
        ],
        "required": ["merged_cards", "gaps", "stats", "generated_at"]
    ]

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
