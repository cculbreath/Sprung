//
//  ReflectionNotesTests.swift
//  SprungTests
//
//  Round-trip contract for the Weekly Review reflection fields
//  (ReflectionNotes in WeeklyReviewView.swift): `composed` is the labeled
//  prose stored in WeeklyGoal.userNotes, `init(parsing:)` reads it back into
//  the four fields, and an all-blank compose returns nil — the guard that
//  keeps an accidental empty save from wiping previously saved notes.
//

import XCTest
@testable import Sprung

final class ReflectionNotesTests: XCTestCase {

    // MARK: - Blank-Save Guard

    func testComposedIsNilWhenAllFieldsBlank() {
        XCTAssertNil(ReflectionNotes().composed)
        XCTAssertNil(
            ReflectionNotes(wins: "  ", challenges: "\n", learnings: "\t", nextWeekFocus: " ").composed
        )
    }

    func testComposedIsNonNilWhenAnySingleFieldHasContent() {
        XCTAssertNotNil(ReflectionNotes(wins: "shipped").composed)
        XCTAssertNotNil(ReflectionNotes(nextWeekFocus: "follow ups").composed)
    }

    func testParsingLegacyBlankTemplateComposesBackToNil() {
        // The pre-guard save path wrote the empty template verbatim. Parsing
        // it yields four empty fields, and re-composing yields nil — so a
        // legacy blank record never propagates another blank save.
        let legacyBlank = "Wins: \nChallenges: \nLearnings: \nNext Week: "
        let notes = ReflectionNotes(parsing: legacyBlank)
        XCTAssertEqual(notes, ReflectionNotes())
        XCTAssertNil(notes.composed)
    }

    // MARK: - Round Trip

    func testComposeParseRoundTrip() throws {
        let original = ReflectionNotes(
            wins: "Two interviews scheduled",
            challenges: "Cover letters took too long",
            learnings: "Batch the research step",
            nextWeekFocus: "Follow up with Sarah"
        )
        let composed = try XCTUnwrap(original.composed)
        XCTAssertEqual(ReflectionNotes(parsing: composed), original)
    }

    func testComposedUsesLabeledLineFormat() throws {
        let composed = try XCTUnwrap(
            ReflectionNotes(wins: "a", challenges: "b", learnings: "c", nextWeekFocus: "d").composed
        )
        XCTAssertEqual(composed, "Wins: a\nChallenges: b\nLearnings: c\nNext Week: d")
    }

    func testParsingPreservesMultiLineFieldValues() {
        // Lines that don't start a labeled field continue the current one.
        let text = "Wins: first win\nsecond win\nChallenges: tricky week\nLearnings: \nNext Week: rest"
        let notes = ReflectionNotes(parsing: text)
        XCTAssertEqual(notes.wins, "first win\nsecond win")
        XCTAssertEqual(notes.challenges, "tricky week")
        XCTAssertEqual(notes.learnings, "")
        XCTAssertEqual(notes.nextWeekFocus, "rest")
    }

    func testFieldValuesAreTrimmedOnCompose() throws {
        let composed = try XCTUnwrap(
            ReflectionNotes(wins: "  padded  ", challenges: "", learnings: "", nextWeekFocus: "").composed
        )
        XCTAssertEqual(
            composed,
            "Wins: padded\nChallenges: \nLearnings: \nNext Week: "
        )
    }

    // MARK: - Known Quirk (documented contract)

    func testContinuationLineStartingWithALabelIsClaimedByThatLabel() {
        // Accepted ambiguity of the labeled-prose format: the labels double
        // as parse delimiters, so a continuation line the user typed inside
        // one field that happens to begin with another field's label is
        // claimed by that label on parse (a later occurrence of the same
        // label replaces the earlier value).
        let text = "Wins: shipped it\nNext Week: (typed inside the wins box)\nChallenges: none\nLearnings: \nNext Week: the real focus"
        let notes = ReflectionNotes(parsing: text)
        XCTAssertEqual(notes.wins, "shipped it")
        XCTAssertEqual(notes.challenges, "none")
        XCTAssertEqual(notes.learnings, "")
        XCTAssertEqual(notes.nextWeekFocus, "the real focus")
    }
}
