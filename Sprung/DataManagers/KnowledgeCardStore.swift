//
//  KnowledgeCardStore.swift
//  Sprung
//
//  Store for managing KnowledgeCard persistence via SwiftData.
//  Replaces the former ResRefStore.
//

import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class KnowledgeCardStore: SwiftDataStore {
    unowned let modelContext: ModelContext

    // MARK: - Computed Collections

    /// All knowledge cards - SwiftData is the single source of truth
    var knowledgeCards: [KnowledgeCard] {
        (try? modelContext.fetch(FetchDescriptor<KnowledgeCard>())) ?? []
    }

    /// Cards enabled by default for new resumes
    var defaultCards: [KnowledgeCard] {
        knowledgeCards.filter { $0.enabledByDefault }
    }

    /// Cards created during onboarding
    var onboardingCards: [KnowledgeCard] {
        knowledgeCards.filter { $0.isFromOnboarding }
    }

    /// Cards pending user approval (created during onboarding but not yet approved)
    var pendingCards: [KnowledgeCard] {
        knowledgeCards.filter { $0.isPending }
    }

    /// Cards that have been approved (not pending)
    var approvedCards: [KnowledgeCard] {
        knowledgeCards.filter { !$0.isPending }
    }

    // MARK: - Initialization

    init(context: ModelContext) {
        modelContext = context
    }

    // MARK: - CRUD Operations

    /// Adds a new KnowledgeCard to the store
    func add(_ card: KnowledgeCard) {
        modelContext.insert(card)
        saveContext()
    }

    /// Adds multiple KnowledgeCards to the store
    func addAll(_ cards: [KnowledgeCard]) {
        for card in cards {
            modelContext.insert(card)
        }
        saveContext()
    }

    /// Persists updates (entity already mutated)
    func update(_ card: KnowledgeCard) {
        _ = saveContext()
    }

    /// Deletes a KnowledgeCard from the store
    func delete(_ card: KnowledgeCard) {
        modelContext.delete(card)
        saveContext()
    }

    /// Deletes multiple KnowledgeCards from the store
    func deleteAll(_ cards: [KnowledgeCard]) {
        for card in cards {
            modelContext.delete(card)
        }
        saveContext()
    }

    /// Deletes all KnowledgeCards created during onboarding
    func deleteOnboardingCards() {
        let cards = onboardingCards
        for card in cards {
            modelContext.delete(card)
        }
        saveContext()
        Logger.info("🗑️ Deleted \(cards.count) onboarding KnowledgeCards", category: .ai)
    }

    /// Deletes all pending cards
    func deletePendingCards() {
        let cards = pendingCards
        for card in cards {
            modelContext.delete(card)
        }
        saveContext()
        Logger.info("🗑️ Deleted \(cards.count) pending KnowledgeCards", category: .ai)
    }

    /// Approves pending cards by setting isPending = false
    /// - Parameter cardIds: Set of card IDs to approve. If nil, approves all pending cards.
    func approveCards(cardIds: Set<UUID>? = nil) {
        let cardsToApprove: [KnowledgeCard]
        if let ids = cardIds {
            cardsToApprove = pendingCards.filter { ids.contains($0.id) }
        } else {
            cardsToApprove = pendingCards
        }

        for card in cardsToApprove {
            card.isPending = false
        }
        saveContext()
        Logger.info("✅ Approved \(cardsToApprove.count) KnowledgeCards", category: .ai)
    }

    /// Deletes cards that originated from a specific artifact
    /// - Parameter artifactId: The artifact ID to match against evidenceAnchors
    func deleteCardsFromArtifact(_ artifactId: String) {
        let cardsToDelete = knowledgeCards.filter { card in
            card.evidenceAnchors.contains { $0.documentId == artifactId }
        }
        for card in cardsToDelete {
            modelContext.delete(card)
        }
        saveContext()
        Logger.info("🗑️ Deleted \(cardsToDelete.count) cards from artifact \(artifactId)", category: .ai)
    }

    // MARK: - Import/Export

    /// Imports KnowledgeCards from a JSON file URL
    /// - Parameter url: File URL pointing to a JSON array of KnowledgeCard objects
    /// - Returns: Number of cards imported
    @discardableResult
    func importFromJSON(url: URL) throws -> Int {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let importedCards = try decoder.decode([KnowledgeCard].self, from: data)

        // Check for existing IDs to avoid duplicates
        let existingIDs = Set(knowledgeCards.map { $0.id })
        var importedCount = 0

        for card in importedCards {
            if existingIDs.contains(card.id) {
                Logger.info("⏭️ Skipping duplicate KnowledgeCard: \(card.title)", category: .data)
                continue
            }
            modelContext.insert(card)
            importedCount += 1
        }

        saveContext()
        Logger.info("📥 Imported \(importedCount) KnowledgeCards from JSON", category: .data)
        return importedCount
    }

    /// Exports all knowledge cards to JSON data
    func exportToJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(knowledgeCards)
    }

    // MARK: - Query Helpers

    /// Find a card by ID
    func card(withId id: UUID) -> KnowledgeCard? {
        knowledgeCards.first { $0.id == id }
    }

    /// Find cards by type
    func cards(ofType type: CardType) -> [KnowledgeCard] {
        knowledgeCards.filter { $0.cardType == type }
    }

    /// Find cards containing a keyword in title or narrative
    func cards(matching query: String) -> [KnowledgeCard] {
        let lowercased = query.lowercased()
        return knowledgeCards.filter { card in
            card.title.lowercased().contains(lowercased) ||
            card.narrative.lowercased().contains(lowercased)
        }
    }
}
