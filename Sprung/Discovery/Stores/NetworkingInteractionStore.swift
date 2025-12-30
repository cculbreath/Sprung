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
final class NetworkingInteractionStore: SwiftDataStore {
    unowned let modelContext: ModelContext

    init(context: ModelContext) {
        modelContext = context
    }

    var allInteractions: [NetworkingInteraction] {
        (try? modelContext.fetch(
            FetchDescriptor<NetworkingInteraction>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        )) ?? []
    }

    func add(_ interaction: NetworkingInteraction) {
        modelContext.insert(interaction)
        saveContext()
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
