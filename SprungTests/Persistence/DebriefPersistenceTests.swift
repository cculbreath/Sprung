//
//  DebriefPersistenceTests.swift
//  SprungTests
//
//  Pins the debrief persistence contract on NetworkingEventOpportunity:
//  everything the debrief sheet captures lands in a column — wouldRecommend,
//  keyInsights, and the free-text followUpActions are plain optionals, and
//  the AI-generated DebriefOutcomesResult round-trips through the
//  debriefOutcomesJSON-backed typed accessor (camelCase JSON we control).
//

import XCTest
import SwiftData
@testable import Sprung

@MainActor
final class DebriefPersistenceTests: InMemoryStoreCase {

    private func makeDebriefedEvent() -> NetworkingEventOpportunity {
        let event = NetworkingEventOpportunity()
        event.name = "Tech Mixer"
        event.status = .debriefed
        return event
    }

    func testCapturedDebriefFieldsPersistAsPlainColumns() throws {
        let event = makeDebriefedEvent()
        event.eventNotes = "Crowded but worth it"
        event.eventRating = .good
        event.wouldRecommend = false
        event.keyInsights = "Two teams hiring for infra"
        event.followUpActions = "Email Dana; connect with the organizer"
        insert(event)
        saveContext()

        let fetched = try XCTUnwrap(fetchAll(NetworkingEventOpportunity.self).first)
        XCTAssertEqual(fetched.eventNotes, "Crowded but worth it")
        XCTAssertEqual(fetched.eventRating, .good)
        XCTAssertEqual(fetched.wouldRecommend, false)
        XCTAssertEqual(fetched.keyInsights, "Two teams hiring for infra")
        XCTAssertEqual(fetched.followUpActions, "Email Dana; connect with the organizer")
    }

    func testDebriefFieldsNilByDefault() throws {
        insert(makeDebriefedEvent())
        saveContext()

        let fetched = try XCTUnwrap(fetchAll(NetworkingEventOpportunity.self).first)
        XCTAssertNil(fetched.wouldRecommend)
        XCTAssertNil(fetched.keyInsights)
        XCTAssertNil(fetched.followUpActions)
        XCTAssertNil(fetched.debriefOutcomes)
    }

    func testDebriefOutcomesRoundTripThroughContext() throws {
        let event = makeDebriefedEvent()
        event.debriefOutcomes = DebriefOutcomesResult(
            summary: "Met two hiring managers.",
            keyTakeaways: ["Infra teams are growing"],
            followUpActions: [
                DebriefFollowUpAction(contactName: "Dana", action: "Email resume",
                                      deadline: "within 24 hours", priority: "high")
            ],
            opportunitiesIdentified: ["Referral at Hooli"],
            nextSteps: ["Send thank-you notes"]
        )
        insert(event)
        saveContext()

        let fetched = try XCTUnwrap(fetchAll(NetworkingEventOpportunity.self).first)
        let outcomes = try XCTUnwrap(fetched.debriefOutcomes)
        XCTAssertEqual(outcomes.summary, "Met two hiring managers.")
        XCTAssertEqual(outcomes.keyTakeaways, ["Infra teams are growing"])
        XCTAssertEqual(outcomes.followUpActions.count, 1)
        XCTAssertEqual(outcomes.followUpActions[0].contactName, "Dana")
        XCTAssertEqual(outcomes.opportunitiesIdentified, ["Referral at Hooli"])
        XCTAssertEqual(outcomes.nextSteps, ["Send thank-you notes"])

        let json = try XCTUnwrap(fetched.debriefOutcomesJSON)
        XCTAssertTrue(json.contains("\"keyTakeaways\""),
                      "persisted blob uses the camelCase keys we control")
        XCTAssertTrue(json.contains("\"contactName\""))
    }
}
