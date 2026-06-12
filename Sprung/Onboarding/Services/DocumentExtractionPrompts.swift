//
//  DocumentExtractionPrompts.swift
//  Sprung
//
//  Centralized prompts for document summarization (Anthropic document analysis).
//

import Foundation

enum DocumentExtractionPrompts {

    // MARK: - JSON Schema for Structured Output

    /// JSON Schema for DocumentSummary structured output
    static let summaryJsonSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "documentType": [
                "type": "string",
                "description": "Type of document (resume, performance_review, project_doc, cover_letter, recommendation, technical_report, grant_proposal, other)"
            ],
            "briefDescription": [
                "type": "string",
                "description": "Brief one-line description (~10 words) for quick reference"
            ],
            "summary": [
                "type": "string",
                "description": "~500 word narrative summary of the document content"
            ],
            "timePeriod": [
                "type": "string",
                "description": "Time period covered by the document (e.g., '2019-2023'), empty string if not applicable"
            ],
            "companies": [
                "type": "array",
                "items": ["type": "string"],
                "description": "Companies mentioned in the document"
            ],
            "roles": [
                "type": "array",
                "items": ["type": "string"],
                "description": "Roles/positions mentioned in the document"
            ],
            "skills": [
                "type": "array",
                "items": ["type": "string"],
                "description": "Skills identified in the document"
            ],
            "achievements": [
                "type": "array",
                "items": ["type": "string"],
                "description": "Key achievements mentioned"
            ],
            "relevanceHints": [
                "type": "string",
                "description": "Hints about what types of knowledge cards this doc could support"
            ]
        ],
        "required": ["documentType", "briefDescription", "summary", "timePeriod", "companies", "roles", "skills", "achievements", "relevanceHints"],
        "additionalProperties": false
    ]

    // MARK: - Summarization Prompts

    /// Instructions for document summarization. The document content itself is
    /// provided as a preceding content block (PDF document block or cached text
    /// block), not inlined into the prompt.
    /// Generates structured JSON output with summary, document type, metadata.
    /// Used to create lightweight context for the main LLM coordinator.
    static func summaryInstructions(filename: String) -> String {
        PromptLibrary.substitute(
            template: PromptLibrary.documentSummaryTemplate,
            replacements: [
                "FILENAME": filename
            ]
        )
    }
}
