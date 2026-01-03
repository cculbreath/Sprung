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
        UserDefaults.standard.string(forKey: "kcExtractionModelId") ?? "gemini-2.5-pro"
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

            let jsonString: String
            do {
                jsonString = try await facade.generateStructuredJSON(
                    prompt: prompt,
                    maxOutputTokens: 32768,
                    jsonSchema: KCExtractionPrompts.jsonSchema
                )
            } catch {
                if attempt < maxAttempts {
                    Logger.warning("📖 API error on attempt \(attempt), retrying: \(error.localizedDescription)", category: .ai)
                    continue
                }
                throw error
            }

            // Validate response
            if isGarbageResponse(jsonString) {
                Logger.warning("📖 Garbage response detected (attempt \(attempt))", category: .ai)
                if attempt < maxAttempts { continue }
                throw KCError.garbageResponse
            }

            // Decode response
            guard let jsonData = jsonString.data(using: .utf8) else {
                throw KCError.invalidResponse
            }

            do {
                let response = try JSONDecoder().decode(KnowledgeCardExtractionResponse.self, from: jsonData)
                Logger.info("📖 Extracted \(response.cards.count) narrative cards", category: .ai)
                return response.cards
            } catch {
                Logger.error("❌ Failed to decode KC extraction: \(error.localizedDescription)", category: .ai)
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

    /// Check for garbage responses
    private func isGarbageResponse(_ response: String) -> Bool {
        if response.contains(String(repeating: "\n", count: 20)) {
            return true
        }

        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "{}" || trimmed == "[]" {
            return true
        }

        let nonWhitespaceCount = response.filter { !$0.isWhitespace }.count
        let contentRatio = Double(nonWhitespaceCount) / Double(max(1, response.count))
        if response.count > 1000 && contentRatio < 0.3 {
            return true
        }

        return false
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
        case garbageResponse

        var errorDescription: String? {
            switch self {
            case .llmNotConfigured: return "LLM not configured"
            case .invalidResponse: return "Invalid response"
            case .garbageResponse: return "Gemini returned garbage response"
            }
        }
    }
}
