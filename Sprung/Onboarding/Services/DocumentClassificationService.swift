//
//  DocumentClassificationService.swift
//  Sprung
//
//  Service for classifying documents to determine extraction strategy.
//

import Foundation

/// Service for classifying documents to determine optimal extraction strategy
actor DocumentClassificationService {
    private var llmFacade: LLMFacade?

    init(llmFacade: LLMFacade?) {
        self.llmFacade = llmFacade
        Logger.info("📋 DocumentClassificationService initialized", category: .ai)
    }

    func updateLLMFacade(_ facade: LLMFacade?) {
        self.llmFacade = facade
    }

    /// Classify a document based on its content
    /// - Parameters:
    ///   - content: Extracted text content (or preview for large docs)
    ///   - filename: Original filename
    /// - Returns: DocumentClassification result
    func classify(content: String, filename: String) async throws -> DocumentClassification {
        guard let facade = llmFacade else {
            Logger.warning("⚠️ LLMFacade not configured, using default classification", category: .ai)
            return DocumentClassification.default(filename: filename)
        }

        let preview = String(content.prefix(3000))
        let prompt = DocumentClassificationPrompts.classificationPrompt(
            filename: filename,
            preview: preview
        )

        Logger.info("📋 Classifying document: \(filename)", category: .ai)

        // Call LLM for classification and parse JSON response
        let jsonString = try await facade.generateStructuredJSON(prompt: prompt)

        guard let jsonData = jsonString.data(using: .utf8) else {
            Logger.warning("⚠️ Invalid JSON response for classification, using default", category: .ai)
            return DocumentClassification.default(filename: filename)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        do {
            let classification = try decoder.decode(DocumentClassification.self, from: jsonData)
            Logger.info("✅ Document classified as: \(classification.documentType.rawValue)", category: .ai)
            return classification
        } catch {
            Logger.warning("⚠️ Failed to decode classification JSON: \(error.localizedDescription)", category: .ai)
            return DocumentClassification.default(filename: filename)
        }
    }
}
