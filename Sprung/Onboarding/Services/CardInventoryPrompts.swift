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

    /// Build the inventory prompt for a document with extracted text.
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

    /// Build the inventory prompt for direct PDF analysis.
    /// The PDF is attached separately via Files API, so this prompt focuses on instructions.
    /// - Parameters:
    ///   - documentId: Unique document identifier
    ///   - filename: Document filename
    /// - Returns: Formatted prompt string for PDF analysis
    static func inventoryPromptForPDF(
        documentId: String,
        filename: String
    ) -> String {
        return """
        Analyze the attached PDF document and generate a comprehensive inventory of potential knowledge cards.

        Document ID: \(documentId)
        Filename: \(filename)

        ## Your Task

        Read the ENTIRE document thoroughly. This is a professional document that may contain:
        - Employment history and job responsibilities
        - Projects and technical achievements
        - Skills and technologies used
        - Educational background
        - Research, publications, or academic work
        - Quantified outcomes and metrics

        ## Document Type Classification

        First, determine the document type from the content. Valid types are:
        - resume, personnel_file, technical_report, cover_letter, reference_letter
        - dissertation, grant_proposal, project_documentation, git_analysis
        - presentation, certificate, transcript, or other

        ## Card Types to Identify

        For each potential knowledge card, determine its type:
        - **employment**: Job positions, roles, responsibilities
        - **project**: Specific projects, initiatives, deliverables
        - **skill**: Technical skills, tools, methodologies, competencies
        - **achievement**: Awards, recognition, quantified accomplishments
        - **education**: Degrees, certifications, training, courses

        ## Extraction Guidelines

        For EACH potential card:
        1. **proposed_title**: Create a specific, descriptive title (e.g., "Senior Software Engineer at Google" not just "Software Engineer")
        2. **evidence_strength**: Rate as "primary" (main source), "supporting" (adds detail), or "mention" (brief reference)
        3. **evidence_locations**: Note where in the document this appears (page numbers, section names, chapter titles)
        4. **key_facts**: Extract specific facts with categories (see categories below)
        5. **technologies**: List all technologies, tools, frameworks, methodologies mentioned
        6. **quantified_outcomes**: Capture ALL metrics, percentages, dollar amounts, scale indicators
        7. **cross_references**: Note relationships to other potential cards

        ## Key Facts Format
        Each key_fact should be a string in the format: "[CATEGORY] fact statement"

        Categories for R&D/academic work:
        - [RESEARCH] for hypothesis, experimental design, methodology, data analysis, results

        Categories for professional/industry work:
        - [LEADERSHIP], [ACHIEVEMENT], [TECHNICAL], [RESPONSIBILITY], [IMPACT], [COLLABORATION], [GENERAL]

        Example: "[LEADERSHIP] Managed cross-functional team of 12 engineers across 3 time zones"

        ## Important

        - Be EXHAUSTIVE - capture every potential card, even if evidence is limited
        - Preserve specificity - keep exact numbers, dates, company names, project names
        - For long documents (dissertations, reports), identify MULTIPLE cards from different sections
        - Include both explicit achievements and implied skills from context
        """
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
                            "description": "Specific facts as strings in format '[CATEGORY] statement' where CATEGORY is one of: leadership, achievement, technical, responsibility, impact, collaboration, research, general",
                            "items": ["type": "string"]
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
