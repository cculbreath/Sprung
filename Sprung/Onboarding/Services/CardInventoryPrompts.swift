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
    /// This is used with Gemini's native structured output mode.
    /// - Parameters:
    ///   - documentId: Unique document identifier
    ///   - filename: Document filename
    ///   - documentType: Document type from classification
    ///   - classification: Full classification result
    ///   - content: Extracted document content
    /// - Returns: Formatted prompt string
    static func inventoryPrompt(
        documentId: String,
        filename: String,
        documentType: String,
        classification: DocumentClassification,
        content: String
    ) -> String {
        """
        Analyze this document and identify ALL distinct knowledge cards that can be extracted.

        ## Document Context
        - Document ID: \(documentId)
        - Filename: \(filename)
        - Type: \(documentType)
        - Estimated card yield: employment=\(classification.estimatedCardYield.employment), project=\(classification.estimatedCardYield.project), skill=\(classification.estimatedCardYield.skill), achievement=\(classification.estimatedCardYield.achievement), education=\(classification.estimatedCardYield.education)

        ## Document Content
        \(content)

        ---

        ## Your Task

        Identify every distinct knowledge card this document provides evidence for. Be EXHAUSTIVE — it's better to propose too many cards than to miss important content.

        ## Card Types

        **employment**: A role/position with employer, title, dates
        - One card per distinct role (promotions = separate cards if responsibilities changed significantly)
        - Include: scope, team, responsibilities, technologies, outcomes

        **project**: A specific initiative, product, system, or deliverable
        - Must be nameable ("Physics Cloud LMS", not "web development work")
        - Include: what it was, your role, technologies, outcomes, timeline

        **skill**: A technical or professional capability
        - Must be demonstrable from this document (not just mentioned)
        - Include: proficiency evidence, contexts where applied, related technologies

        **achievement**: A publication, award, certification, presentation, or notable accomplishment
        - Must be specific and verifiable
        - Include: what, when, where, impact

        **education**: A degree, training program, or credential
        - Include: institution, dates, field, notable details

        ## Evidence Strength Definitions

        - **primary**: This document is THE main source for this card. Contains detailed, first-hand information.
        - **supporting**: This document adds valuable detail but another doc is likely the primary source.
        - **mention**: This document references the topic but with minimal detail.

        ## Critical Rules

        1. Be specific in titles: "Allen-Bradley PLC Control System Design" not "automation work"
        2. Preserve all numbers: "47 microservices", "$2.3M budget", "12-person team"
        3. Preserve all names: project names, tool names, company names
        4. One card per distinct topic: Don't bundle unrelated things
        5. Skills require evidence: Don't list a skill unless this doc demonstrates proficiency
        6. Projects need scope: A project card should describe what was built/delivered
        7. Include implicit skills: If doc shows PLC programming, propose a skill card even if not explicitly listed
        """
    }

    /// JSON Schema for DocumentInventory - used by Gemini's native structured output.
    /// This schema guarantees the LLM response will be valid, parseable JSON.
    static let jsonSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "document_id": [
                "type": "string",
                "description": "Unique identifier for this document"
            ],
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
            ],
            "generated_at": [
                "type": "string",
                "description": "ISO8601 timestamp when this inventory was generated"
            ]
        ],
        "required": ["document_id", "document_type", "cards", "generated_at"]
    ]
}
