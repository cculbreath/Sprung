//
//  CardInventoryPrompts.swift
//  Sprung
//
//  Prompt builder for card inventory generation.
//

import Foundation

/// Builds prompts for document card inventory generation
enum CardInventoryPrompts {

    /// Build the inventory prompt for a document
    /// - Parameters:
    ///   - documentId: Unique document identifier
    ///   - documentType: Document type from classification
    ///   - classification: Full classification result
    ///   - content: Extracted document content
    /// - Returns: Formatted prompt string
    static func inventoryPrompt(
        documentId: String,
        documentType: String,
        classification: DocumentClassification,
        content: String
    ) -> String {
        // Encode classification to JSON string
        let classificationJSON: String
        if let data = try? JSONEncoder().encode(classification),
           let jsonString = String(data: data, encoding: .utf8) {
            classificationJSON = jsonString
        } else {
            classificationJSON = "{}"
        }

        return PromptLibrary.substitute(
            template: PromptLibrary.cardInventoryTemplate,
            replacements: [
                "DOC_ID": documentId,
                "FILENAME": documentId,  // Could be filename if available
                "DOCUMENT_TYPE": documentType,
                "CLASSIFICATION_JSON": classificationJSON,
                "EXTRACTED_CONTENT": content
            ]
        )
    }
}
