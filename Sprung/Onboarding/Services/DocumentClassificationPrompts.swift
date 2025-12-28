//
//  DocumentClassificationPrompts.swift
//  Sprung
//
//  Prompt builder and JSON schema for document classification.
//  Uses Gemini's native structured output mode for guaranteed valid JSON.
//

import Foundation

/// Builds prompts and schemas for document classification
enum DocumentClassificationPrompts {

    /// Build the classification prompt for a document.
    /// This is a simplified prompt since the JSON schema enforces the output format.
    /// - Parameters:
    ///   - filename: Original filename
    ///   - preview: First ~3000 characters of content
    /// - Returns: Formatted prompt string
    static func classificationPrompt(filename: String, preview: String) -> String {
        """
        Classify this document to determine the optimal extraction strategy for knowledge card generation.

        FILENAME: \(filename)

        CONTENT PREVIEW:
        \(preview)

        ---

        Analyze the document and determine:
        1. The primary document type (resume, personnel_file, technical_report, etc.)
        2. A more specific subtype if applicable (e.g., "WPAF" for a personnel file)
        3. The recommended extraction strategy
        4. Estimated number of knowledge cards that can be extracted by type
        5. Structural hints about the document format
        6. Any special handling requirements

        Document Type Definitions:
        - resume: CV or resume showing work history, education, skills
        - personnel_file: Employee file with reviews, appointment letters, evaluations
        - technical_report: Design docs, consultation reports, technical documentation
        - cover_letter: Job application cover letter
        - reference_letter: Recommendation or reference letter
        - dissertation: Academic thesis or dissertation
        - grant_proposal: Funding proposal (STTR, SBIR, etc.)
        - project_documentation: Project reports, status updates, deliverables
        - git_analysis: Pre-analyzed git repository data
        - presentation: Slides or presentation materials
        - certificate: Professional certification or credential
        - transcript: Academic transcript
        - other: Doesn't fit above categories

        Extraction Strategy Definitions:
        - single_pass: Document can be processed in one pass (short docs, clear structure)
        - sectioned: Break into logical sections, process each (long docs with clear headers)
        - timeline_aware: Multiple roles/periods need timeline context (personnel files, resumes)
        - code_analysis: Already structured code analysis (git_analysis JSON)
        """
    }

    /// JSON Schema for DocumentClassification - used by Gemini's native structured output.
    /// This schema guarantees the LLM response will be valid, parseable JSON.
    static let jsonSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "document_type": [
                "type": "string",
                "enum": ["resume", "personnel_file", "technical_report", "cover_letter",
                         "reference_letter", "dissertation", "grant_proposal",
                         "project_documentation", "git_analysis", "presentation",
                         "certificate", "transcript", "other"],
                "description": "Primary document type classification"
            ],
            "document_subtype": [
                "type": "string",
                "description": "More specific subtype if applicable (e.g., 'WPAF' for personnel_file)"
            ],
            "extraction_strategy": [
                "type": "string",
                "enum": ["single_pass", "sectioned", "timeline_aware", "code_analysis"],
                "description": "Recommended extraction strategy"
            ],
            "estimated_card_yield": [
                "type": "object",
                "properties": [
                    "employment": ["type": "integer", "description": "Estimated employment/job cards"],
                    "project": ["type": "integer", "description": "Estimated project cards"],
                    "skill": ["type": "integer", "description": "Estimated skill cards"],
                    "achievement": ["type": "integer", "description": "Estimated achievement cards"],
                    "education": ["type": "integer", "description": "Estimated education cards"]
                ],
                "required": ["employment", "project", "skill", "achievement", "education"]
            ],
            "structure_hints": [
                "type": "object",
                "properties": [
                    "has_clear_sections": ["type": "boolean", "description": "Document has clear section headers"],
                    "has_timeline_data": ["type": "boolean", "description": "Document contains dated events"],
                    "has_quantitative_data": ["type": "boolean", "description": "Document contains metrics/numbers"],
                    "has_figures": ["type": "boolean", "description": "Document contains figures/diagrams"],
                    "primary_voice": [
                        "type": "string",
                        "enum": ["first_person", "third_person", "institutional", "unknown"],
                        "description": "Primary narrative voice"
                    ]
                ],
                "required": ["has_clear_sections", "has_timeline_data", "has_quantitative_data", "has_figures", "primary_voice"]
            ],
            "special_handling": [
                "type": "array",
                "items": [
                    "type": "string",
                    "enum": ["needs_figure_extraction", "contains_multiple_roles", "spans_multiple_years", "contains_writing_samples"]
                ],
                "description": "Special handling flags for extraction"
            ]
        ],
        "required": ["document_type", "extraction_strategy", "estimated_card_yield", "structure_hints", "special_handling"]
    ]
}
