//
//  JobScoutUIHelpersTests.swift
//  SprungTests
//
//  Pure-half coverage for the Job Scout run modal's keyword field parsing
//  (ScoutKeywordsParser): comma/newline splitting, trimming, empty-piece
//  dropping, case-insensitive dedup, and the join round-trip.
//

import XCTest
@testable import Sprung

final class JobScoutUIHelpersTests: XCTestCase {
    // MARK: - parse

    func testParseSplitsOnCommas() {
        XCTAssertEqual(
            ScoutKeywordsParser.parse("iOS Developer, Optical Engineer, Data Scientist"),
            ["iOS Developer", "Optical Engineer", "Data Scientist"]
        )
    }

    func testParseSplitsOnNewlines() {
        XCTAssertEqual(
            ScoutKeywordsParser.parse("iOS Developer\nOptical Engineer\nData Scientist"),
            ["iOS Developer", "Optical Engineer", "Data Scientist"]
        )
    }

    func testParseTrimsWhitespaceAroundKeywords() {
        XCTAssertEqual(
            ScoutKeywordsParser.parse("  iOS Developer ,\tOptical Engineer  "),
            ["iOS Developer", "Optical Engineer"]
        )
    }

    func testParseDropsEmptyPieces() {
        XCTAssertEqual(
            ScoutKeywordsParser.parse("iOS,, ,Optics,"),
            ["iOS", "Optics"]
        )
    }

    func testParseDedupesCaseInsensitivelyKeepingFirstSpelling() {
        XCTAssertEqual(
            ScoutKeywordsParser.parse("Swift, swift, SWIFT, Optics"),
            ["Swift", "Optics"]
        )
    }

    func testParsePreservesInternalSpaces() {
        XCTAssertEqual(
            ScoutKeywordsParser.parse("staff  software engineer"),
            ["staff  software engineer"]
        )
    }

    func testParseEmptyAndWhitespaceOnlyTextGivesEmptyArray() {
        XCTAssertEqual(ScoutKeywordsParser.parse(""), [])
        XCTAssertEqual(ScoutKeywordsParser.parse("   ,\n , "), [])
    }

    // MARK: - join

    func testJoinRendersCommaSeparatedText() {
        XCTAssertEqual(
            ScoutKeywordsParser.join(["iOS Developer", "Optics"]),
            "iOS Developer, Optics"
        )
    }

    func testJoinEmptyListGivesEmptyString() {
        XCTAssertEqual(ScoutKeywordsParser.join([]), "")
    }

    func testJoinThenParseRoundTrips() {
        let keywords = ["iOS Developer", "Optical Engineer", "Data Scientist"]
        XCTAssertEqual(
            ScoutKeywordsParser.parse(ScoutKeywordsParser.join(keywords)),
            keywords
        )
    }
}
