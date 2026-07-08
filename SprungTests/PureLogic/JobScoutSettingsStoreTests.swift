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
//   - scoutAutoImportStrongMatches — opt-in auto-import toggle (defaults false)
//   - lastSuccessfulScoutRunAt — stamped only through recordSuccessfulScoutRun
//   - scoutRunHistory — the capped, newest-first ScoutRunReport blob round-trip
//   - scoutDismissedPostings — cross-run dismissed memory (TTL + cap)
//   - scoutTasteProfile — learned-preferences text + decision counter + stamp
//
//  Uses the store's `defaults:` injection seam with a `TestDefaults` suite so
//  these round-trips never touch the developer's real UserDefaults.standard.
//

import XCTest
@testable import Sprung

@MainActor
final class JobScoutSettingsStoreTests: XCTestCase {

    // MARK: - scoutEnabledBoards

    func testScoutEnabledBoardsDefaultsToNoKeyBoards() {
        let store = DiscoverySettingsStore(defaults: TestDefaults().store)
        XCTAssertEqual(
            store.scoutEnabledBoards,
            [.dice, .zipRecruiter, .linkedIn],
            "no-key boards are on by default; the aggregator boards stay off until a key is added"
        )
        XCTAssertFalse(store.scoutEnabledBoards.contains(.jsearch))
        XCTAssertFalse(store.scoutEnabledBoards.contains(.serpApi))
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

    // MARK: - scoutRunHistory (Codable blob, newest-first, capped)

    private func report(
        startedAt: Date,
        verdict: JobScoutMatchAssessment.Verdict = .strong,
        disposition: JobScoutService.ScoutRecommendation.Disposition = .pending
    ) -> JobScoutService.ScoutRunReport {
        JobScoutService.ScoutRunReport(
            startedAt: startedAt,
            boardsSearched: ["Dice"],
            resultsFound: 5,
            duplicatesDropped: 1,
            previouslyDismissedDropped: 0,
            recommendations: [
                JobScoutService.ScoutRecommendation(
                    url: "https://\(startedAt.timeIntervalSince1970)",
                    title: "Senior Medical Physicist",
                    company: "Acme Oncology",
                    reasoning: "Their commissioning work matches the linac experience in the dossier.",
                    match: JobScoutMatchAssessment(
                        skills: .strong, seniority: .strong, locationFit: .moderate,
                        compensation: .unknown, verdict: verdict
                    ),
                    disposition: disposition
                )
            ],
            notes: ["LinkedIn was skipped: the one-time LinkedIn consent hasn't been accepted."]
        )
    }

    func testScoutRunHistoryDefaultsEmpty() {
        let store = DiscoverySettingsStore(defaults: TestDefaults().store)
        XCTAssertTrue(store.scoutRunHistory.isEmpty)
    }

    func testScoutRunHistoryRoundTripsWithDispositions() throws {
        let defaults = TestDefaults()
        let store = DiscoverySettingsStore(defaults: defaults.store)
        let older = report(startedAt: Date(timeIntervalSince1970: 1_751_000_000), disposition: .dismissed)
        let newer = report(startedAt: Date(timeIntervalSince1970: 1_752_000_000), verdict: .promising, disposition: .imported)
        store.scoutRunHistory = [newer, older]   // newest first

        let reloaded = DiscoverySettingsStore(defaults: defaults.store)
        XCTAssertEqual(reloaded.scoutRunHistory.count, 2)
        XCTAssertEqual(reloaded.scoutRunHistory[0].recommendations[0].disposition, .imported)
        XCTAssertEqual(reloaded.scoutRunHistory[0].recommendations[0].match.verdict, .promising)
        XCTAssertEqual(reloaded.scoutRunHistory[1].recommendations[0].disposition, .dismissed)
        XCTAssertEqual(reloaded.scoutRunHistory[1].previouslyDismissedDropped, 0)
    }

    func testScoutRunHistoryCapsAtTheLimit() {
        let store = DiscoverySettingsStore(defaults: TestDefaults().store)
        let cap = DiscoverySettingsStore.scoutRunHistoryCap
        let reports = (0..<(cap + 5)).map {
            report(startedAt: Date(timeIntervalSince1970: TimeInterval(1_750_000_000 + $0)))
        }
        store.scoutRunHistory = reports
        XCTAssertEqual(store.scoutRunHistory.count, cap, "history keeps at most the cap, newest-first prefix")
    }

    func testScoutRunHistoryUndecodableBlobReadsAsEmpty() {
        let defaults = TestDefaults()
        defaults.store.set(Data("not json".utf8), forKey: "discoveryScoutRunHistory")
        let store = DiscoverySettingsStore(defaults: defaults.store)
        XCTAssertTrue(store.scoutRunHistory.isEmpty, "a corrupt blob reads as empty history, never a crash")
    }

    // MARK: - scoutAutoImportStrongMatches

    func testScoutAutoImportStrongMatchesDefaultsFalseAndRoundTrips() {
        let defaults = TestDefaults()
        let store = DiscoverySettingsStore(defaults: defaults.store)
        XCTAssertFalse(store.scoutAutoImportStrongMatches, "curation is the default — auto-import is opt-in")

        store.scoutAutoImportStrongMatches = true
        XCTAssertTrue(store.scoutAutoImportStrongMatches)

        let reloaded = DiscoverySettingsStore(defaults: defaults.store)
        XCTAssertTrue(reloaded.scoutAutoImportStrongMatches)
    }

    // MARK: - scoutDismissedPostings (cross-run memory)

    private func dismissed(
        url: String,
        title: String = "Physicist",
        company: String = "Acme",
        daysAgo: Int,
        now: Date
    ) -> JobScoutService.ScoutDismissedPosting {
        JobScoutService.ScoutDismissedPosting(
            url: url, title: title, company: company,
            dismissedAt: now.addingTimeInterval(TimeInterval(-daysAgo) * 86_400),
            reason: nil
        )
    }

    func testScoutDismissedPostingsDefaultsEmpty() {
        let store = DiscoverySettingsStore(defaults: TestDefaults().store)
        XCTAssertEqual(store.scoutDismissedPostings, [])
    }

    func testScoutDismissedPostingsRoundTripsAcrossStoreInstances() {
        let defaults = TestDefaults()
        let store = DiscoverySettingsStore(defaults: defaults.store)
        let now = Date()
        store.scoutDismissedPostings = [
            dismissed(url: "https://a", daysAgo: 1, now: now),
            dismissed(url: "https://b", title: "Engineer", company: "Beta", daysAgo: 2, now: now)
        ]
        let reloaded = DiscoverySettingsStore(defaults: defaults.store)
        XCTAssertEqual(reloaded.scoutDismissedPostings.map(\.url), ["https://a", "https://b"])
        XCTAssertEqual(reloaded.scoutDismissedPostings[1].company, "Beta")
    }

    func testRecordDismissedPostingsDedupsByURL() {
        let store = DiscoverySettingsStore(defaults: TestDefaults().store)
        let now = Date()
        store.recordDismissedPostings([dismissed(url: "https://a", daysAgo: 0, now: now)])
        store.recordDismissedPostings([
            dismissed(url: "https://a", daysAgo: 0, now: now),   // already recorded
            dismissed(url: "https://b", daysAgo: 0, now: now)
        ])
        XCTAssertEqual(store.scoutDismissedPostings.map(\.url), ["https://a", "https://b"],
                       "a URL already dismissed is not appended twice")
    }

    func testPruneDismissedDropsEntriesPastTheTTL() {
        let now = Date()
        let fresh = dismissed(url: "https://fresh", daysAgo: 10, now: now)
        let stale = dismissed(url: "https://stale", daysAgo: DiscoverySettingsStore.scoutDismissedTTLDays + 5, now: now)
        let pruned = DiscoverySettingsStore.pruneDismissed([stale, fresh], now: now)
        XCTAssertEqual(pruned.map(\.url), ["https://fresh"],
                       "entries older than the TTL are dropped")
    }

    func testPruneDismissedCapsOldestFirst() {
        let now = Date()
        let cap = DiscoverySettingsStore.scoutDismissedCap
        // cap + 3 entries, all within the TTL (seconds apart so the cap, not the
        // TTL, is what trims them). Index 0 is newest.
        let entries = (0..<(cap + 3)).map { index in
            JobScoutService.ScoutDismissedPosting(
                url: "https://\(index)", title: "T", company: "C",
                dismissedAt: now.addingTimeInterval(-Double(index)), reason: nil
            )
        }
        let pruned = DiscoverySettingsStore.pruneDismissed(entries, now: now)
        XCTAssertEqual(pruned.count, cap)
        XCTAssertTrue(pruned.contains { $0.url == "https://0" }, "the newest survives")
        XCTAssertFalse(pruned.contains { $0.url == "https://\(cap + 2)" }, "the oldest is dropped")
        // Survivors stay chronological: oldest-kept first, newest last.
        XCTAssertEqual(pruned.first?.url, "https://\(cap - 1)")
        XCTAssertEqual(pruned.last?.url, "https://0")
    }

    // MARK: - Learned taste profile

    func testScoutTasteProfileDefaultsEmpty() {
        let store = DiscoverySettingsStore(defaults: TestDefaults().store)
        XCTAssertEqual(store.scoutTasteProfile, "")
        XCTAssertNil(store.scoutTasteProfileUpdatedAt)
        XCTAssertEqual(store.scoutDecisionsSinceSynthesis, 0)
    }

    func testRecordScoutDecisionIncrementsCounter() {
        let store = DiscoverySettingsStore(defaults: TestDefaults().store)
        store.recordScoutDecision()
        store.recordScoutDecision()
        XCTAssertEqual(store.scoutDecisionsSinceSynthesis, 2)
    }

    func testApplyTasteProfileStoresResetsCounterAndStamps() {
        let defaults = TestDefaults()
        let store = DiscoverySettingsStore(defaults: defaults.store)
        store.recordScoutDecision()
        store.recordScoutDecision()

        let when = Date(timeIntervalSince1970: 1_760_000_000)
        store.applyTasteProfile("Pursues clinical roles; avoids relocation.", at: when)

        XCTAssertEqual(store.scoutTasteProfile, "Pursues clinical roles; avoids relocation.")
        XCTAssertEqual(store.scoutDecisionsSinceSynthesis, 0, "installing a profile means we're current")
        XCTAssertEqual(
            store.scoutTasteProfileUpdatedAt?.timeIntervalSince1970 ?? -1,
            when.timeIntervalSince1970, accuracy: 0.001
        )

        // Survives a relaunch.
        let reloaded = DiscoverySettingsStore(defaults: defaults.store)
        XCTAssertEqual(reloaded.scoutTasteProfile, "Pursues clinical roles; avoids relocation.")
        XCTAssertEqual(reloaded.scoutDecisionsSinceSynthesis, 0)
    }
}
