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
    /// - Parameter voiceAnchor: Optional voice-anchoring text (Phase 1 voice
    ///   profile + writing-sample excerpts), injected into the user content
    ///   AFTER the cached source block. Must be byte-stable across the
    ///   narrative passes of an analysis run so the anchored prefix caches.
    func extractCards(
        documentId: String,
        filename: String,
        source: DocumentAnalysisSource,
        voiceAnchor: String? = nil,
        sourceKind: ExtractionSourceKind = .document
    ) async throws -> [KnowledgeCard] {
        guard let facade = llmFacade else {
            throw KCError.llmNotConfigured
        }

        let modelId = try getModelId()
        let instructions = KCExtractionPrompts.extractionPrompt(
            documentId: documentId,
            filename: filename,
            isPagedSource: source.isPaged,
            sourceKind: sourceKind
        )

        let maxAttempts = 3

        for attempt in 1...maxAttempts {
            Logger.info("📖 Extracting narratives from: \(filename) (attempt \(attempt)/\(maxAttempts))", category: .ai)

            do {
                let response: KnowledgeCardExtractionResponse = try await facade.executeStructuredWithAnthropicBlocks(
                    systemContent: DocumentAnalysisPrompts.systemBlocks,
                    userBlocks: DocumentAnalysisPrompts.userBlocks(
                        source: source, voiceAnchor: voiceAnchor, instructions: instructions
                    ),
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
                // Retry ONLY transient network conditions. A malformed/schema/decode
                // failure or a content error (e.g. an API 400) re-fails identically,
                // so surface it now instead of burning two more passes on it.
                if attempt < maxAttempts, LLMErrorHandler().isTransientNetworkError(error) {
                    continue
                }
                throw error
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
