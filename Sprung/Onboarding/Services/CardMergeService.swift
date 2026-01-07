//
//  CardMergeService.swift
//  Sprung
//
//  Service for aggregating skills and narrative cards across documents.
//  Uses SkillBankService for skill deduplication and merging.
//  Uses NarrativeDeduplicationService for intelligent narrative card merging.
//
//  Note: Reads from SwiftData (ArtifactRecordStore) to ensure data persistence
//  survives memory pressure during long sessions.
//

import Foundation
import SwiftyJSON

/// Service for aggregating skills and narrative cards across documents
actor CardMergeService {
    private var llmFacade: LLMFacade?
    private let artifactRecordStore: ArtifactRecordStore
    private let sessionPersistenceHandler: SwiftDataSessionPersistenceHandler
    private let skillBankService: SkillBankService
    private var deduplicationService: NarrativeDeduplicationService?
    private weak var eventBus: EventCoordinator?
    private weak var agentActivityTracker: AgentActivityTracker?

    init(
        artifactRecordStore: ArtifactRecordStore,
        sessionPersistenceHandler: SwiftDataSessionPersistenceHandler,
        llmFacade: LLMFacade?,
        eventBus: EventCoordinator? = nil,
        agentActivityTracker: AgentActivityTracker? = nil
    ) {
        self.artifactRecordStore = artifactRecordStore
        self.sessionPersistenceHandler = sessionPersistenceHandler
        self.llmFacade = llmFacade
        self.eventBus = eventBus
        self.agentActivityTracker = agentActivityTracker
        self.skillBankService = SkillBankService(llmFacade: llmFacade)
        Logger.info("🔄 CardMergeService initialized", category: .ai)
    }

    /// Lazy initialization of deduplication service on MainActor
    private func getDeduplicationService() async -> NarrativeDeduplicationService {
        if let service = deduplicationService {
            return service
        }
        let facade = self.llmFacade
        let bus = self.eventBus
        let tracker = self.agentActivityTracker
        let service = await MainActor.run {
            NarrativeDeduplicationService(llmFacade: facade, eventBus: bus, agentActivityTracker: tracker)
        }
        deduplicationService = service
        return service
    }

    // MARK: - Private Types

    /// Snapshot of artifact data needed for processing
    private struct ArtifactSnapshot {
        let id: String
        let filename: String
        let sourceType: String
        let skills: [Skill]?
        let narrativeCards: [KnowledgeCard]?
    }

    // MARK: - Skill Bank + Narrative Cards Methods

    /// Get merged skill bank from all artifacts
    /// Uses SkillBankService to deduplicate and merge skills across documents
    func getMergedSkillBank() async -> SkillBank? {
        // Read directly from SwiftData for persistence across memory pressure
        let snapshots = await getArtifactSnapshots()
        var documentSkills: [[Skill]] = []
        var sourceDocumentIds: [String] = []

        Logger.info("🔧 CardMergeService: Checking \(snapshots.count) artifacts for skills", category: .ai)

        for artifact in snapshots {
            guard let skills = artifact.skills, !skills.isEmpty else {
                Logger.debug("⏭️ Skipping artifact '\(artifact.filename)': no skills data", category: .ai)
                continue
            }

            documentSkills.append(skills)
            sourceDocumentIds.append(artifact.id)
            Logger.debug("🔧 Loaded \(skills.count) skills from artifact: \(artifact.filename)", category: .ai)
        }

        guard !documentSkills.isEmpty else {
            Logger.info("🔧 No skills found in any artifacts", category: .ai)
            return nil
        }

        // Use SkillBankService to merge and deduplicate
        let mergedBank = await skillBankService.mergeSkillBank(
            documentSkills: documentSkills,
            sourceDocumentIds: sourceDocumentIds
        )

        Logger.info("✅ Merged skill bank: \(mergedBank.skills.count) skills from \(documentSkills.count) documents", category: .ai)
        return mergedBank
    }

    /// Get all narrative cards from all artifacts
    /// Returns cards grouped by document with document metadata
    func getAllNarrativeCards() async -> [NarrativeCardCollection] {
        // Read directly from SwiftData for persistence across memory pressure
        let snapshots = await getArtifactSnapshots()
        var collections: [NarrativeCardCollection] = []

        Logger.info("📖 CardMergeService: Checking \(snapshots.count) artifacts for narrative cards", category: .ai)

        for artifact in snapshots {
            guard let cards = artifact.narrativeCards, !cards.isEmpty else {
                Logger.debug("⏭️ Skipping artifact '\(artifact.filename)': no narrative_cards data", category: .ai)
                continue
            }

            let collection = NarrativeCardCollection(
                documentId: artifact.id,
                filename: artifact.filename,
                documentType: artifact.sourceType,
                cards: cards
            )
            collections.append(collection)
            Logger.debug("📖 Loaded \(cards.count) narrative cards from artifact: \(artifact.filename)", category: .ai)
        }

        let totalCards = collections.reduce(0) { $0 + $1.cards.count }
        Logger.info("✅ Found \(totalCards) narrative cards across \(collections.count) documents", category: .ai)
        return collections
    }

    // MARK: - Private Helpers

    /// Get Sendable snapshots of artifacts from SwiftData for the current session
    private func getArtifactSnapshots() async -> [ArtifactSnapshot] {
        await MainActor.run {
            guard let session = sessionPersistenceHandler.currentSession else {
                Logger.warning("⚠️ No current session found for artifact retrieval", category: .ai)
                return []
            }
            return artifactRecordStore.artifacts(for: session).map { artifact in
                ArtifactSnapshot(
                    id: artifact.id.uuidString,
                    filename: artifact.filename,
                    sourceType: artifact.sourceType,
                    skills: artifact.skills,
                    narrativeCards: artifact.narrativeCards
                )
            }
        }
    }

    /// Get a flat list of all narrative cards across all documents
    func getAllNarrativeCardsFlat() async -> [KnowledgeCard] {
        let collections = await getAllNarrativeCards()
        return collections.flatMap { $0.cards }
    }

    /// Get all narrative cards, deduplicated across documents
    /// Uses LLM to make intelligent merge decisions while preserving detail
    func getAllNarrativeCardsDeduped() async throws -> DeduplicationResult {
        let allCards = await getAllNarrativeCardsFlat()

        guard allCards.count > 1 else {
            return DeduplicationResult(cards: allCards, mergeLog: [])
        }

        Logger.info("🔀 Starting narrative card deduplication: \(allCards.count) cards", category: .ai)
        let service = await getDeduplicationService()
        return try await service.deduplicateCards(allCards)
    }

    /// Deduplicate an arbitrary list of narrative cards
    /// Useful for manual deduplication triggers
    func deduplicateCards(_ cards: [KnowledgeCard]) async throws -> DeduplicationResult {
        guard cards.count > 1 else {
            return DeduplicationResult(cards: cards, mergeLog: [])
        }

        Logger.info("🔀 Manual deduplication requested: \(cards.count) cards", category: .ai)
        let service = await getDeduplicationService()
        return try await service.deduplicateCards(cards)
    }

    enum CardMergeError: Error, LocalizedError {
        case llmNotConfigured
        case noSkillsFound
        case noCardsFound

        var errorDescription: String? {
            switch self {
            case .llmNotConfigured:
                return "LLM facade is not configured"
            case .noSkillsFound:
                return "No skills found in artifacts"
            case .noCardsFound:
                return "No narrative cards found in artifacts"
            }
        }
    }
}

/// Collection of narrative cards from a single document
struct NarrativeCardCollection {
    let documentId: String
    let filename: String
    let documentType: String
    let cards: [KnowledgeCard]
}
