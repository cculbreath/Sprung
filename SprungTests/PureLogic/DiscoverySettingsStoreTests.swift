//
//  DiscoverySettingsStoreTests.swift
//  SprungTests
//
//  Pure-logic coverage for DiscoverySettingsStore's standalone (non-blob) keys:
//   - eventDiscoveryAutoRunEnabled — opt-in gate for the unattended weekly
//     networking-event discovery run (must default to false: unattended LLM
//     spend must never fire until the user explicitly turns it on)
//   - eventDiscoveryStandingGuidance — guidance applied to every automatic run
//
//  Uses the store's `defaults:` injection seam with a `TestDefaults` suite so
//  these round-trips never touch the developer's real UserDefaults.standard.
//

import XCTest
@testable import Sprung

@MainActor
final class DiscoverySettingsStoreTests: XCTestCase {

    // MARK: - eventDiscoveryAutoRunEnabled

    func testEventDiscoveryAutoRunDisabledByDefault() {
        let store = DiscoverySettingsStore(defaults: TestDefaults().store)
        XCTAssertFalse(
            store.eventDiscoveryAutoRunEnabled,
            "unattended LLM spend must be an explicit opt-in, never on by default"
        )
    }

    func testEventDiscoveryAutoRunEnabledRoundTrips() {
        let defaults = TestDefaults()
        let store = DiscoverySettingsStore(defaults: defaults.store)

        store.eventDiscoveryAutoRunEnabled = true
        XCTAssertTrue(store.eventDiscoveryAutoRunEnabled)

        // Persists across store instances backed by the same defaults suite.
        let reloaded = DiscoverySettingsStore(defaults: defaults.store)
        XCTAssertTrue(reloaded.eventDiscoveryAutoRunEnabled)

        store.eventDiscoveryAutoRunEnabled = false
        XCTAssertFalse(store.eventDiscoveryAutoRunEnabled)
    }

    // MARK: - eventDiscoveryStandingGuidance

    func testEventDiscoveryStandingGuidanceDefaultsEmpty() {
        let store = DiscoverySettingsStore(defaults: TestDefaults().store)
        XCTAssertEqual(store.eventDiscoveryStandingGuidance, "")
    }

    func testEventDiscoveryStandingGuidanceRoundTrips() {
        let defaults = TestDefaults()
        let store = DiscoverySettingsStore(defaults: defaults.store)

        store.eventDiscoveryStandingGuidance = "virtual events only"
        XCTAssertEqual(store.eventDiscoveryStandingGuidance, "virtual events only")

        let reloaded = DiscoverySettingsStore(defaults: defaults.store)
        XCTAssertEqual(reloaded.eventDiscoveryStandingGuidance, "virtual events only")
    }

    // MARK: - lastSuccessfulEventDiscoveryAt (still exercised via the injection seam)

    func testLastSuccessfulEventDiscoveryAtNilUntilRecorded() {
        let store = DiscoverySettingsStore(defaults: TestDefaults().store)
        XCTAssertNil(store.lastSuccessfulEventDiscoveryAt)

        let now = Date()
        store.recordSuccessfulEventDiscovery(at: now)
        XCTAssertEqual(
            store.lastSuccessfulEventDiscoveryAt?.timeIntervalSince1970 ?? -1,
            now.timeIntervalSince1970,
            accuracy: 0.001
        )
    }
}
