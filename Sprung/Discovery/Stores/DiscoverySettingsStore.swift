//
//  DiscoverySettingsStore.swift
//  Sprung
//
//  Store for managing Discovery module settings (UserDefaults-backed).
//

import Foundation

@Observable
@MainActor
final class DiscoverySettingsStore {
    private var cached: DiscoverySettings?

    init() {}

    func current() -> DiscoverySettings {
        if let cached {
            return cached
        }
        let settings = DiscoverySettings.load()
        cached = settings
        return settings
    }

    func update(_ settings: DiscoverySettings) {
        settings.save()
        cached = settings
    }
}
