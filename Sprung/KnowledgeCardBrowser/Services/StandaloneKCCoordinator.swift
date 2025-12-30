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

    private let extractor: StandaloneKCExtractor
    private let analyzer: StandaloneKCAnalyzer
    private weak var llmFacade: LLMFacade?
    private weak var resRefStore: ResRefStore?
    private weak var sessionStore: OnboardingSessionStore?

    /// Tracks artifact IDs created during current operation (for export)
    private var currentArtifactIds: Set<String> = []

    // MARK: - Configuration

    private let kcAgentModelId: String

    // MARK: - Initialization

    init(llmFacade: LLMFacade?, resRefStore: ResRefStore?, sessionStore: OnboardingSessionStore?) {
        self.llmFacade = llmFacade
        self.resRefStore = resRefStore
        self.sessionStore = sessionStore
        self.kcAgentModelId = UserDefaults.standard.string(forKey: "onboardingKCAgentModelId") ?? "anthropic/claude-haiku-4.5"

        // Initialize sub-modules
        self.extractor = StandaloneKCExtractor(llmFacade: llmFacade, sessionStore: sessionStore)
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

            // Phase 3: Extract metadata
            status = .analyzingMetadata
            let metadata = try await analyzer.extractMetadata(from: allArtifacts)

            // Phase 4: Generate KC via agent
            status = .generatingCard(current: 1, total: 1)
            let generated = try await runKCAgent(artifactIds: currentArtifactIds, artifacts: allArtifacts, metadata: metadata)

            // Phase 5: Persist to ResRef
            let resRef = createResRef(from: generated, metadata: metadata)
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
                let card = try await runKCAgentForProposal(proposal, artifacts: artifacts)
                resRefStore?.addResRef(card)
                createdCount += 1
                Logger.info("✅ StandaloneKCCoordinator: Created card - \(card.name)", category: .ai)
            } catch {
                Logger.error("❌ StandaloneKCCoordinator: Failed to generate card \(proposal.title): \(error.localizedDescription)", category: .ai)
            }
        }

        // Enhance existing cards using expand agent
        for (index, (proposal, existingCard)) in enhancements.enumerated() {
            status = .generatingCard(current: newCards.count + index + 1, total: totalOperations)

            do {
                // Get the new artifact IDs from the proposal
                var newArtifactIds = Set([proposal.primarySource.documentId])
                newArtifactIds.formUnion(proposal.supportingSources.map { $0.documentId })

                // Filter artifacts to only include those referenced in the proposal
                let newArtifacts = artifacts.filter { artifact in
                    guard let id = artifact["id"].string else { return false }
                    return newArtifactIds.contains(id)
                }

                // Run expand agent
                try await runExpandAgent(existingCard: existingCard, newArtifacts: newArtifacts)
                enhancedCount += 1
                Logger.info("✅ StandaloneKCCoordinator: Expanded card - \(existingCard.name)", category: .ai)
            } catch {
                Logger.warning("⚠️ StandaloneKCCoordinator: Expand agent failed for \(existingCard.name), falling back to simple merge: \(error.localizedDescription)", category: .ai)
                // Fall back to simple fact merging if expand agent fails
                analyzer.enhanceResRef(existingCard, with: proposal)
                enhancedCount += 1
            }
        }

        status = .completed(created: createdCount, enhanced: enhancedCount)
        return (created: createdCount, enhanced: enhancedCount)
    }

    // MARK: - Private: KC Agent Generation

    private func runKCAgent(artifactIds: Set<String>, artifacts: [JSON], metadata: CardMetadata) async throws -> GeneratedCard {
        guard let facade = llmFacade, let store = sessionStore else {
            throw StandaloneKCError.llmNotConfigured
        }

        // Export artifacts to filesystem for agent access
        let exportDir = try store.exportArtifactsByIds(artifactIds)
        defer {
            store.cleanupExportedArtifacts(at: exportDir)
        }

        // Build CardProposal
        let artifactIdList = artifacts.compactMap { $0["id"].string }
        let proposal = CardProposal(
            cardId: UUID().uuidString,
            cardType: metadata.cardType,
            title: metadata.title,
            timelineEntryId: nil,
            assignedArtifactIds: artifactIdList,
            chatExcerpts: [],
            notes: nil
        )

        // Build prompts for fact-based extraction
        let systemPrompt = KCAgentPrompts.systemPrompt(
            cardId: UUID().uuidString,
            cardType: metadata.cardType,
            title: metadata.title
        )

        let initialPrompt = KCAgentPrompts.initialPrompt(
            proposal: proposal,
            allArtifacts: artifacts
        )

        // Create tool executor with exported filesystem
        let toolExecutor = SubAgentToolExecutor(filesystemRoot: exportDir)

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
        guard let facade = llmFacade, let store = sessionStore else {
            throw StandaloneKCError.llmNotConfigured
        }

        // Export artifacts to filesystem for agent access
        let exportDir = try store.exportArtifactsByIds(currentArtifactIds)
        defer {
            store.cleanupExportedArtifacts(at: exportDir)
        }

        // Build CardProposal
        var artifactIdList = [proposal.primarySource.documentId]
        artifactIdList.append(contentsOf: proposal.supportingSources.map { $0.documentId })

        let cardProposal = CardProposal(
            cardId: proposal.cardId,
            cardType: proposal.cardType,
            title: proposal.title,
            timelineEntryId: nil,
            assignedArtifactIds: artifactIdList,
            chatExcerpts: [],
            notes: nil
        )

        // Build prompts for fact-based extraction
        let systemPrompt = KCAgentPrompts.systemPrompt(
            cardId: proposal.cardId,
            cardType: proposal.cardType,
            title: proposal.title
        )

        let initialPrompt = KCAgentPrompts.initialPrompt(
            proposal: cardProposal,
            allArtifacts: artifacts
        )

        // Create tool executor with exported filesystem
        let toolExecutor = SubAgentToolExecutor(filesystemRoot: exportDir)

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

        return createResRef(from: generated, metadata: metadata)
    }

    /// Run the KC expand agent to expand an existing card with new evidence.
    /// Updates the ResRef in place with expanded facts, bullets, and technologies.
    private func runExpandAgent(existingCard: ResRef, newArtifacts: [JSON]) async throws {
        guard let facade = llmFacade, let store = sessionStore else {
            throw StandaloneKCError.llmNotConfigured
        }

        // Export new artifacts to filesystem for agent access
        let newArtifactIds = Set(newArtifacts.compactMap { $0["id"].string })
        let exportDir = try store.exportArtifactsByIds(newArtifactIds)
        defer {
            store.cleanupExportedArtifacts(at: exportDir)
        }

        // Build expand prompts
        let systemPrompt = KCAgentPrompts.expandSystemPrompt(
            cardId: existingCard.id.uuidString,
            cardType: existingCard.cardType ?? "employment",
            title: existingCard.name
        )

        let initialPrompt = KCAgentPrompts.expandInitialPrompt(
            existingCard: existingCard,
            newArtifacts: newArtifacts
        )

        // Create tool executor with exported filesystem
        let toolExecutor = SubAgentToolExecutor(filesystemRoot: exportDir)

        // Run agent
        let runner = AgentRunner.forKnowledgeCard(
            agentId: UUID().uuidString,
            cardTitle: "Expand: \(existingCard.name)",
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

        // Update the existing card with expanded data
        updateResRefFromExpandedOutput(existingCard, output: result, newArtifacts: newArtifacts)
    }

    /// Update an existing ResRef with expanded output from the expand agent.
    private func updateResRefFromExpandedOutput(_ resRef: ResRef, output: JSON, newArtifacts: [JSON]) {
        // Update facts JSON
        if let factsArray = output["facts"].array, !factsArray.isEmpty {
            if let data = try? JSONSerialization.data(withJSONObject: factsArray.map { $0.object }),
               let jsonString = String(data: data, encoding: .utf8) {
                resRef.factsJSON = jsonString
            }
        }

        // Update suggested bullets
        let newBullets = output["suggested_bullets"].arrayValue.map { $0.stringValue }
        if !newBullets.isEmpty {
            if let data = try? JSONSerialization.data(withJSONObject: newBullets),
               let jsonString = String(data: data, encoding: .utf8) {
                resRef.suggestedBulletsJSON = jsonString
            }
            // Update content to reflect new bullets
            resRef.content = newBullets.map { "• \($0)" }.joined(separator: "\n")
        }

        // Update technologies
        let newTechs = output["technologies"].arrayValue.map { $0.stringValue }
        if !newTechs.isEmpty {
            if let data = try? JSONSerialization.data(withJSONObject: newTechs),
               let jsonString = String(data: data, encoding: .utf8) {
                resRef.technologiesJSON = jsonString
            }
        }

        // Merge sources - add new artifact IDs
        var existingSources: [[String: String]] = []
        if let sourcesJSON = resRef.sourcesJSON,
           let data = sourcesJSON.data(using: .utf8),
           let decoded = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] {
            existingSources = decoded
        }

        let existingIds = Set(existingSources.compactMap { $0["artifact_id"] })
        for artifact in newArtifacts {
            if let id = artifact["id"].string, !existingIds.contains(id) {
                existingSources.append(["type": "artifact", "artifact_id": id])
            }
        }

        if let data = try? JSONSerialization.data(withJSONObject: existingSources),
           let jsonString = String(data: data, encoding: .utf8) {
            resRef.sourcesJSON = jsonString
        }

        // Update the store
        resRefStore?.updateResRef(resRef)
    }

    // MARK: - Private: ResRef Creation

    /// Create ResRef from fact-based GeneratedCard
    private func createResRef(from card: GeneratedCard, metadata: CardMetadata) -> ResRef {
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
