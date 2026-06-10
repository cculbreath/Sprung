//
//  SkillBankPrompts.swift
//  Sprung
//
//  Prompt builder and JSON schema for skill bank extraction.
//  Uses Anthropic structured output (output_config schema) for guaranteed valid JSON.
//

import Foundation

/// Builds prompts and schemas for skill bank extraction
enum SkillBankPrompts {

    /// Build the extraction instructions for a document. The document content
    /// itself is provided as a preceding content block (PDF document block or
    /// cached text block), not inlined into the prompt.
    /// Loads template from Resources/Prompts/skill_bank_extraction.txt
    /// - Parameter isPagedSource: true when the source is page-addressable (PDF);
    ///   evidence locations must then be page-anchored ("p. 14", "p. 3, Fig. 2").
    static func extractionPrompt(
        documentId: String,
        filename: String,
        isPagedSource: Bool
    ) -> String {
        let locationGuidance = isPagedSource
            ? "Page-anchored reference — every location MUST cite its page (\"p. 14\", \"p. 3, Fig. 2\"), and quoted evidence cites the page it appears on"
            : "Where in document (page, section, or general area)"
        return PromptLibrary.substitute(
            template: PromptLibrary.skillBankExtractionTemplate,
            replacements: [
                "DOC_ID": documentId,
                "FILENAME": filename,
                "LOCATION_GUIDANCE": locationGuidance
            ]
        )
    }

    /// JSON Schema for skill extraction - enforced via Anthropic structured output (output_config).
    /// Category is a free-form string. Universal anchors and LLM-proposed categories
    /// are guided by the prompt text, not constrained by an enum in the schema.
    static let jsonSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "skills": [
                "type": "array",
                "description": "List of extracted skills with evidence",
                "items": [
                    "type": "object",
                    "properties": [
                        "id": [
                            "type": "string",
                            "description": "Unique identifier (UUID format)"
                        ],
                        "canonical": [
                            "type": "string",
                            "description": "Primary display name for the skill (e.g., 'Python')"
                        ],
                        "ats_variants": [
                            "type": "array",
                            "items": ["type": "string"],
                            "description": "Alternative names/spellings for ATS matching — variants of this one skill, never emitted as separate skill entries"
                        ],
                        "category": [
                            "type": "string",
                            "description": "Category for organizing skills. Use universal anchors (Tools & Software, Leadership & Management, Communication & Writing, Methodologies & Processes) or propose 2-5 domain-appropriate categories that fit the user's profile. Keep total categories between 6-10."
                        ],
                        "proficiency": [
                            "type": "string",
                            "enum": ["expert", "proficient", "familiar"],
                            "description": "Proficiency level based on evidence"
                        ],
                        "evidence": [
                            "type": "array",
                            "description": "Evidence of this skill from the document",
                            "items": [
                                "type": "object",
                                "properties": [
                                    "document_id": [
                                        "type": "string",
                                        "description": "Document identifier"
                                    ],
                                    "location": [
                                        "type": "string",
                                        "description": "Where in document (page, section)"
                                    ],
                                    "context": [
                                        "type": "string",
                                        "description": "Brief description of how skill was used (10-30 words); prefix with 'Implied:' for skills implied by context rather than explicitly demonstrated"
                                    ],
                                    "strength": [
                                        "type": "string",
                                        "enum": ["primary", "supporting", "mention"],
                                        "description": "How strongly evidence demonstrates skill; implied skills are capped at supporting or mention, never primary"
                                    ]
                                ],
                                "required": ["document_id", "location", "context", "strength"]
                            ]
                        ],
                        "related_skills": [
                            "type": "array",
                            "items": ["type": "string"],
                            "description": "IDs of related skills"
                        ],
                        "last_used": [
                            "type": "string",
                            "description": "When skill was last used (year or 'present')"
                        ]
                    ],
                    "required": ["id", "canonical", "ats_variants", "category", "proficiency", "evidence"]
                ]
            ]
        ],
        "required": ["skills"]
    ]
}
