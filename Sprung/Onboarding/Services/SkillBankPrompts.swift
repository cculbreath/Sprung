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
                        "implied": [
                            "type": "boolean",
                            "description": "True when the skill is only inferred from context (tools, roles, or activities described) rather than explicitly demonstrated in the document"
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
                                        "description": "Brief description of how skill was used (10-30 words); for implied skills, explain what the inference rests on"
                                    ],
                                    "strength": [
                                        "type": "string",
                                        "enum": ["primary", "supporting", "mention"],
                                        "description": "How strongly evidence demonstrates skill; implied skills are capped at supporting or mention, never primary"
                                    ]
                                ],
                                "required": ["document_id", "location", "context", "strength"],
                                "additionalProperties": false
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
                    "required": ["id", "canonical", "ats_variants", "category", "proficiency", "implied", "evidence"],
                    "additionalProperties": false
                ]
            ]
        ],
        "required": ["skills"],
        "additionalProperties": false
    ]

    // MARK: - Curation (post-merge gate)

    /// System prompt for the skill curation gate that runs after cross-document
    /// aggregation, before skills are persisted for user review.
    static let curationSystemPrompt = """
        You are a skill-bank curator. You receive an aggregated skill inventory \
        (merged across multiple documents) and decide which entries to collapse \
        into parent skills and which unsupported implied entries to drop. You \
        return decisions only — you never rewrite skill content.
        """

    /// Build the curation instructions for an aggregated skill list.
    /// The skill list is provided as a JSON array in the same prompt.
    static func curationPrompt(skillsJSON: String) -> String {
        """
        Curate the aggregated skill bank below. Return MERGE and DROP decisions only.

        ## Rules

        1. COLLAPSE over-granular entries into their parent skill.
           If "Python 3", "python scripting", and "Python" appear as separate entries,
           keep ONE entry (the most canonical) and absorb the others. The absorbed
           entries' names become ATS variants of the surviving skill.
        2. ATS variants belong on ONE skill, never as separate skills.
           Abbreviation pairs ("ML" / "Machine Learning"), spelling/capitalization
           variants, and tool-version variants are one skill each.
        3. DROP implied skills with no supporting evidence beyond the inference itself.
           A skill with `implied: true` whose evidence is only the inference that
           produced it (no independent demonstration anywhere in the bank) must be
           dropped. Keep an implied skill only if at least one evidence entry shows
           actual use, or another document independently corroborates it.
        4. Do NOT merge genuinely distinct skills (e.g., "PyTorch" is not a variant
           of "Python"; "Team leadership" is not a variant of "Project management").
        5. When in doubt about a merge, leave the entries separate. When in doubt
           about dropping an implied skill, drop it — unsupported inferences dilute
           the bank.

        Reference skills by their `id` values exactly as given.

        ## Aggregated Skill Bank

        ```json
        \(skillsJSON)
        ```

        Return your decisions now.
        """
    }

    /// JSON Schema for the curation decision response.
    static let curationSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "merges": [
                "type": "array",
                "description": "Groups of over-granular entries collapsed into a surviving parent skill",
                "items": [
                    "type": "object",
                    "properties": [
                        "intoSkillId": [
                            "type": "string",
                            "description": "ID of the surviving skill"
                        ],
                        "absorbedSkillIds": [
                            "type": "array",
                            "items": ["type": "string"],
                            "description": "IDs of entries collapsed into the surviving skill (do not include intoSkillId)"
                        ],
                        "canonical": [
                            "type": "string",
                            "description": "Optional improved canonical name for the surviving skill"
                        ],
                        "reasoning": [
                            "type": "string",
                            "description": "One-line justification for the collapse"
                        ]
                    ],
                    "required": ["intoSkillId", "absorbedSkillIds", "reasoning"],
                    "additionalProperties": false
                ]
            ],
            "drops": [
                "type": "array",
                "description": "Implied skills dropped for lacking evidence beyond the inference itself",
                "items": [
                    "type": "object",
                    "properties": [
                        "skillId": [
                            "type": "string",
                            "description": "ID of the skill to drop"
                        ],
                        "reason": [
                            "type": "string",
                            "description": "Why the implied skill has no independent support"
                        ]
                    ],
                    "required": ["skillId", "reason"],
                    "additionalProperties": false
                ]
            ]
        ],
        "required": ["merges", "drops"],
        "additionalProperties": false
    ]
}
