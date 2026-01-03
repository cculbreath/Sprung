//
//  StandaloneKCAnalyzer.swift
//  Sprung
//
//  Handles document analysis, skill extraction, and ResRef matching
//  for standalone KC generation. This module determines what cards should be
//  created vs which existing cards should be enhanced.
//

import Foundation
import SwiftyJSON

/// Handles document analysis and card proposal generation.
@MainActor
class StandaloneKCAnalyzer {
    // MARK: - Dependencies

    private var skillBankService: SkillBankService?
    private var kcExtractionService: KnowledgeCardExtractionService?
    private var metadataService: MetadataExtractionService?
    private weak var resRefStore: ResRefStore?

    // MARK: - Initialization

    init(llmFacade: LLMFacade?, resRefStore: ResRefStore?) {
        self.resRefStore = resRefStore
        self.skillBankService = SkillBankService(llmFacade: llmFacade)
        self.kcExtractionService = KnowledgeCardExtractionService(llmFacade: llmFacade)
        self.metadataService = MetadataExtractionService(llmFacade: llmFacade)
    }

    // MARK: - Analysis Result

    /// Result of analyzing artifacts
    struct AnalysisResult {
        let skillBank: SkillBank
        let narrativeCards: [KnowledgeCard]
    }

    // MARK: - Public API

    /// Analyze artifacts to extract skills and narrative cards.
    /// Uses pre-existing extraction from artifacts when available,
    /// otherwise generates via LLM.
    /// - Parameter artifacts: Extracted artifact JSON objects
    /// - Returns: Analysis result with skills and narrative cards
    func analyzeArtifacts(_ artifacts: [JSON]) async throws -> AnalysisResult {
        var allSkills: [Skill] = []
        var allNarrativeCards: [KnowledgeCard] = []

        for artifact in artifacts {
            let docId = artifact["id"].stringValue
            let filename = artifact["filename"].stringValue
            let content = artifact["extracted_text"].stringValue

            // Check for pre-existing skills
            if let existingSkills = parseExistingSkills(from: artifact) {
                Logger.info("📦 StandaloneKCAnalyzer: Using pre-existing skills for \(filename)", category: .ai)
                allSkills.append(contentsOf: existingSkills)
            } else if let service = skillBankService {
                // Generate skills via LLM
                do {
                    let skills = try await service.extractSkills(
                        documentId: docId,
                        filename: filename,
                        content: content
                    )
                    allSkills.append(contentsOf: skills)
                } catch {
                    Logger.warning("⚠️ StandaloneKCAnalyzer: Failed to extract skills from \(filename): \(error.localizedDescription)", category: .ai)
                }
            }

            // Check for pre-existing narrative cards
            if let existingCards = parseExistingNarrativeCards(from: artifact) {
                Logger.info("📦 StandaloneKCAnalyzer: Using pre-existing narrative cards for \(filename)", category: .ai)
                allNarrativeCards.append(contentsOf: existingCards)
            } else if let service = kcExtractionService {
                // Generate narrative cards via LLM
                do {
                    let cards = try await service.extractCards(
                        documentId: docId,
                        filename: filename,
                        content: content
                    )
                    allNarrativeCards.append(contentsOf: cards)
                } catch {
                    Logger.warning("⚠️ StandaloneKCAnalyzer: Failed to extract narrative cards from \(filename): \(error.localizedDescription)", category: .ai)
                }
            }
        }

        // Deduplicate skills using SkillBankService
        let sourceDocIds = artifacts.map { $0["id"].stringValue }
        let mergedSkillBank = await skillBankService?.mergeSkillBank(documentSkills: [allSkills], sourceDocumentIds: sourceDocIds)
            ?? SkillBank(skills: allSkills, generatedAt: Date(), sourceDocumentIds: sourceDocIds)

        return AnalysisResult(
            skillBank: mergedSkillBank,
            narrativeCards: allNarrativeCards
        )
    }

    /// Parse pre-existing skills from artifact JSON
    private func parseExistingSkills(from artifact: JSON) -> [Skill]? {
        guard let skillsString = artifact["skills"].string,
              let data = skillsString.data(using: .utf8) else { return nil }

        // Note: Skill model has explicit CodingKeys for snake_case - no conversion needed
        let decoder = JSONDecoder()
        return try? decoder.decode([Skill].self, from: data)
    }

    /// Parse pre-existing narrative cards from artifact JSON
    private func parseExistingNarrativeCards(from artifact: JSON) -> [KnowledgeCard]? {
        guard let cardsString = artifact["narrative_cards"].string,
              let data = cardsString.data(using: .utf8) else { return nil }

        // Note: KnowledgeCard model has explicit CodingKeys for snake_case - no conversion needed
        let decoder = JSONDecoder()
        return try? decoder.decode([KnowledgeCard].self, from: data)
    }

