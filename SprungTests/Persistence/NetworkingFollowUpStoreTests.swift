//
//  NetworkingFollowUpStoreTests.swift
//  SprungTests
//
//  Pins the follow-up commitment loop on NetworkingInteractionStore:
//  recordFollowUp (the single writer — debrief per-contact toggle and
//  accepted AI actions) sets followUpNeeded so the row surfaces in
//  pendingFollowUps/overdueFollowUps, and completeNearestPendingFollowUp
//  (called when a Follow Up daily task completes) clears the contact's
//  earliest-due pending commitment.
//

import XCTest
import SwiftData
@testable import Sprung

@MainActor
final class NetworkingFollowUpStoreTests: InMemoryStoreCase {

    private var store: NetworkingInteractionStore!

    override func setUp() async throws {
        try await super.setUp()
        store = NetworkingInteractionStore(context: context)
    }

    override func tearDown() async throws {
        store = nil
        try await super.tearDown()
    }

    private func date(daysFromNow days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()
    }

    // MARK: - recordFollowUp

    func testRecordFollowUpSetsNeededFlagAndFields() {
        let contactId = UUID()
        let eventId = UUID()
        let due = date(daysFromNow: 2)

        let interaction = store.recordFollowUp(
            contactId: contactId,
            action: "Send thank-you note",
            dueDate: due,
            eventId: eventId
        )

        XCTAssertTrue(interaction.followUpNeeded, "the writer must set the flag the queries filter on")
        XCTAssertFalse(interaction.followUpCompleted)
        XCTAssertEqual(interaction.followUpAction, "Send thank-you note")
        XCTAssertEqual(interaction.followUpDate, due)
        XCTAssertEqual(interaction.eventId, eventId)
        XCTAssertEqual(store.pendingFollowUps.map(\.id), [interaction.id])
    }

    func testOverdueFollowUpsContainOnlyPastDueDates() {
        let contactId = UUID()
        store.recordFollowUp(contactId: contactId, action: "Overdue", dueDate: date(daysFromNow: -1))
        store.recordFollowUp(contactId: contactId, action: "Upcoming", dueDate: date(daysFromNow: 3))

        XCTAssertEqual(store.pendingFollowUps.count, 2)
        XCTAssertEqual(store.overdueFollowUps.map(\.followUpAction), ["Overdue"])
    }

    // MARK: - completeNearestPendingFollowUp

    func testCompleteNearestPicksEarliestDueForTheContact() {
        let contactId = UUID()
        let otherContactId = UUID()
        store.recordFollowUp(contactId: contactId, action: "Later", dueDate: date(daysFromNow: 5))
        store.recordFollowUp(contactId: contactId, action: "Sooner", dueDate: date(daysFromNow: 1))
        store.recordFollowUp(contactId: otherContactId, action: "Someone else", dueDate: date(daysFromNow: 0))

        let cleared = store.completeNearestPendingFollowUp(forContactId: contactId)

        XCTAssertEqual(cleared?.followUpAction, "Sooner")
        XCTAssertEqual(cleared?.followUpCompleted, true)
        XCTAssertEqual(store.pendingFollowUps.filter { $0.contactId == contactId }.map(\.followUpAction),
                       ["Later"])
        XCTAssertEqual(store.pendingFollowUps.filter { $0.contactId == otherContactId }.count, 1,
                       "another contact's follow-up is untouched")
    }

    func testCompleteNearestClearsRemainingOnSecondCallAndThenNoOps() {
        let contactId = UUID()
        store.recordFollowUp(contactId: contactId, action: "First", dueDate: date(daysFromNow: 1))
        store.recordFollowUp(contactId: contactId, action: "Second", dueDate: date(daysFromNow: 2))

        XCTAssertEqual(store.completeNearestPendingFollowUp(forContactId: contactId)?.followUpAction, "First")
        XCTAssertEqual(store.completeNearestPendingFollowUp(forContactId: contactId)?.followUpAction, "Second")
        XCTAssertNil(store.completeNearestPendingFollowUp(forContactId: contactId),
                     "no pending follow-ups left — returns nil rather than re-marking")
    }

    func testCompleteNearestReturnsNilForUnknownContact() {
        XCTAssertNil(store.completeNearestPendingFollowUp(forContactId: UUID()))
    }
}
