//
//  DocumentClassificationService.swift
//  Sprung
//
//  Service for classifying documents to determine extraction strategy.
//  Uses Gemini's native structured output mode for guaranteed valid JSON.
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

    /// Classify a document based on its content.
    /// Uses Gemini's native structured output mode with JSON schema for guaranteed valid output.
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

        // Call LLM for classification using Gemini's native structured output
        let jsonString = try await facade.generateStructuredJSON(
            prompt: prompt,
            jsonSchema: DocumentClassificationPrompts.jsonSchema
        )

        // Debug: Log raw JSON to see what Gemini is returning
        Logger.debug("📋 Raw classification JSON: \(jsonString.prefix(2000))", category: .ai)

        guard let jsonData = jsonString.data(using: .utf8) else {
            Logger.warning("⚠️ Invalid JSON response for classification, using default", category: .ai)
            return DocumentClassification.default(filename: filename)
        }

        // Don't use convertFromSnakeCase - we have explicit CodingKeys that handle the mapping
        let decoder = JSONDecoder()

        do {
            let classification = try decoder.decode(DocumentClassification.self, from: jsonData)
            Logger.info("✅ Document classified as: \(classification.documentType.rawValue)", category: .ai)
            return classification
        } catch {
            // Enhanced error logging for debugging schema mismatches
            if let decodingError = error as? DecodingError {
                switch decodingError {
                case .keyNotFound(let key, let context):
                    Logger.warning("⚠️ Classification missing key '\(key.stringValue)' at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))", category: .ai)
                case .typeMismatch(let type, let context):
                    Logger.warning("⚠️ Classification type mismatch for \(type) at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))", category: .ai)
                case .valueNotFound(let type, let context):
                    Logger.warning("⚠️ Classification value not found for \(type) at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))", category: .ai)
                case .dataCorrupted(let context):
                    Logger.warning("⚠️ Classification data corrupted at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))", category: .ai)
                @unknown default:
                    Logger.warning("⚠️ Unknown classification decoding error: \(error.localizedDescription)", category: .ai)
                }
            } else {
                Logger.warning("⚠️ Failed to decode classification JSON: \(error.localizedDescription)", category: .ai)
            }
            Logger.debug("📋 Raw JSON was: \(jsonString.prefix(1000))...", category: .ai)
            return DocumentClassification.default(filename: filename)
        }
    }
}
