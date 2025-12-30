//
//  StandaloneKCCoordinator.swift
//  Sprung
//
//  Orchestrates standalone knowledge card generation from documents/git repos.
//  This is an alternative to the onboarding interview workflow - users can
//  directly ingest documents and generate knowledge cards without going
//  through the full onboarding process.
//
//  Pipeline: Upload Sources → Extract → Classify → Inventory → Merge → KC Agent → Persist
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

    private let repository = InMemoryArtifactRepository()
    private let extractor: StandaloneKCExtractor
    private let analyzer: StandaloneKCAnalyzer
    private weak var llmFacade: LLMFacade?
    private weak var resRefStore: ResRefStore?

    // MARK: - Configuration

    private let kcAgentModelId: String

    // MARK: - Initialization

    init(llmFacade: LLMFacade?, resRefStore: ResRefStore?, sessionStore: OnboardingSessionStore? = nil) {
        self.llmFacade = llmFacade
        self.resRefStore = resRefStore
        self.kcAgentModelId = UserDefaults.standard.string(forKey: "onboardingKCAgentModelId") ?? "anthropic/claude-haiku-4.5"

        // Initialize sub-modules
        self.extractor = StandaloneKCExtractor(llmFacade: llmFacade, sessionStore: sessionStore)
        self.analyzer = StandaloneKCAnalyzer(llmFacade: llmFacade, resRefStore: resRefStore)
    }

    // MARK: - Public API: Single Card Generation

    /// Generate a knowledge card from the given source URLs.
    /// Sources can be document files (PDF, DOCX, TXT) or git repository folders.
    func generateCard(from sources: [URL]) async throws {
        guard !sources.isEmpty else {
            throw StandaloneKCError.noSources
        }

        guard llmFacade != nil else {
            throw StandaloneKCError.llmNotConfigured
        }

        status = .idle
        errorMessage = nil
        generatedCard = nil

        do {
            // Phase 1: Extract all sources
            let artifacts = try await extractor.extractAllSources(sources, into: repository) { [weak self] current, total, filename in
                self?.status = .extracting(current: current, total: total, filename: filename)
            }

            guard !artifacts.isEmpty else {
                throw StandaloneKCError.noArtifactsExtracted
            }

            // Phase 2: Extract metadata
            status = .analyzingMetadata
            let metadata = try await analyzer.extractMetadata(from: artifacts)

            // Phase 3: Generate KC via agent
            status = .generatingCard(current: 1, total: 1)
            let generated = try await runKCAgent(artifacts: artifacts, metadata: metadata)

            // Phase 4: Persist to ResRef
            let resRef = createResRef(from: generated, metadata: metadata, artifacts: artifacts)
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

    /// Reset the coordinator state for a new ingestion
    func reset() {
        status = .idle
        generatedCard = nil
        errorMessage = nil
        Task {
            await repository.reset()
        }
    }

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
            if !existingArtifactIds.isEmpty {
                let existing = await extractor.loadArchivedArtifacts(existingArtifactIds, into: repository)
                allArtifacts.append(contentsOf: existing)
            }

            // Phase 2: Extract new sources
            if !sources.isEmpty {
                let newArtifacts = try await extractor.extractAllSources(sources, into: repository) { [weak self] current, total, filename in
                    self?.status = .extracting(current: current, total: total, filename: filename)
                }
                allArtifacts.append(contentsOf: newArtifacts)
            }

            guard !allArtifacts.isEmpty else {
                throw StandaloneKCError.noArtifactsExtracted
            }

            // Phase 3: Extract metadata
            status = .analyzingMetadata
            let metadata = try await analyzer.extractMetadata(from: allArtifacts)

            // Phase 4: Generate KC via agent
            status = .generatingCard(current: 1, total: 1)
            let generated = try await runKCAgent(artifacts: allArtifacts, metadata: metadata)

            // Phase 5: Persist to ResRef
            let resRef = createResRef(from: generated, metadata: metadata, artifacts: allArtifacts)
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
        if !existingArtifactIds.isEmpty {
            let existing = await extractor.loadArchivedArtifacts(existingArtifactIds, into: repository)
            allArtifacts.append(contentsOf: existing)
        }

        // Phase 2: Extract new sources
        if !sources.isEmpty {
            let newArtifacts = try await extractor.extractAllSources(sources, into: repository) { [weak self] current, total, filename in
                self?.status = .extracting(current: current, total: total, filename: filename)
            }
            allArtifacts.append(contentsOf: newArtifacts)
        }

        guard !allArtifacts.isEmpty else {
            throw StandaloneKCError.noArtifactsExtracted
        }

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
    func generateSelected(
        newCards: [MergedCardInventory.MergedCard],
        enhancements: [(proposal: MergedCardInventory.MergedCard, existing: ResRef)],
        artifacts: [JSON]
    ) async throws -> (created: Int, enhanced: Int) {
        guard llmFacade != nil else {
            throw StandaloneKCError.llmNotConfigured
        }

        let totalCards = newCards.count
        var createdCount = 0
        var enhancedCount = 0

        // Generate new cards
        for (index, proposal) in newCards.enumerated() {
            status = .generatingCard(current: index + 1, total: totalCards)

            do {
                let card = try await runKCAgentForProposal(proposal, artifacts: artifacts)
                resRefStore?.addResRef(card)
                createdCount += 1
                Logger.info("✅ StandaloneKCCoordinator: Created card - \(card.name)", category: .ai)
            } catch {
                Logger.error("❌ StandaloneKCCoordinator: Failed to generate card \(proposal.title): \(error.localizedDescription)", category: .ai)
            }
        }

        // Enhance existing cards (using fact-based merging)
        for (proposal, existingCard) in enhancements {
            analyzer.enhanceResRef(existingCard, with: proposal)
            enhancedCount += 1
        }

        status = .completed(created: createdCount, enhanced: enhancedCount)
        return (created: createdCount, enhanced: enhancedCount)
    }

    // MARK: - Private: KC Agent Generation

    private func runKCAgent(artifacts: [JSON], metadata: CardMetadata) async throws -> GeneratedCard {
        guard let facade = llmFacade else {
            throw StandaloneKCError.llmNotConfigured
        }

        // Build CardProposal
        let artifactIds = artifacts.compactMap { $0["id"].string }
        let proposal = CardProposal(
            cardId: UUID().uuidString,
            cardType: metadata.cardType,
            title: metadata.title,
            timelineEntryId: nil,
            assignedArtifactIds: artifactIds,
            chatExcerpts: [],
            notes: nil
        )

        // Build prompts for fact-based extraction
        let systemPrompt = KCAgentPrompts.systemPrompt(
            cardId: UUID().uuidString,
            cardType: metadata.cardType,
            title: metadata.title
        )

        // Build artifact summaries for the initial prompt
        let summaries = await repository.getArtifactSummaries()

        let initialPrompt = KCAgentPrompts.initialPrompt(
            proposal: proposal,
            allArtifacts: summaries
        )

        // Create tool executor with our in-memory repository
        let toolExecutor = SubAgentToolExecutor(artifactRepository: repository)

        // Run agent
        let runner = AgentRunner.forKnowledgeCard(
            agentId: UUID().uuidString,
            cardTitle: metadata.title,
            systemPrompt: systemPrompt,
            initialPrompt: initialPrompt,
            modelId: kcAgentModelId,
            toolExecutor: toolExecutor,
            llmFacade: facade,
            eventBus: nil,
            tracker: nil
        )

        let output = try await runner.run()

        // Parse result
        guard let result = output.result?["result"] else {
            throw StandaloneKCError.agentNoResult
        }

        let generated = GeneratedCard.fromAgentOutput(result, cardId: proposal.cardId)

        // Validate
        if let error = generated.validationError() {
            throw StandaloneKCError.agentInvalidOutput(error)
        }

        return generated
    }

    private func runKCAgentForProposal(_ proposal: MergedCardInventory.MergedCard, artifacts: [JSON]) async throws -> ResRef {
        guard let facade = llmFacade else {
            throw StandaloneKCError.llmNotConfigured
        }

        // Build CardProposal
        var artifactIds = [proposal.primarySource.documentId]
        artifactIds.append(contentsOf: proposal.supportingSources.map { $0.documentId })

        let cardProposal = CardProposal(
            cardId: proposal.cardId,
            cardType: proposal.cardType,
            title: proposal.title,
            timelineEntryId: nil,
            assignedArtifactIds: artifactIds,
            chatExcerpts: [],
            notes: nil
        )

        // Build prompts for fact-based extraction
        let systemPrompt = KCAgentPrompts.systemPrompt(
            cardId: proposal.cardId,
            cardType: proposal.cardType,
            title: proposal.title
        )

        let summaries = await repository.getArtifactSummaries()
        let initialPrompt = KCAgentPrompts.initialPrompt(
            proposal: cardProposal,
            allArtifacts: summaries
        )

        // Create tool executor with our in-memory repository
        let toolExecutor = SubAgentToolExecutor(artifactRepository: repository)

        // Run agent
        let runner = AgentRunner.forKnowledgeCard(
            agentId: UUID().uuidString,
            cardTitle: proposal.title,
            systemPrompt: systemPrompt,
            initialPrompt: initialPrompt,
            modelId: kcAgentModelId,
            toolExecutor: toolExecutor,
            llmFacade: facade,
            eventBus: nil,
            tracker: nil
        )

        let output = try await runner.run()

        // Parse result
        guard let result = output.result?["result"] else {
            throw StandaloneKCError.agentNoResult
        }

        let generated = GeneratedCard.fromAgentOutput(result, cardId: proposal.cardId)

        // Build metadata from proposal
        let metadata = CardMetadata(
            cardType: proposal.cardType,
            title: proposal.title,
            organization: nil,
            timePeriod: proposal.dateRange,
            location: nil
        )

        return createResRef(from: generated, metadata: metadata, artifacts: artifacts)
    }

    // MARK: - Private: ResRef Creation

    /// Create ResRef from fact-based GeneratedCard
    private func createResRef(from card: GeneratedCard, metadata: CardMetadata, artifacts: [JSON]) -> ResRef {
        // Encode sources as JSON
        var sourcesJSON: String?
        if !card.sources.isEmpty {
            let sourcesArray = card.sources.map { artifactId -> [String: String] in
                ["type": "artifact", "artifact_id": artifactId]
            }
            if let data = try? JSONSerialization.data(withJSONObject: sourcesArray),
               let jsonString = String(data: data, encoding: .utf8) {
                sourcesJSON = jsonString
            }
        }

        // Build content from suggested bullets for display
        let content: String
        if let bullets = card.suggestedBullets, !bullets.isEmpty {
            content = bullets.map { "• \($0)" }.joined(separator: "\n")
        } else {
            content = "Knowledge card: \(card.title)"
        }

        // Encode technologies as JSON
        var technologiesJSON: String?
        if let techs = card.technologies, !techs.isEmpty {
            if let data = try? JSONSerialization.data(withJSONObject: techs),
               let jsonString = String(data: data, encoding: .utf8) {
                technologiesJSON = jsonString
            }
        }

        // Encode suggested bullets as JSON
        var suggestedBulletsJSON: String?
        if let bullets = card.suggestedBullets, !bullets.isEmpty {
            if let data = try? JSONSerialization.data(withJSONObject: bullets),
               let jsonString = String(data: data, encoding: .utf8) {
                suggestedBulletsJSON = jsonString
            }
        }

        return ResRef(
            name: card.title.isEmpty ? metadata.title : card.title,
            content: content,
            enabledByDefault: true,
            cardType: metadata.cardType,
            timePeriod: card.timePeriod ?? metadata.timePeriod,
            organization: card.organization ?? metadata.organization,
            location: card.location ?? metadata.location,
            sourcesJSON: sourcesJSON,
            isFromOnboarding: false,  // Standalone, not from onboarding
            tokenCount: card.tokenCount,
            factsJSON: card.factsJSON,
            suggestedBulletsJSON: suggestedBulletsJSON,
            technologiesJSON: technologiesJSON
        )
    }
}

// MARK: - Errors

enum StandaloneKCError: LocalizedError {
    case noSources
    case llmNotConfigured
    case extractionServiceNotAvailable
    case noArtifactsExtracted
    case extractionFailed(String)
    case agentNoResult
    case agentInvalidOutput(String)

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
        case .agentNoResult:
            return "Knowledge card agent completed without producing a result"
        case .agentInvalidOutput(let message):
            return "Invalid knowledge card output: \(message)"
        }
    }
}
