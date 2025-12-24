//
//  DocumentExtractionPrompts.swift
//  Sprung
//
//  Centralized prompts for document extraction and summarization.
//  Used by GoogleAIService for PDF/document text extraction and summary generation.
//

import Foundation

enum DocumentExtractionPrompts {

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
