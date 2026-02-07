//
//  StandaloneKCCoordinator.swift
//  Sprung
//
//  Orchestrates standalone knowledge card generation from documents/git repos.
//  This is an alternative to the onboarding interview workflow - users can
//  directly ingest documents and generate knowledge cards without going
//  through the full onboarding process.
//
//  Pipeline: Upload Sources → Extract → Analyze → Convert → Persist
//

import Foundation
import SwiftyJSON
import Observation

/// Coordinates standalone document ingestion and knowledge card generation.
/// This is an @Observable class for SwiftUI binding in the ingestion sheet.
@Observable
@MainActor
class StandaloneKCCoordinator {
    // MARK: - Status

    enum Status: Equatable {
        case idle
        case extracting(current: Int, total: Int, filename: String)
        case analyzingGit(turn: Int, maxTurns: Int, action: String)
        case analyzing
        case generatingCard(current: Int, total: Int)
        case persistingSkills(count: Int)
        case processingSkills(String)
        case enriching(current: Int, total: Int, cardTitle: String)
        case merging
        case completed(created: Int, enhanced: Int)
        case completedEnrichment(count: Int)
        case completedMerge(before: Int, after: Int)
        case failed(String)

        var isProcessing: Bool {
            switch self {
            case .idle, .completed, .completedEnrichment, .completedMerge, .failed:
                return false
            case .extracting, .analyzingGit, .analyzing, .generatingCard,
                 .persistingSkills, .processingSkills, .enriching, .merging:
                return true
            }
        }

        var displayText: String {
            switch self {
            case .idle:
                return "Ready"
            case .extracting(let current, let total, let filename):
                return "Extracting (\(current)/\(total)): \(filename)"
            case .analyzingGit(let turn, let maxTurns, let action):
                // Strip redundant "(Turn N) " prefix from agent's action string
                let cleanAction = action.replacingOccurrences(
                    of: #"^\(Turn \d+\) "#,
                    with: "",
                    options: .regularExpression
                )
                return "Git analysis (\(turn)/\(maxTurns)): \(cleanAction)"
            case .analyzing:
                return "Analyzing documents..."
            case .generatingCard(let current, let total):
                return "Generating card (\(current)/\(total))..."
            case .persistingSkills(let count):
                return "Adding \(count) skills..."
            case .processingSkills(let detail):
                return "Processing skills: \(detail)"
            case .enriching(let current, let total, let cardTitle):
                return "Enriching (\(current)/\(total)): \(cardTitle)"
            case .merging:
                return "Merging similar cards..."
            case .completed(let created, let enhanced):
                if created > 0 && enhanced > 0 {
                    return "Created \(created) cards, enhanced \(enhanced)"
                } else if created > 0 {
                    return created == 1 ? "Knowledge card created!" : "\(created) cards created!"
                } else if enhanced > 0 {
                    return enhanced == 1 ? "Existing card enhanced!" : "\(enhanced) cards enhanced!"
                } else {
                    return "Completed"
                }
            case .completedEnrichment(let count):
                return "Enriched \(count) card\(count == 1 ? "" : "s")"
            case .completedMerge(let before, let after):
                let merged = before - after
                return "Merged \(merged) card\(merged == 1 ? "" : "s") (\(before) → \(after))"
            case .failed(let error):
                return "Failed: \(error)"
            }
        }
    }

    // MARK: - Analysis Result

    /// Result of document analysis for user review before generation
    struct AnalysisResult {
        let skillBank: SkillBank
        let newCards: [KnowledgeCard]
        let enhancements: [(proposal: KnowledgeCard, existing: KnowledgeCard)]
        let artifacts: [JSON]
    }

    // MARK: - Published State

    var status: Status = .idle
    var errorMessage: String?

    // MARK: - Dependencies

    private let extractor: StandaloneKCExtractor
    private let analyzer: StandaloneKCAnalyzer
    private weak var llmFacade: LLMFacade?
    private weak var knowledgeCardStore: KnowledgeCardStore?
    private weak var artifactRecordStore: ArtifactRecordStore?
    private weak var skillStore: SkillStore?

    /// Tracks artifact IDs created during current operation (for export)
    private var currentArtifactIds: Set<String> = []

    // MARK: - Initialization

