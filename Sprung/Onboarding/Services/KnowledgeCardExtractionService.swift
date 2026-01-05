//
//  KnowledgeCardExtractionService.swift
//  Sprung
//
//  Service for extracting narrative knowledge cards from documents.
//  Captures the full story with WHY/JOURNEY/LESSONS structure.
//

import Foundation

/// Service for generating narrative knowledge cards from documents
actor KnowledgeCardExtractionService {
    private var llmFacade: LLMFacade?

    private var modelId: String {
        // Pro for narratives - quality matters
        UserDefaults.standard.string(forKey: "kcExtractionModelId") ?? DefaultModels.geminiPro
    }

    init(llmFacade: LLMFacade?) {
        self.llmFacade = llmFacade
        Logger.info("📖 KnowledgeCardExtractionService initialized", category: .ai)
    }

    func updateLLMFacade(_ facade: LLMFacade?) {
        self.llmFacade = facade
    }

    /// Maximum characters per chunk for narrative extraction
    private let maxChunkSize = 150_000

    /// Extract knowledge cards from a document
    func extractCards(
        documentId: String,
        filename: String,
        content: String
    ) async throws -> [KnowledgeCard] {
        guard let facade = llmFacade else {
            throw KCError.llmNotConfigured
        }

        if content.count > maxChunkSize {
            return try await extractLargeDocument(
                documentId: documentId,
                filename: filename,
                content: content,
                facade: facade
            )
        }

        return try await extractSinglePass(
            documentId: documentId,
            filename: filename,
            content: content,
            facade: facade
        )
    }

    /// Extract cards from a single document pass
    private func extractSinglePass(
        documentId: String,
        filename: String,
        content: String,
        facade: LLMFacade
    ) async throws -> [KnowledgeCard] {
        let prompt = KCExtractionPrompts.extractionPrompt(
            documentId: documentId,
            filename: filename,
            content: content
        )

        let maxAttempts = 3

        for attempt in 1...maxAttempts {
            Logger.info("📖 Extracting narratives from: \(filename) (attempt \(attempt)/\(maxAttempts))", category: .ai)

            do {
                // Use unified structured output API with Gemini backend
                let response: KnowledgeCardExtractionResponse = try await facade.executeStructuredWithDictionarySchema(
                    prompt: prompt,
                    modelId: modelId,
                    as: KnowledgeCardExtractionResponse.self,
                    schema: KCExtractionPrompts.jsonSchema,
                    schemaName: "knowledge_card_extraction",
                    maxOutputTokens: 32768,
                    backend: .gemini
                )
                Logger.info("📖 Extracted \(response.cards.count) narrative cards", category: .ai)
                return response.cards
            } catch {
                Logger.warning("📖 Error on attempt \(attempt): \(error.localizedDescription)", category: .ai)
                if let decodingError = error as? DecodingError {
                    logDecodingError(decodingError)
                }
                if attempt < maxAttempts { continue }
                throw KCError.invalidResponse
            }
        }

        throw KCError.invalidResponse
    }

    /// Extract cards from a large document by chunking at section boundaries
    private func extractLargeDocument(
        documentId: String,
        filename: String,
        content: String,
        facade: LLMFacade
    ) async throws -> [KnowledgeCard] {
        let chunks = chunkAtSectionBoundaries(content, maxSize: maxChunkSize)
        Logger.info("📖 Large document: \(chunks.count) chunks", category: .ai)

        var allCards: [KnowledgeCard] = []

        for (i, chunk) in chunks.enumerated() {
            do {
                let cards = try await extractSinglePass(
                    documentId: documentId,
                    filename: "\(filename) (part \(i + 1))",
                    content: chunk,
                    facade: facade
                )
                allCards.append(contentsOf: cards)
                Logger.info("📖 Chunk \(i + 1)/\(chunks.count): \(cards.count) cards", category: .ai)
            } catch {
                Logger.warning("📖 Chunk \(i + 1) failed: \(error.localizedDescription)", category: .ai)
                // Continue with other chunks
            }
        }

        Logger.info("📖 Total extracted: \(allCards.count) cards from \(chunks.count) chunks", category: .ai)
        return allCards
    }

    /// Log decoding errors for debugging
    private func logDecodingError(_ error: DecodingError) {
        switch error {
        case .keyNotFound(let key, let context):
            Logger.error("❌ Missing key '\(key.stringValue)' at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))", category: .ai)
        case .typeMismatch(let type, let context):
            Logger.error("❌ Type mismatch for \(type) at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))", category: .ai)
        case .valueNotFound(let type, let context):
            Logger.error("❌ Value not found for \(type) at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))", category: .ai)
        case .dataCorrupted(let context):
            Logger.error("❌ Data corrupted at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))", category: .ai)
        @unknown default:
            Logger.error("❌ Unknown decoding error", category: .ai)
        }
    }

    /// Chunk content at section boundaries
    private func chunkAtSectionBoundaries(_ content: String, maxSize: Int) -> [String] {
        let pattern = #"\n(?=---|===|Chapter |\\d+\\.\\s+[A-Z]|#{1,3}\\s)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [content]
        }

        let range = NSRange(content.startIndex..., in: content)
        var sections: [String] = []
        var lastEnd = content.startIndex

        regex.enumerateMatches(in: content, range: range) { match, _, _ in
            if let match = match, let r = Range(match.range, in: content) {
                sections.append(String(content[lastEnd..<r.lowerBound]))
                lastEnd = r.lowerBound
            }
        }
        sections.append(String(content[lastEnd...]))

        var chunks: [String] = []
        var current = ""
        for section in sections {
            if current.count + section.count > maxSize && !current.isEmpty {
                chunks.append(current)
                current = section
            } else {
                current += section
            }
        }
        if !current.isEmpty { chunks.append(current) }

        return chunks
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
