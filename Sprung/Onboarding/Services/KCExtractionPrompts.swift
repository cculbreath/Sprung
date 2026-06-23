//
//  KCExtractionPrompts.swift
//  Sprung
//
//  Prompt builder and JSON schema for narrative knowledge card extraction.
//  Uses Anthropic structured output (output_config schema) for guaranteed valid JSON.
//

import Foundation

/// Builds prompts and schemas for narrative knowledge card extraction
enum KCExtractionPrompts {

    /// Build the extraction instructions for a document. The document content
    /// itself is provided as a preceding content block (PDF document block or
    /// cached text block), not inlined into the prompt.
    /// Loads template from Resources/Prompts/kc_extraction.txt
    /// - Parameter isPagedSource: true when the source is page-addressable (PDF);
    ///   evidence anchors must then be page-anchored ("p. 14", "p. 3, Fig. 2").
    static func extractionPrompt(
        documentId: String,
        filename: String,
        isPagedSource: Bool,
        sourceKind: ExtractionSourceKind = .document
    ) -> String {
        let locationGuidance = isPagedSource
            ? """
            - Locations MUST be page-anchored: cite the page for every anchor ("p. 14", "p. 3, Fig. 2")
            - Every verbatim excerpt must cite the page it appears on
            """
            : "- Page numbers or section references"
        let base = PromptLibrary.substitute(
            template: PromptLibrary.kcExtractionTemplate,
            replacements: [
                "DOC_ID": documentId,
                "FILENAME": filename,
                "LOCATION_GUIDANCE": locationGuidance
            ]
        )
        guard sourceKind == .codeRepository else { return base }
        return base + "\n\n" + codeRepositoryScope
    }

    /// Appended to the card-extraction instructions when the source is a code
    /// repository digest. Cards must describe what the applicant BUILT and the
    /// engineering it demonstrates — never biographical claims lifted from the
    /// repository's domain content. (Instructions are the uncached trailing
    /// block, so this never perturbs the prompt-cache prefix.)
    private static let codeRepositoryScope = """
    ## Code Repository Scope (overrides the generic framing above)

    This source is a digest of SOURCE CODE the applicant authored — not their personal
    document. Extract cards for what the applicant BUILT and the engineering it
    demonstrates:

    - Prefer `project` cards describing the software, its architecture, the hard
      problems solved, and the applicant's authorship — grounded in the code,
      architecture, dependency usage, technical highlights, and skill signals.
    - The repository serves a domain (a business, a field, a client, or the applicant's
      own portfolio). Its README/docs/marketing copy/page text/sample data describe WHAT
      THE SOFTWARE SERVES — that is context, NOT the applicant's experience. Never create
      employment/achievement cards from it, and never restate its claims, audiences,
      credentials, or operational metrics (users served, patients treated, revenue,
      enrollment) as the applicant's own.
    - Building software for a domain demonstrates engineering skill, not domain
      experience: a clinic's website is web engineering, not surgery; a portfolio site's
      copy is context describing the work, not accomplishments to assert as fact.
    - `scale` metadata must reflect the CODEBASE (LOC, modules, dependencies, sustained
      authorship), not domain figures from the content.
    - If a number or claim is only asserted in prose and not demonstrated by the code,
      leave it out.
    """

    /// JSON Schema for narrative KC extraction - enforced via Anthropic structured output (output_config)
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
                                        "description": "Verbatim excerpt showing the author's reasoning and voice, not just achievement statements (20-50 words)"
                                    ]
                                ],
                                "required": ["document_id", "location"],
                                "additionalProperties": false
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
                            ],
                            "additionalProperties": false
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
                    "required": ["id", "card_type", "title", "narrative", "evidence_anchors"],
                    "additionalProperties": false
                ]
            ]
        ],
        "required": ["document_type", "cards"],
        "additionalProperties": false
    ]
}
