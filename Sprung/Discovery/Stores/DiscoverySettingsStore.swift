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

    // MARK: - Event-Discovery Auto-Run State

    /// UserDefaults key for the last SUCCESSFUL networking-event discovery run
    /// (manual or automatic — both funnel through the same completion point).
    /// Failed or cancelled runs never update it.
    private static let lastSuccessfulEventDiscoveryKey = "discoveryLastSuccessfulEventDiscoveryAt"

    var lastSuccessfulEventDiscoveryAt: Date? {
        UserDefaults.standard.object(forKey: Self.lastSuccessfulEventDiscoveryKey) as? Date
    }

    func recordSuccessfulEventDiscovery(at date: Date = Date()) {
        UserDefaults.standard.set(date, forKey: Self.lastSuccessfulEventDiscoveryKey)
    }
}
