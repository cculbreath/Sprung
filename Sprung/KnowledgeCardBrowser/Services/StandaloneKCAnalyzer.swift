//
//  StandaloneKCAnalyzer.swift
//  Sprung
//
//  Handles document analysis, skill extraction, and KnowledgeCard matching
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
    private var deduplicationService: NarrativeDeduplicationService?
    private weak var knowledgeCardStore: KnowledgeCardStore?

    // MARK: - Initialization

    init(llmFacade: LLMFacade?, knowledgeCardStore: KnowledgeCardStore?) {
        self.knowledgeCardStore = knowledgeCardStore
        self.skillBankService = SkillBankService(llmFacade: llmFacade)
        self.kcExtractionService = KnowledgeCardExtractionService(llmFacade: llmFacade)
        self.metadataService = MetadataExtractionService(llmFacade: llmFacade)
        self.deduplicationService = NarrativeDeduplicationService(llmFacade: llmFacade)
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
    /// - Parameters:
    ///   - artifacts: Extracted artifact JSON objects
    ///   - deduplicateNarratives: Whether to run LLM-powered deduplication on narrative cards
    /// - Returns: Analysis result with skills and narrative cards
    func analyzeArtifacts(_ artifacts: [JSON], deduplicateNarratives: Bool = false) async throws -> AnalysisResult {
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

        // Optionally deduplicate narrative cards
        var finalNarrativeCards = allNarrativeCards
        if deduplicateNarratives, allNarrativeCards.count > 1, let service = deduplicationService {
            do {
                Logger.info("🔀 StandaloneKCAnalyzer: Running narrative deduplication on \(allNarrativeCards.count) cards", category: .ai)
                let result = try await service.deduplicateCards(allNarrativeCards)
                finalNarrativeCards = result.cards
                Logger.info("✅ StandaloneKCAnalyzer: Deduplication complete - \(result.cards.count) cards, \(result.mergeLog.count) merges", category: .ai)
            } catch {
                Logger.warning("⚠️ StandaloneKCAnalyzer: Deduplication failed, using original cards: \(error.localizedDescription)", category: .ai)
            }
        }

        return AnalysisResult(
            skillBank: mergedSkillBank,
            narrativeCards: finalNarrativeCards
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

    /// Match narrative cards against existing KnowledgeCards to determine new vs enhancement.
    /// - Parameter analysisResult: Analysis result with skills and narrative cards
    /// - Returns: Tuple of new cards and enhancement proposals
    func matchAgainstExisting(
        _ analysisResult: AnalysisResult
    ) -> (newCards: [KnowledgeCard], enhancements: [(proposal: KnowledgeCard, existing: KnowledgeCard)]) {
        let existingCards = knowledgeCardStore?.knowledgeCards ?? []
        var newCards: [KnowledgeCard] = []
        var enhancements: [(proposal: KnowledgeCard, existing: KnowledgeCard)] = []

        for card in analysisResult.narrativeCards {
            if let match = findMatchingKnowledgeCard(card, in: existingCards) {
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

    /// Enhance an existing KnowledgeCard with new evidence from a proposal card.
    func enhanceKnowledgeCard(_ existingCard: KnowledgeCard, with proposal: KnowledgeCard) {
        // Merge facts from proposal
        var existingFacts = existingCard.facts
        let existingStatements = Set(existingFacts.map { $0.statement.lowercased() })

        let newFacts = proposal.facts.filter { fact in
            !existingStatements.contains(fact.statement.lowercased())
        }
        existingFacts.append(contentsOf: newFacts)
        existingCard.factsJSON = {
            guard let data = try? JSONEncoder().encode(existingFacts),
                  let json = String(data: data, encoding: .utf8) else { return nil }
            return json
        }()

        // Merge evidence anchors
        var existingAnchors = existingCard.evidenceAnchors
        let existingDocIds = Set(existingAnchors.map { $0.documentId })

        let newAnchors = proposal.evidenceAnchors.filter { anchor in
            !existingDocIds.contains(anchor.documentId)
        }
        existingAnchors.append(contentsOf: newAnchors)
        existingCard.evidenceAnchorsJSON = {
            guard let data = try? JSONEncoder().encode(existingAnchors),
                  let json = String(data: data, encoding: .utf8) else { return nil }
            return json
        }()

        // Merge extractable metadata
        let proposalExtractable = proposal.extractable
        let existingExtractable = existingCard.extractable

        // Merge domains
        let existingDomains = Set(existingExtractable.domains.map { $0.lowercased() })
        let newDomains = proposalExtractable.domains.filter { !existingDomains.contains($0.lowercased()) }
        let mergedDomains = existingExtractable.domains + newDomains

        // Merge scale items
        let existingScale = Set(existingExtractable.scale.map { $0.lowercased() })
        let newScale = proposalExtractable.scale.filter { !existingScale.contains($0.lowercased()) }
        let mergedScale = existingExtractable.scale + newScale

        // Create new extractable with merged values
        let mergedExtractable = ExtractableMetadata(
            domains: mergedDomains,
            scale: mergedScale,
            keywords: existingExtractable.keywords
        )
        existingCard.extractable = mergedExtractable

        knowledgeCardStore?.update(existingCard)
        Logger.info("✅ StandaloneKCAnalyzer: Enhanced card with \(newFacts.count) new facts, \(newAnchors.count) new anchors", category: .ai)
    }

    // MARK: - Private: KnowledgeCard Matching

    /// Match a narrative card against existing KnowledgeCards
    private func findMatchingKnowledgeCard(
        _ card: KnowledgeCard,
        in existing: [KnowledgeCard]
    ) -> KnowledgeCard? {
        let titleCore = cardTitleCore(card.title)
        return existing.first { existingCard in
            existingCard.cardType == card.cardType &&
            existingCard.title.lowercased().contains(titleCore)
        }
    }

    /// Extract core identifier from title (e.g., "Senior Engineer at TechCorp" -> "techcorp")
    private func cardTitleCore(_ title: String) -> String {
        title.lowercased().split(separator: " ").last.map(String.init) ?? title.lowercased()
    }
}
