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
    /// Injectable seam for the UserDefaults keys owned by this store.
    /// Defaults to `.standard` in production; tests pass `TestDefaults().store`
    /// so these round-trips never touch the developer's real defaults.
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Event-Discovery Auto-Run State

    /// UserDefaults key for the last SUCCESSFUL networking-event discovery run
    /// (manual or automatic — both funnel through the same completion point).
    /// Failed or cancelled runs never update it.
    private static let lastSuccessfulEventDiscoveryKey = "discoveryLastSuccessfulEventDiscoveryAt"

    var lastSuccessfulEventDiscoveryAt: Date? {
        defaults.object(forKey: Self.lastSuccessfulEventDiscoveryKey) as? Date
    }

    func recordSuccessfulEventDiscovery(at date: Date = Date()) {
        defaults.set(date, forKey: Self.lastSuccessfulEventDiscoveryKey)
    }

    // MARK: - Event-Discovery Auto-Run Toggle + Standing Guidance

    private static let eventDiscoveryAutoRunEnabledKey = "discoveryEventDiscoveryAutoRunEnabled"

    /// Opt-in gate for the unattended weekly networking-event discovery run.
    /// Defaults to `false`: an automatic run at coordinator startup spends real
    /// LLM budget without the user in the loop, so it must be explicitly enabled.
    var eventDiscoveryAutoRunEnabled: Bool {
        get { defaults.bool(forKey: Self.eventDiscoveryAutoRunEnabledKey) }
        set { defaults.set(newValue, forKey: Self.eventDiscoveryAutoRunEnabledKey) }
    }

    private static let eventDiscoveryStandingGuidanceKey = "discoveryEventDiscoveryStandingGuidance"

    /// Standing guidance applied to every automatic weekly run. Manual runs use
    /// their own per-run guidance instead (see `EventsView`'s discover trigger).
    /// Empty means no guidance — the auto run proceeds plain.
    var eventDiscoveryStandingGuidance: String {
        get { defaults.string(forKey: Self.eventDiscoveryStandingGuidanceKey) ?? "" }
        set { defaults.set(newValue, forKey: Self.eventDiscoveryStandingGuidanceKey) }
    }
}
