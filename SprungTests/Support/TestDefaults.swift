//
//  TestDefaults.swift
//  SprungTests
//
//  An isolated `UserDefaults` suite for tests that exercise code reading/writing defaults
//  (model-id config, Discovery `SearchPreferences`/`DiscoverySettings`, generation options).
//  Never touch `UserDefaults.standard` in tests — it pollutes the developer's real settings
//  and leaks state between test methods. Create a `TestDefaults` per test; it auto-clears.
//
//  Usage:
//      let defaults = TestDefaults()          // unique, empty suite
//      defaults.store.set("x", forKey: "k")
//      // ... pass `defaults.store` into code under test ...
//      // suite is wiped on deinit / explicit reset()
//

import Foundation
import XCTest

/// Wraps a uniquely-named `UserDefaults` suite and guarantees cleanup.
final class TestDefaults {

    let suiteName: String
    let store: UserDefaults

    /// Create a fresh, empty suite. The name is unique per instance so parallel tests
    /// never collide. (UUID is fine here — this is test plumbing, not replayed logic.)
    init(suiteName: String = "SprungTests.\(UUID().uuidString)") {
        self.suiteName = suiteName
        guard let store = UserDefaults(suiteName: suiteName) else {
            fatalError("Failed to create UserDefaults suite \(suiteName)")
        }
        self.store = store
        store.removePersistentDomain(forName: suiteName)
    }

    /// Remove everything in the suite (call between phases of a single test if needed).
    func reset() {
        store.removePersistentDomain(forName: suiteName)
    }

    deinit {
        store.removePersistentDomain(forName: suiteName)
    }
}
