//
//  SkillBankPrompts.swift
//  Sprung
//
//  Prompt builder and JSON schema for skill bank extraction.
//  Uses Gemini's native structured output mode for guaranteed valid JSON.
//

import Foundation

/// Builds prompts and schemas for skill bank extraction
enum SkillBankPrompts {

    /// Build the extraction prompt for a document
    /// Loads template from Resources/Prompts/skill_bank_extraction.txt
    static func extractionPrompt(
        documentId: String,
        filename: String,
        content: String
    ) -> String {
        return PromptLibrary.substitute(
            template: PromptLibrary.skillBankExtractionTemplate,
            replacements: [
                "DOC_ID": documentId,
                "FILENAME": filename,
                "EXTRACTED_CONTENT": content
            ]
        )
    }

    /// JSON Schema for skill extraction - used by Gemini's native structured output
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
                            "description": "Alternative names/spellings for ATS matching"
                        ],
                        "category": [
                            "type": "string",
                            "enum": ["Programming Languages", "Frameworks & Libraries", "Tools & Platforms",
                                    "Hardware & Electronics", "Fabrication & Manufacturing",
                                    "Scientific & Analysis", "Leadership & Communication", "Domain Expertise"],
                            "description": "Category for organizing skills"
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
                                        "description": "Brief description of how skill was used (10-30 words)"
                                    ],
                                    "strength": [
                                        "type": "string",
                                        "enum": ["primary", "supporting", "mention"],
                                        "description": "How strongly evidence demonstrates skill"
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
