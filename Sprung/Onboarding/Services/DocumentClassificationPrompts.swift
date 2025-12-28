//
//  DocumentClassificationPrompts.swift
//  Sprung
//
//  Prompt builder for document classification.
//

import Foundation

/// Builds prompts for document classification
enum DocumentClassificationPrompts {

    /// Build the classification prompt for a document
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
}
