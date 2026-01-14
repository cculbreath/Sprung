//
//  SkillBankService.swift
//  Sprung
//
//  Service for extracting comprehensive skill inventories from documents.
//  Uses Gemini structured output for guaranteed valid JSON.
//

import Foundation

/// Service for generating per-document skill inventories
actor SkillBankService {
    private var llmFacade: LLMFacade?

    private func getModelId() throws -> String {
        guard let modelId = UserDefaults.standard.string(forKey: "skillBankModelId"), !modelId.isEmpty else {
            throw ModelConfigurationError.modelNotConfigured(
                settingKey: "skillBankModelId",
                operationName: "Skill Bank Extraction"
            )
        }
        return modelId
    }

    init(llmFacade: LLMFacade?) {
        self.llmFacade = llmFacade
        Logger.info("🔧 SkillBankService initialized", category: .ai)
    }

    func updateLLMFacade(_ facade: LLMFacade?) {
        self.llmFacade = facade
    }

    /// Maximum characters per chunk for skill extraction
    private let maxChunkSize = 100_000

    /// Extract skills from a single document
    func extractSkills(
        documentId: String,
        filename: String,
        content: String
    ) async throws -> [Skill] {
        guard let facade = llmFacade else {
            throw SkillBankError.llmNotConfigured
        }

        // For large documents, chunk and merge
        if content.count > maxChunkSize {
            return try await extractSkillsFromLargeDocument(
                documentId: documentId,
                filename: filename,
                content: content,
                facade: facade
            )
        }

        return try await extractSkillsSingleChunk(
            documentId: documentId,
            filename: filename,
            content: content,
            facade: facade
        )
    }

    /// Extract skills from a large document by chunking
    private func extractSkillsFromLargeDocument(
        documentId: String,
        filename: String,
        content: String,
        facade: LLMFacade
    ) async throws -> [Skill] {
        let chunks = chunkContent(content, maxSize: maxChunkSize)
        Logger.info("🔧 Large document (\(content.count) chars) split into \(chunks.count) chunks", category: .ai)

        var allSkills: [Skill] = []

        for (index, chunk) in chunks.enumerated() {
            do {
                let chunkSkills = try await extractSkillsSingleChunk(
                    documentId: documentId,
                    filename: "\(filename) (part \(index + 1))",
                    content: chunk,
                    facade: facade
                )
                allSkills.append(contentsOf: chunkSkills)
                Logger.info("🔧 Chunk \(index + 1)/\(chunks.count): \(chunkSkills.count) skills", category: .ai)
            } catch {
                Logger.warning("🔧 Chunk \(index + 1) failed: \(error.localizedDescription)", category: .ai)
                // Continue with other chunks
            }
        }

        // Deduplicate skills across chunks
        let merged = deduplicateSkills(allSkills)
        Logger.info("🔧 Merged skills: \(merged.count) total from \(chunks.count) chunks", category: .ai)
        return merged
    }

    /// Extract skills from a single chunk
    private func extractSkillsSingleChunk(
        documentId: String,
        filename: String,
        content: String,
        facade: LLMFacade
    ) async throws -> [Skill] {
        let modelId = try getModelId()
        let prompt = SkillBankPrompts.extractionPrompt(
            documentId: documentId,
            filename: filename,
            content: content
        )

        let maxAttempts = 3

        for attempt in 1...maxAttempts {
            Logger.info("🔧 Extracting skills from: \(filename) (attempt \(attempt)/\(maxAttempts))", category: .ai)

            do {
                // Use unified structured output API with Gemini backend
                let response: SkillExtractionResponse = try await facade.executeStructuredWithDictionarySchema(
                    prompt: prompt,
                    modelId: modelId,
                    as: SkillExtractionResponse.self,
                    schema: SkillBankPrompts.jsonSchema,
                    schemaName: "skill_extraction",
                    maxOutputTokens: 32768,
                    backend: .gemini
                )
                Logger.info("🔧 Extracted \(response.skills.count) skills", category: .ai)
                return response.skills
            } catch {
                Logger.warning("🔧 Error on attempt \(attempt): \(error.localizedDescription)", category: .ai)
                if attempt < maxAttempts { continue }
                throw SkillBankError.invalidResponse
            }
        }

        throw SkillBankError.invalidResponse
    }

    /// Split content into chunks at paragraph boundaries
    private func chunkContent(_ content: String, maxSize: Int) -> [String] {
        var chunks: [String] = []
        var currentChunk = ""

        let paragraphs = content.components(separatedBy: "\n\n")
        for paragraph in paragraphs {
            if currentChunk.count + paragraph.count + 2 > maxSize && !currentChunk.isEmpty {
                chunks.append(currentChunk)
                currentChunk = paragraph
            } else {
                if !currentChunk.isEmpty {
                    currentChunk += "\n\n"
                }
                currentChunk += paragraph
            }
        }
        if !currentChunk.isEmpty {
            chunks.append(currentChunk)
        }
        return chunks
    }

    /// Deduplicate skills by canonical name
    private func deduplicateSkills(_ skills: [Skill]) -> [Skill] {
        var merged: [String: Skill] = [:]

        for skill in skills {
            let key = skill.canonical.lowercased()
            if let existing = merged[key] {
                // Merge evidence
                var allEvidence = existing.evidence + skill.evidence
                // Dedupe by document+location
                var seen = Set<String>()
                allEvidence = allEvidence.filter { evidence in
                    let key = "\(evidence.documentId):\(evidence.location)"
                    if seen.contains(key) { return false }
                    seen.insert(key)
                    return true
                }

                // Take higher proficiency
                let proficiency = existing.proficiency.sortOrder < skill.proficiency.sortOrder
                    ? existing.proficiency : skill.proficiency

                // Union ATS variants
                let variants = Array(Set(existing.atsVariants + skill.atsVariants))

                merged[key] = Skill(
                    id: existing.id,
                    canonical: existing.canonical,
                    atsVariants: variants,
                    category: existing.category,
                    proficiency: proficiency,
                    evidence: allEvidence,
                    relatedSkills: Array(Set(existing.relatedSkills + skill.relatedSkills)),
                    lastUsed: existing.lastUsed ?? skill.lastUsed
                )
            } else {
                merged[key] = skill
            }
        }

        return Array(merged.values).sorted { $0.canonical < $1.canonical }
    }

    /// Merge skills from multiple documents into unified bank
    func mergeSkillBank(documentSkills: [[Skill]], sourceDocumentIds: [String]) -> SkillBank {
        let allSkills = documentSkills.flatMap { $0 }
        let merged = deduplicateSkills(allSkills)

        return SkillBank(
            skills: merged,
            generatedAt: Date(),
            sourceDocumentIds: sourceDocumentIds
        )
    }

    enum SkillBankError: Error, LocalizedError {
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

/// Response wrapper for skill extraction
private struct SkillExtractionResponse: Codable {
    let skills: [Skill]
}
