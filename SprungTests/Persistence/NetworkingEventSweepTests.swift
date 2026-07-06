//
//  NetworkingEventSweepTests.swift
//  SprungTests
//
//  Pins the `.missed` sweep contract: NetworkingEventStore's init runs
//  sweepMissedEvents(), the single writer of EventPipelineStatus.missed.
//  Only planned events whose date is more than one day past are swept —
//  a planned event was a commitment; discovered/attended/debriefed ones
//  are not the sweep's business. The sweep is idempotent: a second store
//  over the same context changes nothing.
//

import XCTest
import SwiftData
@testable import Sprung

@MainActor
final class NetworkingEventSweepTests: InMemoryStoreCase {

    private func makeEvent(
        name: String,
        status: EventPipelineStatus,
        daysFromNow: Int
    ) -> NetworkingEventOpportunity {
        let event = NetworkingEventOpportunity()
        event.name = name
        event.status = status
        event.date = Calendar.current.date(byAdding: .day, value: daysFromNow, to: Date()) ?? Date()
        return event
    }

    func testPlannedEventPastCutoffIsMarkedMissedOnInit() throws {
        insert(makeEvent(name: "Stale Meetup", status: .planned, daysFromNow: -3))
        saveContext()

        _ = NetworkingEventStore(context: context)

        let fetched = try XCTUnwrap(fetchAll(NetworkingEventOpportunity.self).first)
        XCTAssertEqual(fetched.status, .missed)
    }

    func testFutureAndRecentPlannedEventsAreUntouched() throws {
        insert(makeEvent(name: "Next Week", status: .planned, daysFromNow: 7))
        // Passed, but not by more than a day — the user may still mark it attended today.
        insert(makeEvent(name: "Last Night", status: .planned, daysFromNow: 0))
        saveContext()

        _ = NetworkingEventStore(context: context)

        for event in try fetchAll(NetworkingEventOpportunity.self) {
            XCTAssertEqual(event.status, .planned, "\(event.name) must not be swept")
        }
    }

    func testNonPlannedPastEventsAreUntouched() throws {
        insert(makeEvent(name: "Attended", status: .attended, daysFromNow: -5))
        insert(makeEvent(name: "Debriefed", status: .debriefed, daysFromNow: -5))
        insert(makeEvent(name: "Skipped", status: .skipped, daysFromNow: -5))
        insert(makeEvent(name: "Only Discovered", status: .discovered, daysFromNow: -5))
        saveContext()

        _ = NetworkingEventStore(context: context)

        let byName = Dictionary(
            uniqueKeysWithValues: try fetchAll(NetworkingEventOpportunity.self).map { ($0.name, $0.status) }
        )
        XCTAssertEqual(byName["Attended"], .attended)
        XCTAssertEqual(byName["Debriefed"], .debriefed)
        XCTAssertEqual(byName["Skipped"], .skipped)
        XCTAssertEqual(byName["Only Discovered"], .discovered,
                       "a discovered event was never a commitment — it just ages out")
    }

    func testSweepIsIdempotentAcrossRepeatedInits() throws {
        insert(makeEvent(name: "Stale Meetup", status: .planned, daysFromNow: -3))
        insert(makeEvent(name: "Next Week", status: .planned, daysFromNow: 7))
        saveContext()

        _ = NetworkingEventStore(context: context)
        _ = NetworkingEventStore(context: context)  // second launch: nothing left to sweep

        let byName = Dictionary(
            uniqueKeysWithValues: try fetchAll(NetworkingEventOpportunity.self).map { ($0.name, $0.status) }
        )
        XCTAssertEqual(byName["Stale Meetup"], .missed)
        XCTAssertEqual(byName["Next Week"], .planned)
    }
}
