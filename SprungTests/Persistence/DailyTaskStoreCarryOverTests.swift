//
//  DailyTaskStoreCarryOverTests.swift
//  SprungTests
//
//  Pins DailyTaskStore.previousTaskDay() (the carry-over delta base for coaching
//  openers) and completionStreakDays() (consecutive completed-day counting).
//

import XCTest
import SwiftData
@testable import Sprung

@MainActor
final class DailyTaskStoreCarryOverTests: InMemoryStoreCase {

    // MARK: - Helpers

    private func makeTask(daysAgo: Int, completed: Bool = false) -> DailyTask {
        let task = DailyTask(type: .gatherLeads, title: "Task \(daysAgo)d ago")
        task.createdAt = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        if completed {
            task.isCompleted = true
            task.completedAt = task.createdAt
        }
        return task
    }

    // MARK: - previousTaskDay()

    func testPreviousTaskDayReturnsMostRecentPriorDayWithCompletionState() throws {
        let store = DailyTaskStore(context: context)
        store.add(makeTask(daysAgo: 2))                       // older prior day — should be skipped
        store.add(makeTask(daysAgo: 1, completed: true))       // yesterday, completed
        store.add(makeTask(daysAgo: 1, completed: false))      // yesterday, still pending
        store.add(makeTask(daysAgo: 0))                        // today — excluded entirely

        let result = try XCTUnwrap(store.previousTaskDay())

        let expectedDay = Calendar.current.startOfDay(
            for: Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        )
        XCTAssertEqual(result.date, expectedDay)
        XCTAssertEqual(result.tasks.count, 2)
        XCTAssertTrue(result.tasks.contains { $0.isCompleted })
        XCTAssertTrue(result.tasks.contains { !$0.isCompleted })
    }

    func testPreviousTaskDayReturnsNilWhenOnlyTodaysTasksExist() {
        let store = DailyTaskStore(context: context)
        store.add(makeTask(daysAgo: 0))
        XCTAssertNil(store.previousTaskDay())
    }

    func testPreviousTaskDayReturnsNilForEmptyStore() {
        let store = DailyTaskStore(context: context)
        XCTAssertNil(store.previousTaskDay())
    }

    // MARK: - completionStreakDays()

    func testCompletionStreakDaysCountsConsecutiveDaysAndStopsAtGap() {
        let store = DailyTaskStore(context: context)
        store.add(makeTask(daysAgo: 0, completed: true))
        store.add(makeTask(daysAgo: 1, completed: true))
        store.add(makeTask(daysAgo: 2, completed: true))
        // Gap at daysAgo 3 (no completion that day) breaks the streak before this one:
        store.add(makeTask(daysAgo: 4, completed: true))

        XCTAssertEqual(store.completionStreakDays(), 3)
    }

    func testCompletionStreakDaysCountsYesterdayEvenWithoutTodaysCompletion() {
        let store = DailyTaskStore(context: context)
        store.add(makeTask(daysAgo: 1, completed: true))
        store.add(makeTask(daysAgo: 2, completed: true))
        store.add(makeTask(daysAgo: 0, completed: false))  // today has a task, but not completed yet

        XCTAssertEqual(store.completionStreakDays(), 2, "a streak that ended yesterday still counts until today is over")
    }

    func testCompletionStreakDaysCountsDayWithOnlyPartialCompletion() {
        // Real contract: a day counts toward the streak if ANY task that day was
        // completed — not that every task created that day was completed.
        let store = DailyTaskStore(context: context)
        store.add(makeTask(daysAgo: 0, completed: true))
        store.add(makeTask(daysAgo: 0, completed: false))
        store.add(makeTask(daysAgo: 1, completed: true))

        XCTAssertEqual(store.completionStreakDays(), 2)
    }

    func testCompletionStreakDaysZeroWhenNeitherTodayNorYesterdayCompleted() {
        let store = DailyTaskStore(context: context)
        store.add(makeTask(daysAgo: 2, completed: true))

        XCTAssertEqual(store.completionStreakDays(), 0)
    }

    func testCompletionStreakDaysZeroForEmptyStore() {
        let store = DailyTaskStore(context: context)
        XCTAssertEqual(store.completionStreakDays(), 0)
    }
}
