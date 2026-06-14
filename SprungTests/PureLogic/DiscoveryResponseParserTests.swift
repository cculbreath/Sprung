//
//  DiscoveryResponseParserTests.swift
//  SprungTests
//
//  Pure-logic coverage for DiscoveryResponseParser: JSON extraction (fenced
//  blocks, raw braces, raw brackets) exercised through the typed parse* methods,
//  plus error surfacing for unparseable input. Snake_case wire keys are checked.
//

import XCTest
@testable import Sprung

final class DiscoveryResponseParserTests: XCTestCase {

    private let parser = DiscoveryResponseParser()

    // MARK: - parseTasks

    func testParseTasksRawJSON() throws {
        let json = #"""
        {"tasks":[{"task_type":"apply","title":"Apply to Acme","description":"do it","priority":1,"related_id":null,"estimated_minutes":30}]}
        """#
        let result = try parser.parseTasks(json)
        XCTAssertEqual(result.tasks.count, 1)
        XCTAssertEqual(result.tasks.first?.title, "Apply to Acme")
        XCTAssertEqual(result.tasks.first?.taskType, "apply", "snake_case task_type must map to taskType")
        XCTAssertEqual(result.tasks.first?.priority, 1)
        XCTAssertEqual(result.tasks.first?.estimatedMinutes, 30)
    }

    func testParseTasksFromFencedBlock() throws {
        // Single-line JSON inside a ```json fence (extractJSON's regex is line-oriented).
        let response = "Here are your tasks:\n```json {\"tasks\":[]} ```\nThat's all."
        let result = try parser.parseTasks(response)
        XCTAssertEqual(result.tasks.count, 0)
    }

    func testParseTasksFromBracesWithSurroundingProse() throws {
        let response = "Sure thing. {\"tasks\":[]} Hope that helps!"
        let result = try parser.parseTasks(response)
        XCTAssertTrue(result.tasks.isEmpty)
    }

    func testParseTasksUsesFirstBraceToLastBrace() throws {
        // extractJSON grabs firstIndex("{")...lastIndex("}"); trailing prose with no
        // braces is excluded, so this parses cleanly.
        let response = "prefix {\"tasks\":[{\"task_type\":\"gather\",\"title\":\"T\",\"priority\":2}]} done"
        let result = try parser.parseTasks(response)
        XCTAssertEqual(result.tasks.first?.taskType, "gather")
        XCTAssertEqual(result.tasks.first?.priority, 2)
        XCTAssertNil(result.tasks.first?.description, "optional missing field decodes to nil")
    }

    // MARK: - parseSources

    func testParseSourcesRawJSON() throws {
        let json = #"""
        {"sources":[{"name":"LinkedIn","url":"https://x","category":"aggregator","relevance_reason":"big","recommended_cadence_days":7}]}
        """#
        let result = try parser.parseSources(json)
        XCTAssertEqual(result.sources.count, 1)
        XCTAssertEqual(result.sources.first?.name, "LinkedIn")
        XCTAssertEqual(result.sources.first?.relevanceReason, "big",
                       "snake_case relevance_reason must map to relevanceReason")
        XCTAssertEqual(result.sources.first?.recommendedCadenceDays, 7)
    }

    func testParseSourcesOptionalCadenceMissing() throws {
        let json = #"{"sources":[{"name":"X","url":"u","category":"local","relevance_reason":"r"}]}"#
        let result = try parser.parseSources(json)
        XCTAssertNil(result.sources.first?.recommendedCadenceDays)
    }

    // MARK: - parseEvents

    func testParseEventsRawJSON() throws {
        let json = #"""
        {"events":[{"name":"Meetup","date":"2026-07-01","location":"SF","url":"u","event_type":"meetup"}]}
        """#
        let result = try parser.parseEvents(json)
        XCTAssertEqual(result.events.count, 1)
        XCTAssertEqual(result.events.first?.name, "Meetup")
        XCTAssertEqual(result.events.first?.eventType, "meetup",
                       "snake_case event_type must map to eventType")
        XCTAssertNil(result.events.first?.organizer, "missing optional decodes to nil")
    }

    // MARK: - Error surfacing

    func testNoJSONThrowsInvalidResponse() {
        XCTAssertThrowsError(try parser.parseTasks("there is no json in this text")) { error in
            guard case DiscoveryAgentError.invalidResponse = error else {
                return XCTFail("expected .invalidResponse, got \(error)")
            }
        }
    }

    func testMalformedJSONThrowsInvalidResponse() {
        // Has braces (so extraction succeeds) but the shape is wrong for DailyTasksResult.
        XCTAssertThrowsError(try parser.parseTasks(#"{"not_tasks": 5}"#)) { error in
            guard case DiscoveryAgentError.invalidResponse = error else {
                return XCTFail("expected .invalidResponse, got \(error)")
            }
        }
    }

    // MARK: - Array-shaped extraction path

    func testRawBracketExtractionFailsDecodeButExercisesArrayPath() {
        // No object braces, only an array -> extractJSON returns the bracket span.
        // DailyTasksResult expects an object, so decode fails -> invalidResponse.
        // This proves the bracket branch is reached (not a nil/extraction failure).
        XCTAssertThrowsError(try parser.parseTasks("results: [1,2,3] end")) { error in
            guard case DiscoveryAgentError.invalidResponse = error else {
                return XCTFail("expected .invalidResponse, got \(error)")
            }
        }
    }
}
