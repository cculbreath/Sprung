//
//  SeedGenSkillGroupEditTests.swift
//  SprungTests
//
//  Pins the SGM review-sheet skill-group edit round-trip:
//  SkillGroup.editableText(for:) → user edits → SkillGroup.parse(editableText:)
//  must reproduce the groups exactly, so what the user saves is what gets
//  applied. Regression guard for the trap where Edit on a skill-groups card
//  opened an empty editor and approving silently applied the ORIGINAL grouping.
//
//  Format contract: one group per line, "Category Name: skill1, skill2".
//  Only the FIRST colon splits name from keywords; keywords are comma-split
//  (a keyword itself must not contain a comma); whitespace is trimmed.
//

import XCTest
@testable import Sprung

final class SeedGenSkillGroupEditTests: XCTestCase {

    // MARK: - Round trip

    func testRoundTripPreservesGroups() {
        let groups = [
            SkillGroup(name: "Data Engineering", keywords: ["Python", "SQL", "Airflow"]),
            SkillGroup(name: "Leadership", keywords: ["Mentoring", "Hiring"]),
            SkillGroup(name: "Tools", keywords: ["Git"])
        ]
        let text = SkillGroup.editableText(for: groups)
        XCTAssertEqual(SkillGroup.parse(editableText: text), groups,
                       "editableText → parse must be lossless")
    }

    func testEditableTextFormat() {
        let text = SkillGroup.editableText(for: [
            SkillGroup(name: "Tools", keywords: ["Git", "Docker"])
        ])
        XCTAssertEqual(text, "Tools: Git, Docker")
    }

    // MARK: - Parse leniency

    func testParseTrimsWhitespaceAndSkipsBlankLines() {
        let parsed = SkillGroup.parse(editableText: "\n  Tools :  Git ,  Docker \n\n")
        XCTAssertEqual(parsed, [SkillGroup(name: "Tools", keywords: ["Git", "Docker"])])
    }

    func testParseLineWithoutColonBecomesNameOnlyGroup() {
        XCTAssertEqual(SkillGroup.parse(editableText: "Communication"),
                       [SkillGroup(name: "Communication", keywords: [])])
    }

    func testParseDropsEmptyKeywords() {
        XCTAssertEqual(SkillGroup.parse(editableText: "Tools: Git,, ,Docker"),
                       [SkillGroup(name: "Tools", keywords: ["Git", "Docker"])])
    }

    func testParseOnlyFirstColonSplitsNameFromKeywords() {
        XCTAssertEqual(SkillGroup.parse(editableText: "Ratios: A:B testing"),
                       [SkillGroup(name: "Ratios", keywords: ["A:B testing"])])
    }

    func testParseEmptyTextYieldsNoGroups() {
        XCTAssertEqual(SkillGroup.parse(editableText: "   \n \n"), [])
    }

    func testParseDropsColonOnlyLine() {
        XCTAssertEqual(SkillGroup.parse(editableText: " : "), [],
                       "a line with neither name nor keywords is noise, not a group")
    }
}
