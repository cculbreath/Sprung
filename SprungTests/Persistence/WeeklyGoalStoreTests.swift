//
//  WeeklyGoalStoreTests.swift
//  SprungTests
//
//  WeeklyGoal target seeding and review-note plumbing. Contract under test:
//  SearchPreferences is the single source of truth for the weekly
//  application/events targets — every newly minted week snapshots them at
//  creation time (no hardcoded per-week defaults). The contacts target has
//  no preferences field and carries forward from the most recent prior
//  week's row. `previousWeekUserNotes()` is the reader that feeds saved
//  Weekly Review notes into the reflection and coaching contexts.
//

import XCTest
import SwiftData
@testable import Sprung

@MainActor
final class WeeklyGoalStoreTests: InMemoryStoreCase {

    /// Mutable preferences fixture injected as the store's `currentPreferences`
    /// closure, so tests can steer targets without touching UserDefaults.
    private final class PreferencesBox {
        var prefs = SearchPreferences()
    }

    private func makeGoalStore(preferences box: PreferencesBox) -> WeeklyGoalStore {
        let templateStore = TemplateStore(context: context)
        let applicantProfileStore = ApplicantProfileStore(context: context)
        let experienceDefaultsStore = ExperienceDefaultsStore(context: context)
        let coverRefStore = CoverRefStore(context: context)

        let exportService = ResumeExportService(
            templateStore: templateStore,
            applicantProfileStore: applicantProfileStore
        )
        let exportCoordinator = ResumeExportCoordinator(exportService: exportService)
        let resStore = ResStore(
            context: context,
            exportCoordinator: exportCoordinator,
            experienceDefaultsStore: experienceDefaultsStore
        )
        let coverLetterStore = CoverLetterStore(
            context: context,
            refStore: coverRefStore,
            applicantProfileStore: applicantProfileStore
        )
        let jobAppStore = JobAppStore(
            context: context,
            resStore: resStore,
            coverLetterStore: coverLetterStore
        )
        return WeeklyGoalStore(
            context: context,
            jobAppStore: jobAppStore,
            currentPreferences: { box.prefs }
        )
    }

    private var currentWeekStart: Date {
        let calendar = Calendar.current
        return calendar.date(
            from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        ) ?? Date()
    }

    private var previousWeekStart: Date {
        Calendar.current.date(byAdding: .weekOfYear, value: -1, to: currentWeekStart) ?? Date()
    }

    // MARK: - Target Seeding

    func testNewWeekSeedsTargetsFromPreferences() {
        let box = PreferencesBox()
        box.prefs.weeklyApplicationTarget = 12
        box.prefs.weeklyNetworkingTarget = 4
        let store = makeGoalStore(preferences: box)

        let goal = store.currentWeek()

        XCTAssertEqual(goal.applicationTarget, 12)
        XCTAssertEqual(goal.eventsAttendedTarget, 4)
    }

    func testMintedWeekIsSnapshotNotLiveView() {
        // Once a week's row exists, later preference edits don't rewrite it —
        // the row is a point-in-time snapshot; edits flow through
        // applyTargetsToCurrentWeek (this week) and mint-time seeding (future
        // weeks).
        let box = PreferencesBox()
        box.prefs.weeklyApplicationTarget = 10
        box.prefs.weeklyNetworkingTarget = 3
        let store = makeGoalStore(preferences: box)

        let goal = store.currentWeek()
        box.prefs.weeklyApplicationTarget = 99
        box.prefs.weeklyNetworkingTarget = 99

        let sameGoal = store.currentWeek()
        XCTAssertEqual(sameGoal.id, goal.id)
        XCTAssertEqual(sameGoal.applicationTarget, 10)
        XCTAssertEqual(sameGoal.eventsAttendedTarget, 3)
    }

