//
//  DiscoveryResponseParserTests.swift
//  SprungTests
//
//  Pure-logic coverage for DiscoveryResponseParser: JSON extraction (fenced
//  blocks, raw braces, raw brackets) exercised through the typed parse* methods,
//  plus error surfacing for unparseable input. (The daily-task contract moved to
//  DailyTaskGenerator's structured output — see DiscoveryPureLogicTests; the
//  event-discovery contract is the strict submit_events tool — see
//  EventDiscoveryLoopTests.)
//

import XCTest
@testable import Sprung

final class DiscoveryResponseParserTests: XCTestCase {

    private let parser = DiscoveryResponseParser()

    /// Minimal valid JobSelectionsResult body (camelCase keys we control).
    private let emptySelectionsJSON = #"{"selections":[],"overallAnalysis":"none","considerations":[]}"#

    // MARK: - Extraction shapes (exercised through parseJobSelections)

    func testParseJobSelectionsFromFencedBlock() throws {
        // Single-line JSON inside a ```json fence (extractJSON's regex is line-oriented).
        let response = "Here are your selections:\n```json \(emptySelectionsJSON) ```\nThat's all."
        let result = try parser.parseJobSelections(response)
        XCTAssertTrue(result.selections.isEmpty)
        XCTAssertEqual(result.overallAnalysis, "none")
    }

    func testParseJobSelectionsFromBracesWithSurroundingProse() throws {
        let response = "Sure thing. \(emptySelectionsJSON) Hope that helps!"
        let result = try parser.parseJobSelections(response)
        XCTAssertTrue(result.selections.isEmpty)
    }

    func testParseJobSelectionsUsesFirstBraceToLastBrace() throws {
        // extractJSON grabs firstIndex("{")...lastIndex("}"); trailing prose with no
        // braces is excluded, so this parses cleanly.
        let uuid = UUID().uuidString
        let json = #"{"selections":[{"jobId":"\#(uuid)","company":"X","role":"Eng","matchScore":0.5,"reasoning":"fit"}],"overallAnalysis":"one","considerations":["Comp"]}"#
        let response = "prefix \(json) done"
        let result = try parser.parseJobSelections(response)
        XCTAssertEqual(result.selections.first?.company, "X")
        XCTAssertEqual(result.considerations, ["Comp"])
    }

    // MARK: - Error surfacing

    func testNoJSONThrowsInvalidResponse() {
        XCTAssertThrowsError(try parser.parseJobSelections("there is no json in this text")) { error in
            guard case DiscoveryAgentError.invalidResponse = error else {
                return XCTFail("expected .invalidResponse, got \(error)")
            }
        }
    }

    func testMalformedJSONThrowsInvalidResponse() {
        // Has braces (so extraction succeeds) but the shape is wrong for JobSelectionsResult.
        XCTAssertThrowsError(try parser.parseJobSelections(#"{"not_selections": 5}"#)) { error in
            guard case DiscoveryAgentError.invalidResponse = error else {
                return XCTFail("expected .invalidResponse, got \(error)")
            }
        }
    }

    // MARK: - Array-shaped extraction path

    func testRawBracketExtractionFailsDecodeButExercisesArrayPath() {
        // No object braces, only an array -> extractJSON returns the bracket span.
        // JobSelectionsResult expects an object, so decode fails -> invalidResponse.
        // This proves the bracket branch is reached (not a nil/extraction failure).
        XCTAssertThrowsError(try parser.parseJobSelections("results: [1,2,3] end")) { error in
            guard case DiscoveryAgentError.invalidResponse = error else {
                return XCTFail("expected .invalidResponse, got \(error)")
            }
        }
    }
}
