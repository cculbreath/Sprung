//
//  JobSourceStore.swift
//  Sprung
//
//  Store for managing job sources.
//

import SwiftData
import Foundation

@Observable
@MainActor
final class JobSourceStore: EntityStore {
    typealias Entity = JobSource

    unowned let modelContext: ModelContext

    /// `@Observable` refresh counter; the EntityStore extension bumps it on every mutation.
    var changeVersion: Int = 0

    init(context: ModelContext) {
        modelContext = context
    }

    var sources: [JobSource] {
        fetchAll(sortBy: [SortDescriptor(\.name)])
    }

    var activeSources: [JobSource] {
        sources.filter { $0.isActive }
    }

    var dueSources: [JobSource] {
        activeSources.filter { $0.isDue }
    }

    func addMultiple(_ sources: [JobSource]) {
        addAll(sources)
    }

    func markVisited(_ source: JobSource) {
        source.lastVisitedAt = Date()
        source.totalVisits += 1
        update(source)
    }

    func updateCadence(_ source: JobSource, days: Int) {
        source.recommendedCadenceDays = days
        update(source)
    }

    func source(byId id: UUID) -> JobSource? {
        sources.first { $0.id == id }
    }

    func source(byUrl url: String) -> JobSource? {
        sources.first { $0.url == url }
    }

    /// Check if a source with this URL already exists
    func exists(url: String) -> Bool {
        sources.contains { $0.url == url }
    }

    /// Get sources that need URL revalidation
    var sourcesNeedingRevalidation: [JobSource] {
        activeSources.filter { $0.needsRevalidation }
    }

    /// Update URL validation result
    func updateValidation(_ source: JobSource, valid: Bool) {
        source.urlLastVerified = Date()
        source.urlValid = valid

        if valid {
            source.consecutiveFailures = 0
            source.firstFailureAt = nil
        } else {
            if source.consecutiveFailures == 0 {
                source.firstFailureAt = Date()
            }
            source.consecutiveFailures += 1
        }

        update(source)
    }

    /// Get top sources by effectiveness
    func topSourcesByEffectiveness(limit: Int = 5) -> [JobSource] {
        activeSources
            .filter { $0.effectiveness != nil }
            .sorted { ($0.effectiveness ?? 0) > ($1.effectiveness ?? 0) }
            .prefix(limit)
            .map { $0 }
    }

    /// Get sources that were checked this week
    func checkedThisWeek() -> [JobSource] {
        let calendar = Calendar.current
        let weekStart = calendar.date(
            from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        ) ?? Date()

        return sources.filter { source in
            guard let lastVisited = source.lastVisitedAt else { return false }
            return lastVisited >= weekStart
        }
    }
}
