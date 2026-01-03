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
        let enhancements: [(proposal: KnowledgeCard, existing: ResRef)]
        let artifacts: [JSON]
    }

    // MARK: - Published State

    var status: Status = .idle
    var generatedCard: ResRef?
    var errorMessage: String?

    // MARK: - Dependencies

    private let extractor: StandaloneKCExtractor
    private let analyzer: StandaloneKCAnalyzer
    private weak var llmFacade: LLMFacade?
    private weak var resRefStore: ResRefStore?
    private weak var artifactRecordStore: ArtifactRecordStore?

    /// Tracks artifact IDs created during current operation (for export)
    private var currentArtifactIds: Set<String> = []

    // MARK: - Initialization

    init(llmFacade: LLMFacade?, resRefStore: ResRefStore?, artifactRecordStore: ArtifactRecordStore?) {
        self.llmFacade = llmFacade
        self.resRefStore = resRefStore
        self.artifactRecordStore = artifactRecordStore

        // Initialize sub-modules
        self.extractor = StandaloneKCExtractor(llmFacade: llmFacade, artifactRecordStore: artifactRecordStore)
        self.analyzer = StandaloneKCAnalyzer(llmFacade: llmFacade, resRefStore: resRefStore)
    }

    // MARK: - Public API: Single Card Generation

    /// Generate a knowledge card from URLs and/or pre-loaded archived artifacts.
    func generateCardWithExisting(from sources: [URL], existingArtifactIds: Set<String>) async throws {
        guard !sources.isEmpty || !existingArtifactIds.isEmpty else {
            throw StandaloneKCError.noSources
        }

        guard llmFacade != nil else {
            throw StandaloneKCError.llmNotConfigured
        }

        status = .idle
        errorMessage = nil
        generatedCard = nil

        do {
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
                // Add new artifact IDs
                for artifact in newArtifacts {
                    if let id = artifact["id"].string {
                        allArtifactIds.insert(id)
                    }
                }
            }

            guard !allArtifacts.isEmpty else {
                throw StandaloneKCError.noArtifactsExtracted
            }

            // Track artifact IDs for export
            currentArtifactIds = allArtifactIds

            // Phase 3: Analyze artifacts
            status = .analyzing
            let analysisResult = try await analyzer.analyzeArtifacts(allArtifacts)

            guard let firstCard = analysisResult.narrativeCards.first else {
                throw StandaloneKCError.noArtifactsExtracted
            }

            // Phase 4: Convert narrative card to ResRef
            status = .generatingCard(current: 1, total: 1)
            let converter = KnowledgeCardToResRefConverter()

            // Build artifact lookup
            var artifactLookup: [String: String] = [:]
            for artifact in allArtifacts {
                let id = artifact["id"].stringValue
                let filename = artifact["filename"].stringValue
                if !id.isEmpty && !filename.isEmpty {
                    artifactLookup[id] = filename
                }
            }

            let resRef = converter.convert(card: firstCard, artifactLookup: artifactLookup)
            resRef.isFromOnboarding = false
            resRefStore?.addResRef(resRef)

            self.generatedCard = resRef
            status = .completed(created: 1, enhanced: 0)

            Logger.info("✅ StandaloneKCCoordinator: Knowledge card created - \(resRef.name)", category: .ai)

        } catch {
            let message = error.localizedDescription
            status = .failed(message)
            errorMessage = message
            Logger.error("❌ StandaloneKCCoordinator: Failed - \(message)", category: .ai)
            throw error
        }
    }

    // MARK: - Public API: Multi-Card Analysis & Generation

    /// Analyze documents to produce card proposals for user review.
    func analyzeDocuments(from sources: [URL], existingArtifactIds: Set<String> = []) async throws -> AnalysisResult {
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

        guard !allArtifacts.isEmpty else {
            throw StandaloneKCError.noArtifactsExtracted
        }

        // Track artifact IDs for later export
        currentArtifactIds = allArtifactIds

        // Phase 3: Analyze artifacts
        status = .analyzing
        let analysisResult = try await analyzer.analyzeArtifacts(allArtifacts)

        // Phase 4: Match against existing
        let (newCards, enhancements) = analyzer.matchAgainstExisting(analysisResult)

        status = .idle
        Logger.info("📊 StandaloneKCCoordinator: Analysis complete - \(newCards.count) new, \(enhancements.count) enhancements", category: .ai)

        return AnalysisResult(
            skillBank: analysisResult.skillBank,
            newCards: newCards,
            enhancements: enhancements,
            artifacts: allArtifacts
        )
    }

    /// Generate selected cards and apply enhancements.
    func generateSelected(
        newCards: [KnowledgeCard],
        enhancements: [(proposal: KnowledgeCard, existing: ResRef)],
        artifacts: [JSON]
    ) async throws -> (created: Int, enhanced: Int) {
        guard llmFacade != nil else {
            throw StandaloneKCError.llmNotConfigured
        }

        let totalOperations = newCards.count + enhancements.count
        var createdCount = 0
        var enhancedCount = 0

        // Build artifact lookup
        var artifactLookup: [String: String] = [:]
        for artifact in artifacts {
            let id = artifact["id"].stringValue
            let filename = artifact["filename"].stringValue
            if !id.isEmpty && !filename.isEmpty {
                artifactLookup[id] = filename
            }
        }

        let converter = KnowledgeCardToResRefConverter()

        // Generate new cards
        for (index, card) in newCards.enumerated() {
            status = .generatingCard(current: index + 1, total: totalOperations)

            let resRef = converter.convert(card: card, artifactLookup: artifactLookup)
            resRef.isFromOnboarding = false
            resRefStore?.addResRef(resRef)
            createdCount += 1
            Logger.info("✅ StandaloneKCCoordinator: Created card - \(resRef.name)", category: .ai)
        }

        // Enhance existing cards
        for (index, (proposal, existingCard)) in enhancements.enumerated() {
            status = .generatingCard(current: newCards.count + index + 1, total: totalOperations)

            analyzer.enhanceResRef(existingCard, with: proposal)
            enhancedCount += 1
            Logger.info("✅ StandaloneKCCoordinator: Enhanced card - \(existingCard.name)", category: .ai)
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