    init(llmFacade: LLMFacade?, knowledgeCardStore: KnowledgeCardStore?, artifactRecordStore: ArtifactRecordStore?, skillStore: SkillStore? = nil) {
        self.llmFacade = llmFacade
        self.knowledgeCardStore = knowledgeCardStore
        self.artifactRecordStore = artifactRecordStore
        self.skillStore = skillStore

        // Initialize sub-modules
        self.extractor = StandaloneKCExtractor(llmFacade: llmFacade, artifactRecordStore: artifactRecordStore)
        self.analyzer = StandaloneKCAnalyzer(llmFacade: llmFacade, knowledgeCardStore: knowledgeCardStore)
    }

    // MARK: - Public API: Analysis & Generation

    /// Analyze documents to produce card proposals for user review.
    /// - Parameters:
    ///   - sources: URLs to extract content from
    ///   - existingArtifactIds: IDs of already-extracted artifacts to include
    ///   - deduplicateNarratives: Whether to run LLM-powered deduplication on narrative cards
    func analyzeDocuments(from sources: [URL], existingArtifactIds: Set<String> = [], deduplicateNarratives: Bool = false) async throws -> AnalysisResult {
        guard !sources.isEmpty || !existingArtifactIds.isEmpty else {
            throw StandaloneKCError.noSources
        }

        guard llmFacade != nil else {
            throw StandaloneKCError.llmNotConfigured
        }

        status = .idle
        errorMessage = nil

        // Phase 1: Load existing artifacts
        var allArtifacts: [JSON] = []
        var allArtifactIds = existingArtifactIds
        if !existingArtifactIds.isEmpty {
            let existing = extractor.loadArchivedArtifacts(existingArtifactIds)
            allArtifacts.append(contentsOf: existing)
        }

        // Phase 2: Extract new sources (persisted to SwiftData)
        if !sources.isEmpty {
            let newArtifacts = try await extractor.extractAllSources(
                sources,
                onProgress: { [weak self] current, total, filename in
                    self?.status = .extracting(current: current, total: total, filename: filename)
                },
                onGitProgress: { [weak self] turn, maxTurns, action in
                    self?.status = .analyzingGit(turn: turn, maxTurns: maxTurns, action: action)
                }
            )
            allArtifacts.append(contentsOf: newArtifacts)
            // Track new artifact IDs
            for artifact in newArtifacts {
                if let id = artifact["id"].string {
                    allArtifactIds.insert(id)
                }
            }
        }

        // Track artifact IDs for later export
        currentArtifactIds = allArtifactIds

        // Collect pre-analyzed git results (GitAnalysisAgent produces cards directly)
        let gitCards = extractor.gitAnalyzedCards

        // Phase 3: Analyze non-git artifacts (with optional deduplication)
        var allNewCards: [KnowledgeCard] = gitCards
        var skillBank = SkillBank(skills: extractor.gitAnalyzedSkills, generatedAt: Date(), sourceDocumentIds: [])
        let nonGitArtifacts = allArtifacts.filter { $0["source_type"].string != "git_repository" }
        if !nonGitArtifacts.isEmpty {
            status = .analyzing
            let analysisResult = try await analyzer.analyzeArtifacts(nonGitArtifacts, deduplicateNarratives: deduplicateNarratives)
            allNewCards.append(contentsOf: analysisResult.narrativeCards)
            // Merge skill banks from git analysis and document analysis
            let mergedSkills = skillBank.skills + analysisResult.skillBank.skills
            skillBank = SkillBank(skills: mergedSkills, generatedAt: Date(), sourceDocumentIds: analysisResult.skillBank.sourceDocumentIds)

            // Write back extracted skills/cards to artifact records for reuse
            writeBackAnalysisResults(
                skills: analysisResult.skillBank.skills,
                narrativeCards: analysisResult.narrativeCards,
                artifacts: nonGitArtifacts
            )
        }

        guard !allNewCards.isEmpty || !allArtifacts.isEmpty else {
            throw StandaloneKCError.noArtifactsExtracted
        }

        // Phase 4: Match against existing (for git cards and analyzer cards)
        let (newCards, enhancements) = analyzer.matchCardsAgainstExisting(allNewCards)

        status = .idle
        Logger.info("📊 StandaloneKCCoordinator: Analysis complete - \(newCards.count) new, \(enhancements.count) enhancements", category: .ai)

        return AnalysisResult(
            skillBank: skillBank,
            newCards: newCards,
            enhancements: enhancements,
            artifacts: allArtifacts
        )
    }

