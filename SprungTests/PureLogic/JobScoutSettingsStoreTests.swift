//
//  JobScoutSettingsStoreTests.swift
//  SprungTests
//
//  Pure-logic coverage for DiscoverySettingsStore's Job-Scout keys:
//   - scoutEnabledBoards — defaults to ALL boards until the user saves a
//     choice; an explicitly-saved empty selection persists as empty
//   - scoutAutoRunCadence — opt-in gate for the unattended scout run (must
//     default to .off: unattended LLM spend never fires until enabled), plus
//     the cadence-elapsed date math the auto-run guard keys on (injected now)
//   - scoutStandingGuidance / scoutRecommendationCount — run parameters
//   - lastSuccessfulScoutRunAt — stamped only through recordSuccessfulScoutRun
//   - lastScoutReport — the full ScoutRunReport Codable blob round-trip
//
//  Uses the store's `defaults:` injection seam with a `TestDefaults` suite so
//  these round-trips never touch the developer's real UserDefaults.standard.
//

import XCTest
@testable import Sprung

@MainActor
final class JobScoutSettingsStoreTests: XCTestCase {

    // MARK: - scoutEnabledBoards

    func testScoutEnabledBoardsDefaultsToAllBoards() {
        let store = DiscoverySettingsStore(defaults: TestDefaults().store)
        XCTAssertEqual(
            store.scoutEnabledBoards,
            JobScoutService.ScoutBoard.allCases,
            "until the user saves a choice, every board participates"
        )
    }

    func testScoutEnabledBoardsRoundTripsAcrossStoreInstances() {
        let defaults = TestDefaults()
        let store = DiscoverySettingsStore(defaults: defaults.store)

        store.scoutEnabledBoards = [.dice, .linkedIn]
        XCTAssertEqual(store.scoutEnabledBoards, [.dice, .linkedIn])

        let reloaded = DiscoverySettingsStore(defaults: defaults.store)
        XCTAssertEqual(reloaded.scoutEnabledBoards, [.dice, .linkedIn])
    }

    func testScoutEnabledBoardsExplicitEmptySelectionPersistsAsEmpty() {
        let store = DiscoverySettingsStore(defaults: TestDefaults().store)
        store.scoutEnabledBoards = []
        XCTAssertEqual(
            store.scoutEnabledBoards, [],
            "a user who disabled every board must not be silently reset to all three"
        )
    }

    func testScoutEnabledBoardsDropsUnknownRawValues() {
        let defaults = TestDefaults()
        defaults.store.set(["dice", "monster", "linkedIn"], forKey: "discoveryScoutEnabledBoards")
        let store = DiscoverySettingsStore(defaults: defaults.store)
        XCTAssertEqual(store.scoutEnabledBoards, [.dice, .linkedIn],
                       "unknown persisted board names are dropped, never crash the read")
    }

    // MARK: - scoutAutoRunCadence

    func testScoutAutoRunCadenceDefaultsOff() {
        let store = DiscoverySettingsStore(defaults: TestDefaults().store)
        XCTAssertEqual(
            store.scoutAutoRunCadence, .off,
            "unattended LLM spend must be an explicit opt-in, never on by default"
        )
    }

    func testScoutAutoRunCadenceRoundTrips() {
        let defaults = TestDefaults()
        let store = DiscoverySettingsStore(defaults: defaults.store)

        store.scoutAutoRunCadence = .weekly
        XCTAssertEqual(store.scoutAutoRunCadence, .weekly)

        let reloaded = DiscoverySettingsStore(defaults: defaults.store)
        XCTAssertEqual(reloaded.scoutAutoRunCadence, .weekly)

        store.scoutAutoRunCadence = .daily
        XCTAssertEqual(store.scoutAutoRunCadence, .daily)
    }

    // MARK: - Cadence date math (the auto-run guard's clock, injected now)

    func testOffCadenceNeverElapses() {
        let cadence = DiscoverySettingsStore.ScoutCadence.off
        XCTAssertFalse(cadence.hasElapsed(since: nil, now: Date()))
        XCTAssertFalse(cadence.hasElapsed(
            since: Date(timeIntervalSince1970: 0),
            now: Date(timeIntervalSince1970: 10_000_000)
        ))
    }

    func testNeverRunCountsAsElapsedForActiveCadences() {
        let now = Date()
        XCTAssertTrue(DiscoverySettingsStore.ScoutCadence.daily.hasElapsed(since: nil, now: now))
        XCTAssertTrue(DiscoverySettingsStore.ScoutCadence.weekly.hasElapsed(since: nil, now: now))
    }

    func testDailyCadenceElapsesAtOneDay() {
        let cadence = DiscoverySettingsStore.ScoutCadence.daily
        let lastRun = Date(timeIntervalSince1970: 1_750_000_000)

        let twelveHoursLater = lastRun.addingTimeInterval(12 * 3600)
        XCTAssertFalse(cadence.hasElapsed(since: lastRun, now: twelveHoursLater))

        let oneDayLater = lastRun.addingTimeInterval(24 * 3600)
        XCTAssertTrue(cadence.hasElapsed(since: lastRun, now: oneDayLater))
    }

    func testWeeklyCadenceElapsesAtSevenDays() {
        let cadence = DiscoverySettingsStore.ScoutCadence.weekly
        let lastRun = Date(timeIntervalSince1970: 1_750_000_000)

        let sixDaysLater = lastRun.addingTimeInterval(6 * 24 * 3600)
        XCTAssertFalse(cadence.hasElapsed(since: lastRun, now: sixDaysLater))

        let sevenDaysLater = lastRun.addingTimeInterval(7 * 24 * 3600)
        XCTAssertTrue(cadence.hasElapsed(since: lastRun, now: sevenDaysLater))
    }

