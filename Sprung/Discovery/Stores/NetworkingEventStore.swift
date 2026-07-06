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
final class NetworkingEventStore: EntityStore {
    typealias Entity = NetworkingEventOpportunity

    unowned let modelContext: ModelContext

    /// `@Observable` refresh counter bumped on every mutation (see EntityStore).
    var changeVersion: Int = 0

    init(context: ModelContext) {
        modelContext = context
        // The one honest `.missed` writer. Runs once per launch (the store is
        // created once, in DiscoveryCoordinator init) — cheap, idempotent, and
        // keeps the pipeline truthful without a background timer.
        sweepMissedEvents()
    }

    var allEvents: [NetworkingEventOpportunity] {
        fetchAll(sortBy: [SortDescriptor(\.date)])
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
        addAll(events)
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
        persistChanges()
    }

    func markAsAttended(_ event: NetworkingEventOpportunity) {
        event.attended = true
        event.attendedAt = Date()
        event.status = .attended
        persistChanges()
    }

    func markAsDebriefed(_ event: NetworkingEventOpportunity) {
        event.status = .debriefed
        persistChanges()
    }

    func markAsSkipped(_ event: NetworkingEventOpportunity) {
        event.status = .skipped
        persistChanges()
    }

    func setDiscoveryFeedback(_ event: NetworkingEventOpportunity, feedback: String, note: String? = nil) {
        event.discoveryFeedback = feedback
        event.discoveryFeedbackNote = note
        persistChanges()
    }

    /// Auto-mark planned events whose date is more than a day past and that
    /// were never marked attended as `.missed`. Only `.planned` qualifies —
    /// the user committed to those; a stale `.discovered` event was never a
    /// commitment, so it just ages out of the upcoming list. Idempotent: a
    /// swept event is `.missed` and never matches again; saves only when
    /// something changed.
    func sweepMissedEvents(now: Date = Date()) {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -1, to: now) else { return }
        let missed = allEvents.filter { $0.status == .planned && $0.date < cutoff }
        guard !missed.isEmpty else { return }
        for event in missed {
            event.status = .missed
        }
        persistChanges()
        Logger.info("Marked \(missed.count) past planned event(s) as missed", category: .storage)
    }
}
