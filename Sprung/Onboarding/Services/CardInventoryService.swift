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

    /// Private struct for decoding LLM response (excludes client-set fields)
    private struct LLMInventoryResponse: Codable {
        let documentType: String
        let proposedCards: [DocumentInventory.ProposedCardEntry]

        enum CodingKeys: String, CodingKey {
            case documentType = "document_type"
            case proposedCards = "cards"
        }
    }

    init(llmFacade: LLMFacade?) {
        self.llmFacade = llmFacade
        Logger.info("📦 CardInventoryService initialized", category: .ai)
    }

    func updateLLMFacade(_ facade: LLMFacade?) {
        self.llmFacade = facade
    }

    /// Generate card inventory for a document.
    /// Uses Gemini's native structured output mode with JSON schema for guaranteed valid output.
    /// The inventory service now determines document type itself from full content.
    /// - Parameters:
    ///   - documentId: Unique document identifier
    ///   - filename: Original filename
    ///   - content: Full extracted text
    /// - Returns: DocumentInventory with proposed cards
    func inventoryDocument(
        documentId: String,
        filename: String,
        content: String
    ) async throws -> DocumentInventory {
        guard let facade = llmFacade else {
            throw CardInventoryError.llmNotConfigured
        }

        let prompt = CardInventoryPrompts.inventoryPrompt(
            documentId: documentId,
            filename: filename,
            content: content
        )

        Logger.info("📦 Generating card inventory for: \(filename)", category: .ai)

        // Call LLM using Gemini's native structured output with schema
        let jsonString = try await facade.generateStructuredJSON(
            prompt: prompt,
            jsonSchema: CardInventoryPrompts.jsonSchema
        )

        // Log raw JSON to see what Gemini is returning (INFO level for visibility)
        Logger.info("📦 Raw inventory JSON (\(jsonString.count) chars): \(jsonString.prefix(500))...", category: .ai)

        guard let jsonData = jsonString.data(using: .utf8) else {
            throw CardInventoryError.invalidResponse
        }

        // Don't use convertFromSnakeCase - we have explicit CodingKeys that handle the mapping
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            // Decode LLM response (excludes document_id and generated_at)
            let response = try decoder.decode(LLMInventoryResponse.self, from: jsonData)

            // Construct full DocumentInventory with client-side fields
            let inventory = DocumentInventory(
                documentId: documentId,
                documentType: response.documentType,
                proposedCards: response.proposedCards,
                generatedAt: Date()
            )
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
