//
//  EventWeekGroupingTests.swift
//  SprungTests
//
//  Pure-logic coverage for EventWeekBucket: day-granularity "this week"
//  vs "coming up" bucketing used by EventsView's grouped list.
//

import XCTest
@testable import Sprung

final class EventWeekGroupingTests: XCTestCase {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        guard let timeZone = TimeZone(identifier: "UTC") else {
            XCTFail("UTC time zone unavailable")
            return calendar
        }
        calendar.timeZone = timeZone
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        guard let resolved = calendar.date(from: components) else {
            XCTFail("failed to construct date \(year)-\(month)-\(day)")
            return Date()
        }
        return resolved
    }

    func testTodayIsThisWeek() {
        let now = date(2026, 7, 6)
        XCTAssertEqual(EventWeekBucket.bucket(for: now, now: now, calendar: calendar), .thisWeek)
    }

    func testTomorrowIsThisWeek() {
        let now = date(2026, 7, 6)
        let tomorrow = date(2026, 7, 7)
        XCTAssertEqual(EventWeekBucket.bucket(for: tomorrow, now: now, calendar: calendar), .thisWeek)
    }

    func testSixDaysOutIsThisWeek() {
        let now = date(2026, 7, 6)
        let sixDaysOut = date(2026, 7, 12)
        XCTAssertEqual(EventWeekBucket.bucket(for: sixDaysOut, now: now, calendar: calendar), .thisWeek)
    }

    func testExactlySevenDaysOutIsComingUp() {
        let now = date(2026, 7, 6)
        let sevenDaysOut = date(2026, 7, 13)
        XCTAssertEqual(EventWeekBucket.bucket(for: sevenDaysOut, now: now, calendar: calendar), .comingUp)
    }

    func testFarFutureIsComingUp() {
        let now = date(2026, 7, 6)
        let farFuture = date(2026, 9, 1)
        XCTAssertEqual(EventWeekBucket.bucket(for: farFuture, now: now, calendar: calendar), .comingUp)
    }
}