    /// Match narrative cards against existing ResRefs to determine new vs enhancement.
    /// - Parameter analysisResult: Analysis result with skills and narrative cards
    /// - Returns: Tuple of new cards and enhancement proposals
    func matchAgainstExisting(
        _ analysisResult: AnalysisResult
    ) -> (newCards: [KnowledgeCard], enhancements: [(proposal: KnowledgeCard, existing: ResRef)]) {
        let existingCards = resRefStore?.resRefs ?? []
        var newCards: [KnowledgeCard] = []
        var enhancements: [(proposal: KnowledgeCard, existing: ResRef)] = []

        for card in analysisResult.narrativeCards {
            if let match = findMatchingResRef(card, in: existingCards) {
                enhancements.append((card, match))
            } else {
                newCards.append(card)
            }
        }

        return (newCards, enhancements)
    }

    /// Extract metadata from artifacts for single-card generation.
    /// - Parameter artifacts: Extracted artifact JSON objects
    /// - Returns: Card metadata
    func extractMetadata(from artifacts: [JSON]) async throws -> CardMetadata {
        guard let service = metadataService else {
            let filename = artifacts.first?["filename"].stringValue ?? "Document"
            return CardMetadata.defaults(fromFilename: filename)
        }

        return try await service.extract(from: artifacts)
    }

    /// Enhance an existing ResRef with new evidence from a narrative card.
    func enhanceResRef(_ resRef: ResRef, with card: KnowledgeCard) {
        // Merge suggested bullets from scale (quantified outcomes)
        var existingBullets: [String] = []
        if let bulletsJSON = resRef.suggestedBulletsJSON,
           let data = bulletsJSON.data(using: .utf8),
           let decoded = try? JSONSerialization.jsonObject(with: data) as? [String] {
            existingBullets = decoded
        }

        // Add scale items as bullets if not already present
        let newBullets = card.extractable.scale.filter { scale in
            !existingBullets.contains { $0.lowercased().contains(scale.lowercased().prefix(30)) }
        }
        existingBullets.append(contentsOf: newBullets)

        if let data = try? JSONSerialization.data(withJSONObject: existingBullets),
           let jsonString = String(data: data, encoding: .utf8) {
            resRef.suggestedBulletsJSON = jsonString
        }

        // Merge domains (technologies)
        var existingTech: [String] = []
        if let techJSON = resRef.technologiesJSON,
           let data = techJSON.data(using: .utf8),
           let decoded = try? JSONSerialization.jsonObject(with: data) as? [String] {
            existingTech = decoded
        }

        let newTech = card.extractable.domains.filter { domain in
            !existingTech.contains { $0.lowercased() == domain.lowercased() }
        }
        existingTech.append(contentsOf: newTech)

        if let data = try? JSONSerialization.data(withJSONObject: existingTech),
           let jsonString = String(data: data, encoding: .utf8) {
            resRef.technologiesJSON = jsonString
        }

        // Update content to reflect new bullets
        resRef.content = existingBullets.map { "• \($0)" }.joined(separator: "\n")

        // Update sources JSON
        var existingSources: [[String: String]] = []
        if let sourcesJSON = resRef.sourcesJSON,
           let data = sourcesJSON.data(using: .utf8),
           let decoded = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] {
            existingSources = decoded
        }

        // Add new sources from evidence anchors
        let existingIds = Set(existingSources.compactMap { $0["artifact_id"] })
        for anchor in card.evidenceAnchors {
            if !existingIds.contains(anchor.documentId) {
                existingSources.append(["type": "artifact", "artifact_id": anchor.documentId])
            }
        }

        if let data = try? JSONSerialization.data(withJSONObject: existingSources),
           let jsonString = String(data: data, encoding: .utf8) {
            resRef.sourcesJSON = jsonString
        }

        resRefStore?.updateResRef(resRef)
        Logger.info("✅ StandaloneKCAnalyzer: Enhanced card with \(newBullets.count) new bullets, \(newTech.count) new domains", category: .ai)
    }

    // MARK: - Private: ResRef Matching

    /// Match a narrative card against existing ResRefs
    private func findMatchingResRef(
        _ card: KnowledgeCard,
        in existing: [ResRef]
    ) -> ResRef? {
        let titleCore = cardTitleCore(card.title)
        return existing.first { resRef in
            resRef.cardType == card.cardType.rawValue &&
            resRef.name.lowercased().contains(titleCore)
        }
    }

    /// Extract core identifier from title (e.g., "Senior Engineer at TechCorp" -> "techcorp")
    private func cardTitleCore(_ title: String) -> String {
        title.lowercased().split(separator: " ").last.map(String.init) ?? title.lowercased()
    }
}
