//
//  EventPrepPersistenceTests.swift
//  SprungTests
//
//  Pins the NetworkingEventOpportunity event-prep field persistence contract: `goal`
//  and `pitchScript` are plain optional Strings, while talkingPoints, targetCompanies,
//  conversationStarters, and thingsToAvoid are JSON-string-backed typed accessors that
//  must survive a save/fetch cycle through a real ModelContext.
//

import XCTest
import SwiftData
@testable import Sprung

@MainActor
final class EventPrepPersistenceTests: InMemoryStoreCase {

    private func makeEvent(name: String = "Tech Mixer") -> NetworkingEventOpportunity {
        let event = NetworkingEventOpportunity()
        event.name = name
        return event
    }

    // MARK: - goal / pitchScript
    //
    // NOTE: unlike the four fields below, `goal` and `pitchScript` are declared as
    // plain `var goal: String?` / `var pitchScript: String?` on the model — there is
    // no JSON-backed typed accessor for these two. Documenting the real (simpler)
    // contract rather than a JSON round trip that doesn't exist for these fields.

    func testGoalAndPitchScriptPersistAsPlainStrings() throws {
        let event = makeEvent()
        event.goal = "Meet 3 hiring managers"
        event.pitchScript = "Hi, I'm Ada, a systems engineer..."
        insert(event)
        saveContext()

        let fetched = try XCTUnwrap(fetchAll(NetworkingEventOpportunity.self).first)
        XCTAssertEqual(fetched.goal, "Meet 3 hiring managers")
        XCTAssertEqual(fetched.pitchScript, "Hi, I'm Ada, a systems engineer...")
    }

    func testGoalAndPitchScriptNilByDefault() throws {
        let event = makeEvent()
        insert(event)
        saveContext()

        let fetched = try XCTUnwrap(fetchAll(NetworkingEventOpportunity.self).first)
        XCTAssertNil(fetched.goal)
        XCTAssertNil(fetched.pitchScript)
    }

    // MARK: - talkingPoints

    func testTalkingPointsRoundTripThroughContext() throws {
        let event = makeEvent()
        event.talkingPoints = [
            TalkingPoint(topic: "Growth", relevance: "They're scaling infra", yourAngle: "I led a similar migration")
        ]
        insert(event)
        saveContext()

        let fetched = try XCTUnwrap(fetchAll(NetworkingEventOpportunity.self).first)
        XCTAssertNotNil(fetched.talkingPointsJSON)
        XCTAssertEqual(fetched.talkingPoints?.first?.topic, "Growth")
        XCTAssertEqual(fetched.talkingPoints?.first?.yourAngle, "I led a similar migration")
    }

    func testTalkingPointsNilStateByDefault() throws {
        let event = makeEvent()
        insert(event)
        saveContext()

        let fetched = try XCTUnwrap(fetchAll(NetworkingEventOpportunity.self).first)
        XCTAssertNil(fetched.talkingPointsJSON)
        XCTAssertNil(fetched.talkingPoints)
    }

    // MARK: - targetCompanies

    func testTargetCompaniesRoundTripThroughContext() throws {
        let event = makeEvent()
        event.targetCompanies = [
            TargetCompanyContext(
                company: "Acme",
                whyRelevant: "Hiring platform engineers",
                recentNews: "Series C",
                openRoles: ["Staff Engineer"],
                possibleOpeners: ["Congrats on the raise"]
            )
        ]
        insert(event)
        saveContext()

        let fetched = try XCTUnwrap(fetchAll(NetworkingEventOpportunity.self).first)
        XCTAssertEqual(fetched.targetCompanies?.first?.company, "Acme")
        XCTAssertEqual(fetched.targetCompanies?.first?.openRoles, ["Staff Engineer"])
    }

    func testTargetCompaniesNilStateByDefault() throws {
        let event = makeEvent()
        insert(event)
        saveContext()

        let fetched = try XCTUnwrap(fetchAll(NetworkingEventOpportunity.self).first)
        XCTAssertNil(fetched.targetCompaniesJSON)
        XCTAssertNil(fetched.targetCompanies)
    }

    // MARK: - conversationStarters

    func testConversationStartersRoundTripThroughContext() throws {
        let event = makeEvent()
        event.conversationStarters = ["Ask about their new platform", "Mention the conference talk"]
        insert(event)
        saveContext()

        let fetched = try XCTUnwrap(fetchAll(NetworkingEventOpportunity.self).first)
        XCTAssertEqual(fetched.conversationStarters, ["Ask about their new platform", "Mention the conference talk"])
    }

    func testConversationStartersEmptyArrayDistinctFromNil() throws {
        let event = makeEvent()
        event.conversationStarters = []
        insert(event)
        saveContext()

        let fetched = try XCTUnwrap(fetchAll(NetworkingEventOpportunity.self).first)
        XCTAssertNotNil(fetched.conversationStartersJSON, "an explicitly-set empty array still encodes JSON, distinct from a never-set field")
        XCTAssertEqual(fetched.conversationStarters, [])
    }

    // MARK: - thingsToAvoid

    func testThingsToAvoidRoundTripThroughContext() throws {
        let event = makeEvent()
        event.thingsToAvoid = ["Don't pitch immediately", "Avoid salary talk"]
        insert(event)
        saveContext()

        let fetched = try XCTUnwrap(fetchAll(NetworkingEventOpportunity.self).first)
        XCTAssertEqual(fetched.thingsToAvoid, ["Don't pitch immediately", "Avoid salary talk"])
    }

    func testThingsToAvoidNilStateByDefault() throws {
        let event = makeEvent()
        insert(event)
        saveContext()

        let fetched = try XCTUnwrap(fetchAll(NetworkingEventOpportunity.self).first)
        XCTAssertNil(fetched.thingsToAvoidJSON)
        XCTAssertNil(fetched.thingsToAvoid)
    }
}