    /// Generate selected cards, apply enhancements, and optionally persist skills.
    func generateSelected(
        newCards: [KnowledgeCard],
        enhancements: [(proposal: KnowledgeCard, existing: KnowledgeCard)],
        artifacts: [JSON],
        skillBank: SkillBank,
        persistSkills: Bool = true
    ) async throws -> (created: Int, enhanced: Int, skillsAdded: Int) {
        guard llmFacade != nil else {
            throw StandaloneKCError.llmNotConfigured
        }

        let totalOperations = newCards.count + enhancements.count
        var createdCount = 0
        var enhancedCount = 0

        // Generate new cards - persist directly
        for (index, card) in newCards.enumerated() {
            status = .generatingCard(current: index + 1, total: totalOperations)

            card.isFromOnboarding = false
            knowledgeCardStore?.add(card)
            createdCount += 1
            Logger.info("StandaloneKCCoordinator: Created card - \(card.title)", category: .ai)
        }

        // Enhance existing cards
        for (index, (proposal, existingCard)) in enhancements.enumerated() {
            status = .generatingCard(current: newCards.count + index + 1, total: totalOperations)

            analyzer.enhanceKnowledgeCard(existingCard, with: proposal)
            enhancedCount += 1
            Logger.info("StandaloneKCCoordinator: Enhanced card - \(existingCard.title)", category: .ai)
        }

        // Persist skills to SkillStore (directly approved, not pending)
        var skillsAdded = 0
        if persistSkills, !skillBank.skills.isEmpty, let skillStore = skillStore {
            status = .persistingSkills(count: skillBank.skills.count)

            let newSkills = skillBank.skills.map { skill -> Skill in
                Skill(
                    canonical: skill.canonical,
                    atsVariants: skill.atsVariants,
                    category: skill.category,
                    proficiency: skill.proficiency,
                    evidence: skill.evidence,
                    relatedSkills: skill.relatedSkills,
                    lastUsed: skill.lastUsed,
                    isFromOnboarding: false,
                    isPending: false
                )
            }

            skillStore.addAll(newSkills)
            skillsAdded = newSkills.count
            Logger.info("StandaloneKCCoordinator: Persisted \(skillsAdded) skills", category: .ai)

            // Run deduplication + ATS expansion on all skills in store
            if let llmFacade = llmFacade {
                status = .processingSkills("Deduplicating...")
                let skillsService = SkillsProcessingService(
                    skillStore: skillStore,
                    facade: llmFacade
                )
                do {
                    let results = try await skillsService.processAllSkills()
                    for result in results {
                        Logger.info("StandaloneKCCoordinator: \(result.operation) - \(result.details)", category: .ai)
                    }
                } catch is ModelConfigurationError {
                    Logger.warning("StandaloneKCCoordinator: Skills processing skipped - model not configured", category: .ai)
                } catch {
                    Logger.warning("StandaloneKCCoordinator: Skills processing failed: \(error.localizedDescription)", category: .ai)
                }
            }
        }

        status = .completed(created: createdCount, enhanced: enhancedCount)
        return (created: createdCount, enhanced: enhancedCount, skillsAdded: skillsAdded)
    }

    // MARK: - Public API: Enrichment

    /// Enrich cards with structured fact extraction.
    /// - Parameter cards: Cards to enrich (typically those where factsJSON is nil)
    /// - Returns: Number of cards enriched
    func enrichCards(_ cards: [KnowledgeCard]) async throws -> Int {
        guard let facade = llmFacade else {
            throw StandaloneKCError.llmNotConfigured
        }

        let enrichmentService = CardEnrichmentService(llmFacade: facade)
        var enrichedCount = 0
        let batchSize = 5

        for batchStart in stride(from: 0, to: cards.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, cards.count)
            let batch = Array(cards[batchStart..<batchEnd])

            // Resolve source texts on MainActor before dispatching
            let sourceTexts = batch.map { findSourceText(for: $0) }

            status = .enriching(current: batchStart + 1, total: cards.count, cardTitle: "batch of \(batch.count)")

            // Enrich batch in parallel
            let successes = await withTaskGroup(of: (Int, Bool).self) { group in
                for (i, (card, sourceText)) in zip(batch, sourceTexts).enumerated() {
                    group.addTask {
                        do {
                            try await enrichmentService.enrichCard(card, sourceText: sourceText)
                            return (i, true)
                        } catch {
                            Logger.warning("StandaloneKCCoordinator: Failed to enrich \(card.title): \(error.localizedDescription)", category: .ai)
                            return (i, false)
                        }
                    }
                }

                var results = Array(repeating: false, count: batch.count)
                for await (index, success) in group {
                    results[index] = success
                }
                return results
            }

            // Persist successful enrichments on MainActor
            for (i, success) in successes.enumerated() where success {
                let card = batch[i]
                knowledgeCardStore?.update(card)
                enrichedCount += 1
                status = .enriching(current: batchStart + i + 1, total: cards.count, cardTitle: card.title)
                Logger.info("StandaloneKCCoordinator: Enriched card - \(card.title)", category: .ai)
            }
        }

