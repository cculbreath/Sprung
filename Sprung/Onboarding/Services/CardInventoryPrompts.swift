//
//  CardInventoryPrompts.swift
//  Sprung
//
//  Prompt builder and JSON schema for card inventory generation.
//  Uses Gemini's native structured output mode for guaranteed valid JSON.
//

import Foundation

/// Builds prompts and schemas for document card inventory generation
enum CardInventoryPrompts {

    /// Build the inventory prompt for a document.
    /// Loads template from Resources/Prompts/card_inventory_prompt.txt
    /// - Parameters:
    ///   - documentId: Unique document identifier
    ///   - filename: Document filename
    ///   - content: Extracted document content
    /// - Returns: Formatted prompt string
    static func inventoryPrompt(
        documentId: String,
        filename: String,
        content: String
    ) -> String {
        return PromptLibrary.substitute(
            template: PromptLibrary.cardInventoryTemplate,
            replacements: [
                "DOC_ID": documentId,
                "FILENAME": filename,
                "EXTRACTED_CONTENT": content
            ]
        )
    }

    /// JSON Schema for DocumentInventory - used by Gemini's native structured output.
    /// This schema guarantees the LLM response will be valid, parseable JSON.
    static let jsonSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "document_type": [
                "type": "string",
                "description": "Type of document"
            ],
            "cards": [
                "type": "array",
                "description": "List of proposed knowledge cards",
                "items": [
                    "type": "object",
                    "properties": [
                        "card_type": [
                            "type": "string",
                            "enum": ["employment", "project", "skill", "achievement", "education"],
                            "description": "Type of knowledge card"
                        ],
                        "proposed_title": [
                            "type": "string",
                            "description": "Specific, descriptive title for the card"
                        ],
                        "evidence_strength": [
                            "type": "string",
                            "enum": ["primary", "supporting", "mention"],
                            "description": "How strong is this document as evidence for this card"
                        ],
                        "evidence_locations": [
                            "type": "array",
                            "items": ["type": "string"],
                            "description": "Where in the document this evidence appears"
                        ],
                        "key_facts": [
                            "type": "array",
                            "items": ["type": "string"],
                            "description": "Specific facts with numbers/names preserved"
                        ],
                        "technologies": [
                            "type": "array",
                            "items": ["type": "string"],
                            "description": "Technologies, tools, or methods mentioned"
                        ],
                        "quantified_outcomes": [
                            "type": "array",
                            "items": ["type": "string"],
                            "description": "Measurable outcomes or metrics"
                        ],
                        "date_range": [
                            "type": "string",
                            "description": "Time period if applicable (YYYY-YYYY format)"
                        ],
                        "cross_references": [
                            "type": "array",
                            "items": ["type": "string"],
                            "description": "Other card titles this relates to"
                        ],
                        "extraction_notes": [
                            "type": "string",
                            "description": "Any special handling needed for extraction"
                        ]
                    ],
                    "required": ["card_type", "proposed_title", "evidence_strength", "evidence_locations", "key_facts", "technologies", "quantified_outcomes", "cross_references"]
                ]
            ]
        ],
        "required": ["document_type", "cards"]
    ]
}
