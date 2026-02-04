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
        case analyzing
        case generatingCard(current: Int, total: Int)
        case completed(created: Int, enhanced: Int)
        case failed(String)

        var isProcessing: Bool {
            switch self {
            case .idle, .completed, .failed:
                return false
            case .extracting, .analyzing, .generatingCard:
                return true
            }
        }

        var displayText: String {
            switch self {
            case .idle:
                return "Ready"
            case .extracting(let current, let total, let filename):
                return "Extracting (\(current)/\(total)): \(filename)"
            case .analyzing:
                return "Analyzing documents..."
            case .generatingCard(let current, let total):
                return "Generating card (\(current)/\(total))..."
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

    /// Tracks artifact IDs created during current operation (for export)
    private var currentArtifactIds: Set<String> = []

    // MARK: - Initialization

    init(llmFacade: LLMFacade?, knowledgeCardStore: KnowledgeCardStore?, artifactRecordStore: ArtifactRecordStore?) {
        self.llmFacade = llmFacade
        self.knowledgeCardStore = knowledgeCardStore
        self.artifactRecordStore = artifactRecordStore

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
            let newArtifacts = try await extractor.extractAllSources(sources) { [weak self] current, total, filename in
                self?.status = .extracting(current: current, total: total, filename: filename)
            }
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

    /// Generate selected cards and apply enhancements.
    func generateSelected(
        newCards: [KnowledgeCard],
        enhancements: [(proposal: KnowledgeCard, existing: KnowledgeCard)],
        artifacts: [JSON]
    ) async throws -> (created: Int, enhanced: Int) {
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
            Logger.info("✅ StandaloneKCCoordinator: Created card - \(card.title)", category: .ai)
        }

        // Enhance existing cards
        for (index, (proposal, existingCard)) in enhancements.enumerated() {
            status = .generatingCard(current: newCards.count + index + 1, total: totalOperations)

            analyzer.enhanceKnowledgeCard(existingCard, with: proposal)
            enhancedCount += 1
            Logger.info("✅ StandaloneKCCoordinator: Enhanced card - \(existingCard.title)", category: .ai)
        }

        status = .completed(created: createdCount, enhanced: enhancedCount)
        return (created: createdCount, enhanced: enhancedCount)
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
