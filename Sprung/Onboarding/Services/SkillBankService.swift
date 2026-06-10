//
//  SkillBankService.swift
//  Sprung
//
//  Service for extracting comprehensive skill inventories from documents.
//  Uses Anthropic structured output (output_config schema) against a cached
//  source block — either the actual PDF (Files API document block) or text.
//

import Foundation
import SwiftOpenAI

/// Service for generating per-document skill inventories
actor SkillBankService {
    private var llmFacade: LLMFacade?

    private func getModelId() throws -> String {
        try AnthropicDocumentAnalysisService.configuredModelId(operationName: "Skill Bank Extraction")
    }

    init(llmFacade: LLMFacade?) {
        self.llmFacade = llmFacade
        Logger.info("🔧 SkillBankService initialized", category: .ai)
    }

    func updateLLMFacade(_ facade: LLMFacade?) {
        self.llmFacade = facade
    }

    /// Extract skills from raw document text.
    /// Text documents are capped at 200K characters upstream and go in one pass.
    func extractSkills(
        documentId: String,
        filename: String,
        content: String
    ) async throws -> [Skill] {
        try await extractSkills(
            documentId: documentId,
            filename: filename,
            source: .text(AnthropicDocumentAnalysisService.sourceTextBlock(filename: filename, text: content))
        )
    }

    /// Extract skills from an analysis source (uploaded PDF or text block).
    func extractSkills(
        documentId: String,
        filename: String,
        source: DocumentAnalysisSource
    ) async throws -> [Skill] {
        guard let facade = llmFacade else {
            throw SkillBankError.llmNotConfigured
        }

        let modelId = try getModelId()
        let instructions = SkillBankPrompts.extractionPrompt(
            documentId: documentId,
            filename: filename,
            isPagedSource: source.isPaged
        )

        let maxAttempts = 3

        for attempt in 1...maxAttempts {
            Logger.info("🔧 Extracting skills from: \(filename) (attempt \(attempt)/\(maxAttempts))", category: .ai)

            do {
                let response: SkillExtractionResponse = try await facade.executeStructuredWithAnthropicBlocks(
                    systemContent: DocumentAnalysisPrompts.systemBlocks,
                    userBlocks: DocumentAnalysisPrompts.userBlocks(source: source, instructions: instructions),
                    modelId: modelId,
                    responseType: SkillExtractionResponse.self,
                    schema: SkillBankPrompts.jsonSchema,
                    maxTokens: 32768
                )
                Logger.info("🔧 Extracted \(response.skills.count) skills", category: .ai)
                return response.skills
            } catch let error as ModelConfigurationError {
                throw error
            } catch {
                Logger.warning("🔧 Error on attempt \(attempt): \(error.localizedDescription)", category: .ai)
                if attempt < maxAttempts { continue }
                throw SkillBankError.invalidResponse
            }
        }

        throw SkillBankError.invalidResponse
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