    // MARK: - scoutStandingGuidance

    func testScoutStandingGuidanceDefaultsEmptyAndRoundTrips() {
        let defaults = TestDefaults()
        let store = DiscoverySettingsStore(defaults: defaults.store)
        XCTAssertEqual(store.scoutStandingGuidance, "")

        store.scoutStandingGuidance = "favor medical physics roles"
        XCTAssertEqual(store.scoutStandingGuidance, "favor medical physics roles")

        let reloaded = DiscoverySettingsStore(defaults: defaults.store)
        XCTAssertEqual(reloaded.scoutStandingGuidance, "favor medical physics roles")
    }

    // MARK: - scoutRecommendationCount

    func testScoutRecommendationCountDefaultsToFive() {
        let store = DiscoverySettingsStore(defaults: TestDefaults().store)
        XCTAssertEqual(store.scoutRecommendationCount, 5)
    }

    func testScoutRecommendationCountRoundTrips() {
        let defaults = TestDefaults()
        let store = DiscoverySettingsStore(defaults: defaults.store)

        store.scoutRecommendationCount = 3
        XCTAssertEqual(store.scoutRecommendationCount, 3)

        let reloaded = DiscoverySettingsStore(defaults: defaults.store)
        XCTAssertEqual(reloaded.scoutRecommendationCount, 3)
    }

    // MARK: - lastSuccessfulScoutRunAt

    func testLastSuccessfulScoutRunNilUntilRecorded() {
        let store = DiscoverySettingsStore(defaults: TestDefaults().store)
        XCTAssertNil(store.lastSuccessfulScoutRunAt)

        let stamp = Date(timeIntervalSince1970: 1_751_000_000)
        store.recordSuccessfulScoutRun(at: stamp)
        XCTAssertEqual(
            store.lastSuccessfulScoutRunAt?.timeIntervalSince1970 ?? -1,
            stamp.timeIntervalSince1970,
            accuracy: 0.001
        )
    }

    // MARK: - lastScoutReport (Codable blob)

    func testLastScoutReportNilByDefault() {
        let store = DiscoverySettingsStore(defaults: TestDefaults().store)
        XCTAssertNil(store.lastScoutReport)
    }

    func testLastScoutReportRoundTripsFullReport() throws {
        let defaults = TestDefaults()
        let store = DiscoverySettingsStore(defaults: defaults.store)

        let startedAt = Date(timeIntervalSince1970: 1_751_500_000)
        let report = JobScoutService.ScoutRunReport(
            startedAt: startedAt,
            boardsSearched: ["Dice", "LinkedIn"],
            resultsFound: 42,
            duplicatesDropped: 7,
            recommendations: [
                JobScoutService.ScoutRecommendation(
                    url: "https://www.dice.com/job-detail/abc-123",
                    title: "Senior Medical Physicist",
                    company: "Acme Oncology",
                    reasoning: "Their commissioning work matches the linac experience in the dossier.",
                    imported: true
                ),
                JobScoutService.ScoutRecommendation(
                    url: "https://www.linkedin.com/jobs/view/999/",
                    title: "Physicist II",
                    company: "Beta Health",
                    reasoning: "A close fit for the clinical QA background.",
                    imported: false
                )
            ],
            notes: ["LinkedIn was skipped: the one-time LinkedIn consent hasn't been accepted."]
        )

        store.lastScoutReport = report

        // Reload through a fresh store instance: the blob survives relaunches.
        let reloaded = DiscoverySettingsStore(defaults: defaults.store)
        let decoded = try XCTUnwrap(reloaded.lastScoutReport)
        XCTAssertEqual(decoded.startedAt.timeIntervalSince1970, startedAt.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(decoded.boardsSearched, ["Dice", "LinkedIn"])
        XCTAssertEqual(decoded.resultsFound, 42)
        XCTAssertEqual(decoded.duplicatesDropped, 7)
        XCTAssertEqual(decoded.recommendations.count, 2)
        XCTAssertEqual(decoded.recommendations[0].title, "Senior Medical Physicist")
        XCTAssertTrue(decoded.recommendations[0].imported)
        XCTAssertEqual(decoded.recommendations[1].company, "Beta Health")
        XCTAssertFalse(decoded.recommendations[1].imported)
        XCTAssertEqual(decoded.notes.count, 1)
    }

    func testLastScoutReportSetNilClearsTheBlob() {
        let defaults = TestDefaults()
        let store = DiscoverySettingsStore(defaults: defaults.store)
        store.lastScoutReport = JobScoutService.ScoutRunReport(
            startedAt: Date(),
            boardsSearched: [],
            resultsFound: 0,
            duplicatesDropped: 0,
            recommendations: [],
            notes: []
        )
        XCTAssertNotNil(store.lastScoutReport)

        store.lastScoutReport = nil
        XCTAssertNil(store.lastScoutReport)
        XCTAssertNil(defaults.store.data(forKey: "discoveryLastScoutReport"))
    }

    func testLastScoutReportUndecodableBlobReadsAsNil() {
        let defaults = TestDefaults()
        defaults.store.set(Data("not json".utf8), forKey: "discoveryLastScoutReport")
        let store = DiscoverySettingsStore(defaults: defaults.store)
        XCTAssertNil(store.lastScoutReport, "a corrupt blob reads as no report, never a crash")
    }
}