        status = .completedEnrichment(count: enrichedCount)
        return enrichedCount
    }

    // MARK: - Public API: Merge

    /// Merge similar cards using the CardMergeAgent.
    /// - Parameter cards: Cards to evaluate for merging
    /// - Returns: Tuple of (merged count, remaining count)
    func mergeCards(_ cards: [KnowledgeCard]) async throws -> (merged: Int, remaining: Int) {
        guard let facade = llmFacade else {
            throw StandaloneKCError.llmNotConfigured
        }
        guard cards.count > 1 else {
            return (merged: 0, remaining: cards.count)
        }

        status = .merging

        let dedupService = NarrativeDeduplicationService(llmFacade: facade)
        let result = try await dedupService.deduplicateCards(cards)

        let beforeCount = cards.count
        let afterCount = result.cards.count

        if afterCount < beforeCount, let store = knowledgeCardStore {
            // Remove old cards that were merged
            let resultIds = Set(result.cards.map { $0.id })
            let removedCards = cards.filter { !resultIds.contains($0.id) }
            for card in removedCards {
                store.delete(card)
            }
            // Add new merged cards
            let newCards = result.cards.filter { merged in
                !cards.contains(where: { $0.id == merged.id })
            }
            for card in newCards {
                card.isFromOnboarding = false
                store.add(card)
            }
        }

        Logger.info("StandaloneKCCoordinator: Merge complete - \(beforeCount) → \(afterCount) cards", category: .ai)
        status = .completedMerge(before: beforeCount, after: afterCount)
        return (merged: beforeCount - afterCount, remaining: afterCount)
    }

    // MARK: - Private Helpers

    /// Write back extracted skills and narrative cards to artifact records for future reuse.
    private func writeBackAnalysisResults(
        skills: [Skill],
        narrativeCards: [KnowledgeCard],
        artifacts: [JSON]
    ) {
        guard let store = artifactRecordStore else { return }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let skillsJSON: String? = {
            guard !skills.isEmpty,
                  let data = try? encoder.encode(skills) else { return nil }
            return String(data: data, encoding: .utf8)
        }()

        let cardsJSON: String? = {
            guard !narrativeCards.isEmpty,
                  let data = try? encoder.encode(narrativeCards) else { return nil }
            return String(data: data, encoding: .utf8)
        }()

        for artifact in artifacts {
            guard let idString = artifact["id"].string,
                  let record = store.artifact(byIdString: idString) else { continue }

            if let skillsJSON, record.skillsJSON == nil {
                store.updateSkills(record, skillsJSON: skillsJSON)
            }
            if let cardsJSON, record.narrativeCardsJSON == nil {
                store.updateNarrativeCards(record, narrativeCardsJSON: cardsJSON)
            }
        }

        Logger.info("StandaloneKCCoordinator: Wrote back analysis results to \(artifacts.count) artifact records", category: .ai)
    }

    /// Find source document text for a card by searching artifact records.
    private func findSourceText(for card: KnowledgeCard) -> String {
        guard let store = artifactRecordStore else { return card.narrative }

        // Try matching by evidence anchor document IDs
        for anchor in card.evidenceAnchors {
            if let artifact = store.artifact(byIdString: anchor.documentId),
               !artifact.extractedContent.isEmpty {
                return artifact.extractedContent
            }
        }

        // Fall back to searching all artifacts for content overlap
        let allArtifacts = store.allArtifacts
        if let match = allArtifacts.first(where: { !$0.extractedContent.isEmpty && $0.extractedContent.count > 500 }) {
            return match.extractedContent
        }

        // Last resort: use the card's own narrative as source
        return card.narrative
    }
}

// MARK: - Errors

enum StandaloneKCError: LocalizedError {
    case noSources
    case llmNotConfigured
    case extractionServiceNotAvailable
    case noArtifactsExtracted
    case extractionFailed(String)
    case conversionFailed(String)

    var errorDescription: String? {
        switch self {
        case .noSources:
            return "No source documents provided"
        case .llmNotConfigured:
            return "LLM service is not configured. Check your API keys in Settings."
        case .extractionServiceNotAvailable:
            return "Document extraction service is not available"
        case .noArtifactsExtracted:
            return "No content could be extracted from the provided documents"
        case .extractionFailed(let message):
            return message
        case .conversionFailed(let message):
            return "Failed to convert card: \(message)"
        }
    }
}
