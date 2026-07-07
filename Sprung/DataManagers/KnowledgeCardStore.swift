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
final class KnowledgeCardStore: EntityStore {
    typealias Entity = KnowledgeCard
    unowned let modelContext: ModelContext

    /// @Observable refresh counter (see EntityStore). Touched by `fetchAll()` and
    /// bumped by every mutation so views reading the fetched collections re-render
    /// on insert/delete (this store previously had no such counter).
    var changeVersion: Int = 0

    // MARK: - Computed Collections

    /// All knowledge cards - SwiftData is the single source of truth
    var knowledgeCards: [KnowledgeCard] { fetchAll() }

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
    // add / addAll / update / delete / deleteAll are provided by EntityStore.

    /// Deletes all KnowledgeCards created during onboarding
    func deleteOnboardingCards() {
        let cards = onboardingCards
        deleteAll(cards)
        Logger.info("🗑️ Deleted \(cards.count) onboarding KnowledgeCards", category: .ai)
    }

    /// Deletes all pending cards
    func deletePendingCards() {
        let cards = pendingCards
        deleteAll(cards)
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
        persistChanges()
        Logger.info("✅ Approved \(cardsToApprove.count) KnowledgeCards", category: .ai)
    }

    /// Deletes cards that originated from a specific artifact
    /// - Parameter artifactId: The artifact ID to match against evidenceAnchors
    func deleteCardsFromArtifact(_ artifactId: String) {
        let cardsToDelete = knowledgeCards.filter { card in
            card.evidenceAnchors.contains { $0.documentId == artifactId }
        }
        deleteAll(cardsToDelete)
        Logger.info("🗑️ Deleted \(cardsToDelete.count) cards from artifact \(artifactId)", category: .ai)
    }

    /// Deletes only non-pending (approved) cards that originated from a specific artifact
    /// Used during regeneration to clear old approved cards before adding new pending ones
    /// - Parameter artifactId: The artifact ID to match against evidenceAnchors
    func deleteApprovedCardsFromArtifact(_ artifactId: String) {
        let cardsToDelete = knowledgeCards.filter { card in
            !card.isPending && card.evidenceAnchors.contains { $0.documentId == artifactId }
        }
        deleteAll(cardsToDelete)
        if !cardsToDelete.isEmpty {
            Logger.info("🗑️ Deleted \(cardsToDelete.count) approved cards from artifact \(artifactId)", category: .ai)
        }
    }

    /// Deletes non-pending (approved) cards from multiple artifacts
    /// - Parameter artifactIds: Set of artifact IDs to match against evidenceAnchors
    func deleteApprovedCardsFromArtifacts(_ artifactIds: Set<String>) {
        let cardsToDelete = knowledgeCards.filter { card in
            !card.isPending && card.evidenceAnchors.contains { artifactIds.contains($0.documentId) }
        }
        deleteAll(cardsToDelete)
        if !cardsToDelete.isEmpty {
            Logger.info("🗑️ Deleted \(cardsToDelete.count) approved cards from \(artifactIds.count) artifacts", category: .ai)
        }
    }

    // MARK: - Import/Export

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
