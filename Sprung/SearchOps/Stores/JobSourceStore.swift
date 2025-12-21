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
final class JobSourceStore: SwiftDataStore {
    unowned let modelContext: ModelContext

    init(context: ModelContext) {
        modelContext = context
    }

    var sources: [JobSource] {
        (try? modelContext.fetch(
            FetchDescriptor<JobSource>(sortBy: [SortDescriptor(\.name)])
        )) ?? []
    }

    var activeSources: [JobSource] {
        sources.filter { $0.isActive }
    }

    var dueSources: [JobSource] {
        activeSources.filter { $0.isDue }
    }

    var sourcesByCategory: [SourceCategory: [JobSource]] {
        Dictionary(grouping: activeSources) { $0.category }
    }

    func add(_ source: JobSource) {
        modelContext.insert(source)
        saveContext()
    }

    func addMultiple(_ sources: [JobSource]) {
        for source in sources {
            modelContext.insert(source)
        }
        saveContext()
    }

    func markVisited(_ source: JobSource) {
        source.lastVisitedAt = Date()
        source.totalVisits += 1
        saveContext()
    }

    func incrementOpeningsCaptured(_ source: JobSource) {
        source.openingsCaptured += 1
        saveContext()
    }

    func delete(_ source: JobSource) {
        modelContext.delete(source)
        saveContext()
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

    /// Get sources that should be suggested for removal
    var sourcesToSuggestRemoval: [JobSource] {
        sources.filter { $0.shouldSuggestRemoval }
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

        saveContext()
    }

    /// Get top sources by effectiveness
    func topSourcesByEffectiveness(limit: Int = 5) -> [JobSource] {
        activeSources
            .filter { $0.effectiveness != nil }
            .sorted { ($0.effectiveness ?? 0) > ($1.effectiveness ?? 0) }
            .prefix(limit)
            .map { $0 }
    }
}
