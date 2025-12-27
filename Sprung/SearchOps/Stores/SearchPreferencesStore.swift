//
//  SearchPreferencesStore.swift
//  Sprung
//
//  Store for managing search preferences (UserDefaults-backed).
//

import Foundation

@Observable
@MainActor
final class SearchPreferencesStore {
    private var cached: SearchPreferences?

    init() {}

    /// Returns the preferences, loading from UserDefaults if needed
    func current() -> SearchPreferences {
        if let cached {
            return cached
        }
        let prefs = SearchPreferences.load()
        cached = prefs
        return prefs
    }

    func update(_ prefs: SearchPreferences) {
        prefs.save()
        cached = prefs
    }

    /// Check if preferences have been configured (not just defaults)
    var isConfigured: Bool {
        let prefs = current()
        return !prefs.targetSectors.isEmpty && !prefs.primaryLocation.isEmpty
    }
}
