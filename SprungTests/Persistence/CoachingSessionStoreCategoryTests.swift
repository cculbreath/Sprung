//
//  CoachingSessionStoreCategoryTests.swift
//  SprungTests
//
//  Pins the `askedCategoriesJSON` typed-accessor contract on `CoachingSession` plus
//  `CoachingSessionStore.recentAskedCategoriesSummary()`'s repetition-avoidance window,
//  and documents the pre-redesign `questionsJSON` graceful-degradation contract.
//

import XCTest
import SwiftData
@testable import Sprung

@MainActor
final class CoachingSessionStoreCategoryTests: InMemoryStoreCase {

    // MARK: - Helpers

    private func makeCompletedSession(daysAgo: Int, categories: [String]) -> CoachingSession {
        let session = CoachingSession()
        session.sessionDate = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        session.recommendations = "Some advice"
        session.completedAt = Date()
        session.askedCategories = categories
        return session
    }

    // MARK: - askedCategoriesJSON typed accessor

    func testAskedCategoriesRoundTripsThroughTypedAccessorAndContext() throws {
        let session = CoachingSession()
        session.askedCategories = ["motivation", "interview_prep"]
        insert(session)
        saveContext()

        let fetched = try XCTUnwrap(fetchAll(CoachingSession.self).first)
        XCTAssertEqual(fetched.askedCategories, ["motivation", "interview_prep"])

        // Wire format is a plain JSON string array, not nested under a key.
        let rawJSON = try XCTUnwrap(fetched.askedCategoriesJSON)
        let decoded = try JSONDecoder().decode([String].self, from: Data(rawJSON.utf8))
        XCTAssertEqual(decoded, ["motivation", "interview_prep"])
    }

    func testAskedCategoriesEmptyWhenNeverSet() throws {
        let session = CoachingSession()
        insert(session)
        saveContext()

        let fetched = try XCTUnwrap(fetchAll(CoachingSession.self).first)
        XCTAssertNil(fetched.askedCategoriesJSON)
        XCTAssertEqual(fetched.askedCategories, [])
    }

    // MARK: - recentAskedCategoriesSummary()

    func testRecentAskedCategoriesSummaryReflectsLastTwoSessions() {
        let store = CoachingSessionStore(context: context)
        store.add(makeCompletedSession(daysAgo: 10, categories: ["skill_gap"]))
        store.add(makeCompletedSession(daysAgo: 5, categories: ["motivation"]))
        store.add(makeCompletedSession(daysAgo: 1, categories: ["interview_prep"]))

        let summary = store.recentAskedCategoriesSummary()

        XCTAssertTrue(summary.contains("interview_prep"))
        XCTAssertTrue(summary.contains("motivation"))
        XCTAssertFalse(summary.contains("skill_gap"), "recentAskedCategoriesSummary defaults to the last two sessions only")
    }

    func testRecentAskedCategoriesSummarySkipsEmptySessionWithinWindowWithoutBackfilling() {
        let store = CoachingSessionStore(context: context)
        store.add(makeCompletedSession(daysAgo: 10, categories: ["skill_gap"]))  // outside the 2-session window
        store.add(makeCompletedSession(daysAgo: 5, categories: ["motivation"]))   // in window
        store.add(makeCompletedSession(daysAgo: 1, categories: []))              // in window, no categories

        let summary = store.recentAskedCategoriesSummary()

        // Real contract (see CoachingSessionStore.recentAskedCategoriesSummary): the
        // window is fixed to the most recent `sessionCount` completed sessions BEFORE
        // filtering out empty-category rows. An older session outside that window is
        // never used to "backfill" a slot the window itself produced no line for.
        XCTAssertTrue(summary.contains("motivation"))
        XCTAssertFalse(summary.contains("skill_gap"))
    }

    func testRecentAskedCategoriesSummaryNoneWhenWindowSessionsLackCategories() {
        let store = CoachingSessionStore(context: context)
        store.add(makeCompletedSession(daysAgo: 10, categories: ["skill_gap"]))
        store.add(makeCompletedSession(daysAgo: 5, categories: []))
        store.add(makeCompletedSession(daysAgo: 1, categories: []))

        XCTAssertEqual(store.recentAskedCategoriesSummary(), "None — no questions asked in recent sessions.")
    }

    func testRecentAskedCategoriesSummaryNoSessionsAtAll() {
        let store = CoachingSessionStore(context: context)
        XCTAssertEqual(store.recentAskedCategoriesSummary(), "None — no questions asked in recent sessions.")
    }

    // MARK: - Pre-redesign questionsJSON graceful degradation

    /// Documents accepted data loss from the 2026-07-06 redesign: `CoachingQuestion`
    /// now requires a `category` field where the older shape used `questionType`. A
    /// session row persisted under that pre-redesign shape fails Codable decode
    /// (missing the now-required `category` key); `CoachingSession.questions`'s
    /// `try?` swallows that failure and returns `[]` rather than throwing or
    /// crashing the app. Pinning this as the real (if lossy) contract.
    func testOldFormatQuestionsJSONDecodesToEmptyArrayNotThrow() {
        let session = CoachingSession()
        session.questionsJSON = """
        [{"id":"11111111-1111-1111-1111-111111111111","questionText":"What's blocking you?","options":[{"id":"22222222-2222-2222-2222-222222222222","value":1,"label":"Time","emoji":null,"actionId":null}],"questionType":"motivation"}]
        """

        XCTAssertEqual(session.questions, [], "pre-redesign questionType-keyed rows silently decode to empty, not a thrown error")
    }
}
