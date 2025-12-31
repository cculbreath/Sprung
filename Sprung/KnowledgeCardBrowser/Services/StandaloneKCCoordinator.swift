//
//  StandaloneKCCoordinator.swift
//  Sprung
//
//  Orchestrates standalone knowledge card generation from documents/git repos.
//  This is an alternative to the onboarding interview workflow - users can
//  directly ingest documents and generate knowledge cards without going
//  through the full onboarding process.
//
//  Pipeline: Upload Sources → Extract → Inventory → Merge → Convert → Persist
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
        case inventorying
        case merging
        case analyzingMetadata
        case generatingCard(current: Int, total: Int)
        case completed(created: Int, enhanced: Int)
        case failed(String)

        var isProcessing: Bool {
            switch self {
            case .idle, .completed, .failed:
                return false
            case .extracting, .inventorying, .merging, .analyzingMetadata, .generatingCard:
                return true
            }
        }

        var displayText: String {
            switch self {
            case .idle:
                return "Ready"
            case .extracting(let current, let total, let filename):
                return "Extracting (\(current)/\(total)): \(filename)"
            case .inventorying:
                return "Generating card inventory..."
            case .merging:
                return "Merging card proposals..."
            case .analyzingMetadata:
                return "Analyzing document metadata..."
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
        let newCards: [MergedCardInventory.MergedCard]
        let enhancements: [(proposal: MergedCardInventory.MergedCard, existing: ResRef)]
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

            // Phase 3: Analyze and inventory (same as onboarding workflow)
            status = .inventorying
            let merged = try await analyzer.analyzeArtifacts(allArtifacts)

            guard let firstCard = merged.mergedCards.first else {
                throw StandaloneKCError.noArtifactsExtracted
            }

            // Phase 4: Convert merged card to ResRef
            status = .generatingCard(current: 1, total: 1)
            let resRef = try await convertMergedCard(firstCard, artifacts: allArtifacts)
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
    /// This uses the full pipeline: classify → inventory → merge → match existing.
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

        // Phase 3: Analyze and inventory
        status = .inventorying
        let merged = try await analyzer.analyzeArtifacts(allArtifacts)

        // Phase 4: Match against existing
        status = .merging
        let (newCards, enhancements) = analyzer.matchAgainstExisting(merged)

        status = .idle
        Logger.info("📊 StandaloneKCCoordinator: Analysis complete - \(newCards.count) new, \(enhancements.count) enhancements", category: .ai)

        return AnalysisResult(newCards: newCards, enhancements: enhancements, artifacts: allArtifacts)
    }

    /// Generate selected cards and apply enhancements.
    /// For new cards: runs KC generation agent.
    /// For enhancements: runs KC expansion agent to expand existing cards with new evidence.
    func generateSelected(
        newCards: [MergedCardInventory.MergedCard],
        enhancements: [(proposal: MergedCardInventory.MergedCard, existing: ResRef)],
        artifacts: [JSON]
    ) async throws -> (created: Int, enhanced: Int) {
        guard llmFacade != nil else {
            throw StandaloneKCError.llmNotConfigured
        }

        let totalOperations = newCards.count + enhancements.count
        var createdCount = 0
        var enhancedCount = 0

        // Generate new cards
        for (index, proposal) in newCards.enumerated() {
            status = .generatingCard(current: index + 1, total: totalOperations)

            do {
                let card = try await convertMergedCard(proposal, artifacts: artifacts)
                resRefStore?.addResRef(card)
                createdCount += 1
                Logger.info("✅ StandaloneKCCoordinator: Created card - \(card.name)", category: .ai)
            } catch {
                Logger.error("❌ StandaloneKCCoordinator: Failed to generate card \(proposal.title): \(error.localizedDescription)", category: .ai)
            }
        }

        // Enhance existing cards with new facts from proposals
        for (index, (proposal, existingCard)) in enhancements.enumerated() {
            status = .generatingCard(current: newCards.count + index + 1, total: totalOperations)

            // Use simple fact merging to enhance existing card
            analyzer.enhanceResRef(existingCard, with: proposal)
            enhancedCount += 1
            Logger.info("✅ StandaloneKCCoordinator: Enhanced card - \(existingCard.name)", category: .ai)
        }

        status = .completed(created: createdCount, enhanced: enhancedCount)
        return (created: createdCount, enhanced: enhancedCount)
    }

    // MARK: - Private: Card Conversion

    /// Convert a merged card to ResRef using direct conversion (same approach as onboarding)
    private func convertMergedCard(_ proposal: MergedCardInventory.MergedCard, artifacts: [JSON]) async throws -> ResRef {
        guard let facade = llmFacade else {
            throw StandaloneKCError.llmNotConfigured
        }

        // Build artifact lookup for source attribution
        var artifactLookup: [String: String] = [:]
        for artifact in artifacts {
            let id = artifact["id"].stringValue
            let filename = artifact["filename"].stringValue
            if !id.isEmpty && !filename.isEmpty {
                artifactLookup[id] = filename
            }
        }

        // Use the same converter as onboarding
        let converter = MergedCardToResRefConverter(llmFacade: facade, eventBus: nil)
        let resRef = try await converter.convert(mergedCard: proposal, artifactLookup: artifactLookup)

        // Mark as standalone (not from onboarding)
        resRef.isFromOnboarding = false

        return resRef
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
