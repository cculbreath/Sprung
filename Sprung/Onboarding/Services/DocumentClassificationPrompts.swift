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
    /// Loads template from Resources/Prompts/document_classification_prompt.txt
    /// - Parameters:
    ///   - filename: Original filename
    ///   - preview: First ~3000 characters of content
    /// - Returns: Formatted prompt string
    static func classificationPrompt(filename: String, preview: String) -> String {
        PromptLibrary.substitute(
            template: PromptLibrary.documentClassificationTemplate,
            replacements: [
                "FILENAME": filename,
                "PREVIEW": preview
            ]
        )
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
