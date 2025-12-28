//
//  CardInventoryService.swift
//  Sprung
//
//  Service for generating per-document card inventories.
//  Uses Gemini's native structured output mode for guaranteed valid JSON.
//

import Foundation

/// Service for generating per-document card inventories
actor CardInventoryService {
    private var llmFacade: LLMFacade?

    init(llmFacade: LLMFacade?) {
        self.llmFacade = llmFacade
        Logger.info("📦 CardInventoryService initialized", category: .ai)
    }

    func updateLLMFacade(_ facade: LLMFacade?) {
        self.llmFacade = facade
    }

    /// Generate card inventory for a document.
    /// Uses Gemini's native structured output mode with JSON schema for guaranteed valid output.
    /// - Parameters:
    ///   - documentId: Unique document identifier
    ///   - filename: Original filename
    ///   - content: Full extracted text
    ///   - classification: Document classification result
    /// - Returns: DocumentInventory with proposed cards
    func inventoryDocument(
        documentId: String,
        filename: String,
        content: String,
        classification: DocumentClassification
    ) async throws -> DocumentInventory {
        guard let facade = llmFacade else {
            throw CardInventoryError.llmNotConfigured
        }

        let prompt = CardInventoryPrompts.inventoryPrompt(
            documentId: documentId,
            filename: filename,
            documentType: classification.documentType.rawValue,
            classification: classification,
            content: content
        )

        Logger.info("📦 Generating card inventory for: \(filename)", category: .ai)

        // Call LLM using Gemini's native structured output with schema
        let jsonString = try await facade.generateStructuredJSON(
            prompt: prompt,
            jsonSchema: CardInventoryPrompts.jsonSchema
        )

        guard let jsonData = jsonString.data(using: .utf8) else {
            throw CardInventoryError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601

        do {
            let inventory = try decoder.decode(DocumentInventory.self, from: jsonData)
            Logger.info("✅ Card inventory generated: \(inventory.proposedCards.count) potential cards", category: .ai)
            return inventory
        } catch {
            // Enhanced error logging for debugging schema mismatches
            if let decodingError = error as? DecodingError {
                switch decodingError {
                case .keyNotFound(let key, let context):
                    Logger.error("❌ Missing key '\(key.stringValue)' at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))", category: .ai)
                case .typeMismatch(let type, let context):
                    Logger.error("❌ Type mismatch for \(type) at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))", category: .ai)
                case .valueNotFound(let type, let context):
                    Logger.error("❌ Value not found for \(type) at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))", category: .ai)
                case .dataCorrupted(let context):
                    Logger.error("❌ Data corrupted at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))", category: .ai)
                @unknown default:
                    Logger.error("❌ Unknown decoding error: \(error.localizedDescription)", category: .ai)
                }
            } else {
                Logger.error("❌ Failed to decode inventory JSON: \(error.localizedDescription)", category: .ai)
            }
            Logger.debug("📦 Raw JSON was: \(jsonString.prefix(1000))...", category: .ai)
            throw CardInventoryError.invalidResponse
        }
    }

    enum CardInventoryError: Error, LocalizedError {
        case llmNotConfigured
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .llmNotConfigured:
                return "LLM facade is not configured"
            case .invalidResponse:
                return "Invalid response from LLM"
            }
        }
    }
}
