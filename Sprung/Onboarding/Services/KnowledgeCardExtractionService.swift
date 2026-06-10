//
//  KnowledgeCardExtractionService.swift
//  Sprung
//
//  Service for extracting narrative knowledge cards from documents.
//  Captures the full story with WHY/JOURNEY/LESSONS structure.
//  Uses Anthropic structured output against a cached source block — either
//  the actual PDF (Files API document block) or text.
//

import Foundation
import SwiftOpenAI

/// Service for generating narrative knowledge cards from documents
actor KnowledgeCardExtractionService {
    private var llmFacade: LLMFacade?

    private func getModelId() throws -> String {
        try AnthropicDocumentAnalysisService.configuredModelId(operationName: "Knowledge Card Extraction")
    }

    init(llmFacade: LLMFacade?) {
        self.llmFacade = llmFacade
        Logger.info("📖 KnowledgeCardExtractionService initialized", category: .ai)
    }

    func updateLLMFacade(_ facade: LLMFacade?) {
        self.llmFacade = facade
    }

    /// Extract knowledge cards from raw document text.
    /// Text documents are capped at 200K characters upstream and go in one pass.
    func extractCards(
        documentId: String,
        filename: String,
        content: String
    ) async throws -> [KnowledgeCard] {
        try await extractCards(
            documentId: documentId,
            filename: filename,
            source: .text(AnthropicDocumentAnalysisService.sourceTextBlock(filename: filename, text: content))
        )
    }

    /// Extract knowledge cards from an analysis source (uploaded PDF or text block).
    func extractCards(
        documentId: String,
        filename: String,
        source: DocumentAnalysisSource
    ) async throws -> [KnowledgeCard] {
        guard let facade = llmFacade else {
            throw KCError.llmNotConfigured
        }

        let modelId = try getModelId()
        let instructions = KCExtractionPrompts.extractionPrompt(
            documentId: documentId,
            filename: filename,
            isPagedSource: source.isPaged
        )

        let maxAttempts = 3

        for attempt in 1...maxAttempts {
            Logger.info("📖 Extracting narratives from: \(filename) (attempt \(attempt)/\(maxAttempts))", category: .ai)

            do {
                let response: KnowledgeCardExtractionResponse = try await facade.executeStructuredWithAnthropicBlocks(
                    systemContent: DocumentAnalysisPrompts.systemBlocks,
                    userBlocks: DocumentAnalysisPrompts.userBlocks(source: source, instructions: instructions),
                    modelId: modelId,
                    responseType: KnowledgeCardExtractionResponse.self,
                    schema: KCExtractionPrompts.jsonSchema,
                    maxTokens: 32768
                )
                Logger.info("📖 Extracted \(response.cards.count) narrative cards", category: .ai)
                return response.cards
            } catch let error as ModelConfigurationError {
                throw error
            } catch {
                Logger.warning("📖 Error on attempt \(attempt): \(error.localizedDescription)", category: .ai)
                if attempt < maxAttempts { continue }
                throw KCError.invalidResponse
            }
        }

        throw KCError.invalidResponse
    }

    enum KCError: Error, LocalizedError {
        case llmNotConfigured
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .llmNotConfigured: return "LLM not configured"
            case .invalidResponse: return "Invalid response"
            }
        }
    }
}

// MARK: - Response Types

/// Response type for knowledge card extraction
struct KnowledgeCardExtractionResponse: Codable {
    let cards: [KnowledgeCard]
}
