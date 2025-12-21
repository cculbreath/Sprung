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

    func update(_ interaction: NetworkingInteraction) {
        saveContext()
    }

    func delete(_ interaction: NetworkingInteraction) {
        modelContext.delete(interaction)
        saveContext()
    }

    func interaction(byId id: UUID) -> NetworkingInteraction? {
        allInteractions.first { $0.id == id }
    }

    // MARK: - Contact-based Queries

    func interactions(forContactId contactId: UUID) -> [NetworkingInteraction] {
        allInteractions.filter { $0.contactId == contactId }
    }

    func recentInteractions(forContactId contactId: UUID, limit: Int = 5) -> [NetworkingInteraction] {
        Array(interactions(forContactId: contactId).prefix(limit))
    }

    func lastInteraction(forContactId contactId: UUID) -> NetworkingInteraction? {
        interactions(forContactId: contactId).first
    }

    // MARK: - Event-based Queries

    func interactions(forEventId eventId: UUID) -> [NetworkingInteraction] {
        allInteractions.filter { $0.eventId == eventId }
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

    var upcomingFollowUps: [NetworkingInteraction] {
        pendingFollowUps.filter {
            guard let dueDate = $0.followUpDate else { return true }
            return dueDate >= Date()
        }
    }

    func completeFollowUp(_ interaction: NetworkingInteraction) {
        interaction.followUpCompleted = true
        saveContext()
    }

    // MARK: - Date-based Queries

    func interactionsInRange(from startDate: Date, to endDate: Date) -> [NetworkingInteraction] {
        allInteractions.filter {
            $0.date >= startDate && $0.date <= endDate
        }
    }

    func interactionsForCurrentWeek() -> [NetworkingInteraction] {
        let calendar = Calendar.current
        let weekStart = calendar.date(
            from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        ) ?? Date()
        return interactionsInRange(from: weekStart, to: Date())
    }

    func interactionsForDate(_ date: Date) -> [NetworkingInteraction] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? date
        return interactionsInRange(from: startOfDay, to: endOfDay)
    }

    // MARK: - Statistics

    var thisWeeksInteractionCount: Int {
        interactionsForCurrentWeek().count
    }

    func interactionsByType(in interactions: [NetworkingInteraction]) -> [InteractionType: Int] {
        Dictionary(grouping: interactions) { $0.interactionType }
            .mapValues { $0.count }
    }

    func interactionsByOutcome(in interactions: [NetworkingInteraction]) -> [InteractionOutcome: Int] {
        let withOutcomes = interactions.filter { $0.outcome != nil }
        return Dictionary(grouping: withOutcomes) { $0.outcome! }
            .mapValues { $0.count }
    }
}