    func testRemintAfterPreferenceEditSeedsNewValues() {
        // Simulates the week rollover: a week minted after a preference edit
        // picks up the edited targets, not hardcoded defaults.
        let box = PreferencesBox()
        box.prefs.weeklyApplicationTarget = 5
        box.prefs.weeklyNetworkingTarget = 2
        let store = makeGoalStore(preferences: box)

        let firstMint = store.currentWeek()
        store.delete(firstMint)

        box.prefs.weeklyApplicationTarget = 8
        box.prefs.weeklyNetworkingTarget = 6

        let remint = store.currentWeek()
        XCTAssertEqual(remint.applicationTarget, 8)
        XCTAssertEqual(remint.eventsAttendedTarget, 6)
    }

    func testNewWeekCarriesContactsTargetForwardFromPriorWeek() {
        let box = PreferencesBox()
        let store = makeGoalStore(preferences: box)

        let lastWeek = WeeklyGoal(weekStartDate: previousWeekStart)
        lastWeek.newContactsTarget = 7
        store.add(lastWeek)

        let goal = store.currentWeek()
        XCTAssertEqual(goal.newContactsTarget, 7)
    }

    // MARK: - applyTargetsToCurrentWeek

    func testApplyTargetsSnapshotsOntoCurrentRow() {
        let box = PreferencesBox()
        let store = makeGoalStore(preferences: box)

        store.applyTargetsToCurrentWeek(applications: 11, events: 3, contacts: 6)

        let goal = store.currentWeek()
        XCTAssertEqual(goal.applicationTarget, 11)
        XCTAssertEqual(goal.eventsAttendedTarget, 3)
        XCTAssertEqual(goal.newContactsTarget, 6)
    }

    func testApplyTargetsNilContactsLeavesContactsUnchanged() {
        // The onboarding write path: it collects only application and events
        // targets, so it passes nil to leave the row's contacts target alone.
        let box = PreferencesBox()
        let store = makeGoalStore(preferences: box)

        store.applyTargetsToCurrentWeek(applications: 9, events: 2, contacts: 4)
        store.applyTargetsToCurrentWeek(applications: 10, events: 1, contacts: nil)

        let goal = store.currentWeek()
        XCTAssertEqual(goal.applicationTarget, 10)
        XCTAssertEqual(goal.eventsAttendedTarget, 1)
        XCTAssertEqual(goal.newContactsTarget, 4)
    }

    // MARK: - previousWeekUserNotes

    func testPreviousWeekUserNotesReturnsMostRecentPriorWeeksNotes() {
        let box = PreferencesBox()
        let store = makeGoalStore(preferences: box)

        let lastWeek = WeeklyGoal(weekStartDate: previousWeekStart)
        lastWeek.userNotes = "Wins: shipped the parser"
        store.add(lastWeek)

        let current = store.currentWeek()
        current.userNotes = "Wins: this week's notes"
        store.update(current)

        XCTAssertEqual(store.previousWeekUserNotes(), "Wins: shipped the parser")
    }

    func testPreviousWeekUserNotesSkipsBlankWeeks() {
        let box = PreferencesBox()
        let store = makeGoalStore(preferences: box)

        let twoWeeksAgo = WeeklyGoal(
            weekStartDate: Calendar.current.date(byAdding: .weekOfYear, value: -2, to: currentWeekStart) ?? Date()
        )
        twoWeeksAgo.userNotes = "Wins: older but real notes"
        store.add(twoWeeksAgo)

        let lastWeek = WeeklyGoal(weekStartDate: previousWeekStart)
        lastWeek.userNotes = "   \n  "
        store.add(lastWeek)

        XCTAssertEqual(store.previousWeekUserNotes(), "Wins: older but real notes")
    }

    func testPreviousWeekUserNotesNilWhenNoPriorNotesExist() {
        let box = PreferencesBox()
        let store = makeGoalStore(preferences: box)

        let current = store.currentWeek()
        current.userNotes = "Wins: only the current week has notes"
        store.update(current)

        XCTAssertNil(store.previousWeekUserNotes())
    }
}
