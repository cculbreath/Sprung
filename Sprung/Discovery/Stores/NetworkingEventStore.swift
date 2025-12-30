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

    var needsDebrief: [NetworkingEventOpportunity] {
        allEvents.filter { $0.needsDebrief }
    }

    var discoveredEvents: [NetworkingEventOpportunity] {
        allEvents.filter { $0.status == .discovered }
    }

    var attendedEvents: [NetworkingEventOpportunity] {
        allEvents.filter { $0.attended }
    }

    func addMultiple(_ events: [NetworkingEventOpportunity]) {
        for event in events {
            modelContext.insert(event)
        }
        saveContext()
    }

    func update(_: NetworkingEventOpportunity) {
        saveContext()
    }

    func delete(_ event: NetworkingEventOpportunity) {
        modelContext.delete(event)
        saveContext()
    }

    func event(byId id: UUID) -> NetworkingEventOpportunity? {
        allEvents.first { $0.id == id }
    }

    /// Filter out events that already exist (by URL)
    func filterNew(_ events: [NetworkingEventOpportunity]) -> [NetworkingEventOpportunity] {
        let existingUrls = Set(allEvents.map { $0.url })
        return events.filter { !existingUrls.contains($0.url) }
    }

    // MARK: - Status Transitions

    func markAsPlanned(_ event: NetworkingEventOpportunity, calendarEventId: String? = nil) {
        event.status = .planned
        event.calendarEventId = calendarEventId
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

}
