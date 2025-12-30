//
//  DocumentExtractionPrompts.swift
//  Sprung
//
//  Centralized prompts for document extraction and summarization.
//  Used by GoogleAIService for PDF/document text extraction and summary generation.
//

import Foundation

enum DocumentExtractionPrompts {

    // MARK: - JSON Schema for Gemini Structured Output

    /// JSON Schema for DocumentSummary to enable Gemini structured output mode
    static let summaryJsonSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "document_type": [
                "type": "string",
                "description": "Type of document (resume, performance_review, project_doc, cover_letter, recommendation, technical_report, grant_proposal, other)"
            ],
            "brief_description": [
                "type": "string",
                "description": "Brief one-line description (~10 words) for quick reference"
            ],
            "summary": [
                "type": "string",
                "description": "~500 word narrative summary of the document content"
            ],
            "time_period": [
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
            "relevance_hints": [
                "type": "string",
                "description": "Hints about what types of knowledge cards this doc could support"
            ]
        ],
        "required": ["document_type", "brief_description", "summary", "time_period", "companies", "roles", "skills", "achievements", "relevance_hints"]
    ]

    // MARK: - Extraction Prompts

    /// Default prompt for PDF text extraction.
    /// Instructs the model to produce a detailed, structured transcription
    /// that preserves the original content for downstream processing.
    static let defaultExtractionPrompt: String = {
        PromptLibrary.documentExtraction
    }()

    static func promptWithDocumentHints(filename: String, pageCount: Int?, sizeInBytes: Int) -> String {
        let sizeMB = Double(sizeInBytes) / 1_048_576.0
        let pageCountString = pageCount.map(String.init) ?? "unknown"

        return """
        Document hints (use to choose verbatim vs summary):
        - filename: \(filename)
        - page_count: \(pageCountString)
        - size_mb: \(String(format: "%.1f", sizeMB))

        If page_count is unknown, infer document length from structure and avoid runaway verbatim transcription. Always respect the size cap.

        \(defaultExtractionPrompt)
        """
    }

    // MARK: - Summarization Prompts

    /// Prompt for document summarization.
    /// Generates structured JSON output with summary, document type, metadata.
    /// Used to create lightweight context for the main LLM coordinator.
    static func summaryPrompt(filename: String, content: String) -> String {
        PromptLibrary.substitute(
            template: PromptLibrary.documentSummaryTemplate,
            replacements: [
                "FILENAME": filename,
                "CONTENT": String(content.prefix(100000))
            ]
        )
    }
}
