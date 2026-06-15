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
}
