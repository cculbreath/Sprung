//
//  SearchPreferencesStore.swift
//  Sprung
//
//  Store for managing search preferences (singleton pattern).
//

import SwiftData
import Foundation

@Observable
@MainActor
final class SearchPreferencesStore: SwiftDataStore {
    unowned let modelContext: ModelContext

    init(context: ModelContext) {
        modelContext = context
    }

    /// Returns the singleton preferences, creating if needed
    func current() -> SearchPreferences {
        let existing = try? modelContext.fetch(FetchDescriptor<SearchPreferences>())
        if let prefs = existing?.first {
            return prefs
        }
        let newPrefs = SearchPreferences()
        modelContext.insert(newPrefs)
        saveContext()
        return newPrefs
    }

    func update(_ prefs: SearchPreferences) {
        prefs.updatedAt = Date()
        saveContext()
    }

    /// Check if preferences have been configured (not just defaults)
    var isConfigured: Bool {
        let prefs = current()
        return !prefs.targetSectors.isEmpty && !prefs.primaryLocation.isEmpty
    }
}
