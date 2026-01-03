//
//  KCExtractionPrompts.swift
//  Sprung
//
//  Prompt builder and JSON schema for narrative knowledge card extraction.
//  Uses Gemini's native structured output mode for guaranteed valid JSON.
//

import Foundation

/// Builds prompts and schemas for narrative knowledge card extraction
enum KCExtractionPrompts {

    /// Build the extraction prompt for a document
    /// Loads template from Resources/Prompts/kc_extraction.txt
    static func extractionPrompt(
        documentId: String,
        filename: String,
        content: String
    ) -> String {
        return PromptLibrary.substitute(
            template: PromptLibrary.kcExtractionTemplate,
            replacements: [
                "DOC_ID": documentId,
                "FILENAME": filename,
                "EXTRACTED_CONTENT": content
            ]
        )
    }

    /// JSON Schema for narrative KC extraction - used by Gemini's native structured output
    static let jsonSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "document_type": [
                "type": "string",
                "description": "Type of document (e.g., dissertation, resume, project_documentation)"
            ],
            "cards": [
                "type": "array",
                "description": "List of extracted narrative knowledge cards",
                "items": [
                    "type": "object",
                    "properties": [
                        "id": [
                            "type": "string",
                            "description": "Unique identifier (UUID format)"
                        ],
                        "card_type": [
                            "type": "string",
                            "enum": ["employment", "project", "achievement", "education"],
                            "description": "Type of knowledge card (NOT skill - skills go to SkillBank)"
                        ],
                        "title": [
                            "type": "string",
                            "description": "Specific, descriptive title for the card"
                        ],
                        "narrative": [
                            "type": "string",
                            "description": "500-2000 word story capturing WHY/JOURNEY/LESSONS with author's voice"
                        ],
                        "evidence_anchors": [
                            "type": "array",
                            "description": "Links to source documents",
                            "items": [
                                "type": "object",
                                "properties": [
                                    "document_id": [
                                        "type": "string",
                                        "description": "Document identifier"
                                    ],
                                    "location": [
                                        "type": "string",
                                        "description": "Page numbers or section references"
                                    ],
                                    "verbatim_excerpt": [
                                        "type": "string",
                                        "description": "Verbatim excerpt capturing voice (20-50 words)"
                                    ]
                                ],
                                "required": ["document_id", "location"]
                            ]
                        ],
                        "extractable": [
                            "type": "object",
                            "description": "Metadata for job matching",
                            "properties": [
                                "domains": [
                                    "type": "array",
                                    "items": ["type": "string"],
                                    "description": "Fields of expertise (not individual skills)"
                                ],
                                "scale": [
                                    "type": "array",
                                    "items": ["type": "string"],
                                    "description": "Quantified elements (numbers, metrics, scope)"
                                ],
                                "keywords": [
                                    "type": "array",
                                    "items": ["type": "string"],
                                    "description": "High-level terms for job matching"
                                ]
                            ]
                        ],
                        "date_range": [
                            "type": "string",
                            "description": "Time period if applicable (YYYY-YYYY format)"
                        ],
                        "organization": [
                            "type": "string",
                            "description": "Company, institution, or organization"
                        ],
                        "related_card_ids": [
                            "type": "array",
                            "items": ["type": "string"],
                            "description": "IDs of related cards"
                        ]
                    ],
                    "required": ["id", "card_type", "title", "narrative", "evidence_anchors"]
                ]
            ]
        ],
        "required": ["document_type", "cards"]
    ]
}
