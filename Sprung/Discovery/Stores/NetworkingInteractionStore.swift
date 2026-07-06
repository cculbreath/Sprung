//
//  NetworkingInteractionStore.swift
//  Sprung
//
//  Store for managing networking interactions.
//

import SwiftData
import Foundation

@Observable
@MainActor
final class NetworkingInteractionStore: EntityStore {
    typealias Entity = NetworkingInteraction

    unowned let modelContext: ModelContext

    /// `@Observable` refresh counter bumped by EntityStore mutations.
    var changeVersion: Int = 0

    init(context: ModelContext) {
        modelContext = context
    }

    var allInteractions: [NetworkingInteraction] {
        fetchAll(sortBy: [SortDescriptor(\.date, order: .reverse)])
    }

    // MARK: - Contact-based Queries

    func interactions(forContactId contactId: UUID) -> [NetworkingInteraction] {
        allInteractions.filter { $0.contactId == contactId }
    }

    // MARK: - Follow-up Management

    var pendingFollowUps: [NetworkingInteraction] {
        allInteractions.filter { $0.followUpNeeded && !$0.followUpCompleted }
    }

    var overdueFollowUps: [NetworkingInteraction] {
        pendingFollowUps.filter {
            guard let dueDate = $0.followUpDate else { return false }
            return dueDate < Date()
        }
    }

    /// The single writer for follow-up commitments (debrief per-contact toggle
    /// and accepted AI-suggested actions). Sets `followUpNeeded` so the row
    /// actually surfaces in `pendingFollowUps`/`overdueFollowUps`.
    @discardableResult
    func recordFollowUp(
        contactId: UUID,
        action: String,
        dueDate: Date,
        eventId: UUID? = nil,
        type: InteractionType = .email
    ) -> NetworkingInteraction {
        let interaction = NetworkingInteraction(contactId: contactId, type: type)
        interaction.eventId = eventId
        interaction.followUpNeeded = true
        interaction.followUpAction = action
        interaction.followUpDate = dueDate
        add(interaction)
        return interaction
    }

    /// Completing a Follow Up daily task clears the matching commitment: the
    /// contact's pending follow-up with the earliest due date (undated ones
    /// last). Returns the cleared interaction, or nil when none was pending.
    @discardableResult
    func completeNearestPendingFollowUp(forContactId contactId: UUID) -> NetworkingInteraction? {
        let pending = pendingFollowUps
            .filter { $0.contactId == contactId }
            .sorted { ($0.followUpDate ?? Date.distantFuture) < ($1.followUpDate ?? Date.distantFuture) }
        guard let nearest = pending.first else { return nil }
        nearest.followUpCompleted = true
        update(nearest)
        return nearest
    }
}
