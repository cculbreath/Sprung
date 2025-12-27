//
//  NetworkingEventStore.swift
//  Sprung
//
//  Store for managing networking event opportunities.
//

import SwiftData
import Foundation

@Observable
@MainActor
final class NetworkingEventStore: SwiftDataStore {
    unowned let modelContext: ModelContext

    init(context: ModelContext) {
        modelContext = context
    }

    var allEvents: [NetworkingEventOpportunity] {
        (try? modelContext.fetch(
            FetchDescriptor<NetworkingEventOpportunity>(sortBy: [SortDescriptor(\.date)])
        )) ?? []
    }

    var upcomingEvents: [NetworkingEventOpportunity] {
        allEvents.filter { $0.date > Date() && $0.status.isActive }
    }

    var recommendedEvents: [NetworkingEventOpportunity] {
        upcomingEvents.filter { $0.status == .recommended || $0.status == .planned }
    }

    var plannedEvents: [NetworkingEventOpportunity] {
        upcomingEvents.filter { $0.status == .planned }
    }

    var needsDebrief: [NetworkingEventOpportunity] {
        allEvents.filter { $0.needsDebrief }
    }

    var discoveredEvents: [NetworkingEventOpportunity] {
        allEvents.filter { $0.status == .discovered }
    }

    var pastEvents: [NetworkingEventOpportunity] {
        allEvents.filter { $0.isPast }
    }

    var attendedEvents: [NetworkingEventOpportunity] {
        allEvents.filter { $0.attended }
    }

    func add(_ event: NetworkingEventOpportunity) {
        modelContext.insert(event)
        saveContext()
    }

    func addMultiple(_ events: [NetworkingEventOpportunity]) {
        for event in events {
            modelContext.insert(event)
        }
        saveContext()
    }

    func update(_ event: NetworkingEventOpportunity) {
        saveContext()
    }

    func delete(_ event: NetworkingEventOpportunity) {
        modelContext.delete(event)
        saveContext()
    }

    func event(byId id: UUID) -> NetworkingEventOpportunity? {
        allEvents.first { $0.id == id }
    }

    func event(byUrl url: String) -> NetworkingEventOpportunity? {
        allEvents.first { $0.url == url }
    }

    /// Filter out events that already exist (by URL)
    func filterNew(_ events: [NetworkingEventOpportunity]) -> [NetworkingEventOpportunity] {
        let existingUrls = Set(allEvents.map { $0.url })
        return events.filter { !existingUrls.contains($0.url) }
    }

    // MARK: - Status Transitions

    func markAsRecommended(_ event: NetworkingEventOpportunity) {
        event.status = .recommended
        saveContext()
    }

    func markAsPlanned(_ event: NetworkingEventOpportunity, calendarEventId: String? = nil) {
        event.status = .planned
        event.calendarEventId = calendarEventId
        saveContext()
    }

    func markAsSkipped(_ event: NetworkingEventOpportunity) {
        event.status = .skipped
        saveContext()
    }

    func markAsAttended(_ event: NetworkingEventOpportunity) {
        event.attended = true
        event.attendedAt = Date()
        event.status = .attended
        saveContext()
    }

    func markAsDebriefed(_ event: NetworkingEventOpportunity) {
        event.status = .debriefed
        saveContext()
    }

    func markAsCancelled(_ event: NetworkingEventOpportunity) {
        event.status = .cancelled
        saveContext()
    }

    func markAsMissed(_ event: NetworkingEventOpportunity) {
        event.status = .missed
        saveContext()
    }

    // MARK: - This Week's Events

    var thisWeeksEvents: [NetworkingEventOpportunity] {
        let calendar = Calendar.current
        let weekStart = calendar.date(
            from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        ) ?? Date()
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? Date()

        return allEvents.filter {
            $0.date >= weekStart && $0.date < weekEnd && $0.status.isActive
        }
    }

    // MARK: - Events by Organizer (for pattern analysis)

    func events(byOrganizer organizer: String) -> [NetworkingEventOpportunity] {
        allEvents.filter { $0.organizer?.lowercased() == organizer.lowercased() }
    }

    func averageRating(forOrganizer organizer: String) -> Double? {
        let events = events(byOrganizer: organizer).filter { $0.eventRating != nil }
        guard !events.isEmpty else { return nil }
        let total = events.compactMap { $0.eventRating?.rawValue }.reduce(0, +)
        return Double(total) / Double(events.count)
    }
}
