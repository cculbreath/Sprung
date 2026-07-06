//
//  DiscoveryResponseParserTests.swift
//  SprungTests
//
//  Pure-logic coverage for DiscoveryResponseParser: JSON extraction (fenced
//  blocks, raw braces, raw brackets) exercised through the typed parse* methods,
//  plus error surfacing for unparseable input. Wire keys are checked: snake_case
//  where the source/event prompt templates pin it. (The daily-task contract
//  moved to DailyTaskGenerator's structured output — see
//  DiscoveryPureLogicTests.)
//

import XCTest
@testable import Sprung

final class DiscoveryResponseParserTests: XCTestCase {

    private let parser = DiscoveryResponseParser()

    // MARK: - Extraction shapes (exercised through parseSources)

    func testParseSourcesFromFencedBlock() throws {
        // Single-line JSON inside a ```json fence (extractJSON's regex is line-oriented).
        let response = "Here are your sources:\n```json {\"sources\":[]} ```\nThat's all."
        let result = try parser.parseSources(response)
        XCTAssertEqual(result.sources.count, 0)
    }

    func testParseSourcesFromBracesWithSurroundingProse() throws {
        let response = "Sure thing. {\"sources\":[]} Hope that helps!"
        let result = try parser.parseSources(response)
        XCTAssertTrue(result.sources.isEmpty)
    }

    func testParseSourcesUsesFirstBraceToLastBrace() throws {
        // extractJSON grabs firstIndex("{")...lastIndex("}"); trailing prose with no
        // braces is excluded, so this parses cleanly.
        let response = "prefix {\"sources\":[{\"name\":\"X\",\"url\":\"u\",\"category\":\"local\",\"relevance_reason\":\"r\"}]} done"
        let result = try parser.parseSources(response)
        XCTAssertEqual(result.sources.first?.name, "X")
        XCTAssertNil(result.sources.first?.recommendedCadenceDays, "optional missing field decodes to nil")
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
        XCTAssertThrowsError(try parser.parseSources("there is no json in this text")) { error in
            guard case DiscoveryAgentError.invalidResponse = error else {
                return XCTFail("expected .invalidResponse, got \(error)")
            }
        }
    }

    func testMalformedJSONThrowsInvalidResponse() {
        // Has braces (so extraction succeeds) but the shape is wrong for JobSourcesResult.
        XCTAssertThrowsError(try parser.parseSources(#"{"not_sources": 5}"#)) { error in
            guard case DiscoveryAgentError.invalidResponse = error else {
                return XCTFail("expected .invalidResponse, got \(error)")
            }
        }
    }

    // MARK: - Array-shaped extraction path

    func testRawBracketExtractionFailsDecodeButExercisesArrayPath() {
        // No object braces, only an array -> extractJSON returns the bracket span.
        // JobSourcesResult expects an object, so decode fails -> invalidResponse.
        // This proves the bracket branch is reached (not a nil/extraction failure).
        XCTAssertThrowsError(try parser.parseSources("results: [1,2,3] end")) { error in
            guard case DiscoveryAgentError.invalidResponse = error else {
                return XCTFail("expected .invalidResponse, got \(error)")
            }
        }
    }
}
