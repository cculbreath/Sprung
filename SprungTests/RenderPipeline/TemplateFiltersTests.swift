//
//  TemplateFiltersTests.swift
//  SprungTests
//
//  Phase 2 — text-resume Mustache filter formatting.
//
//  NOTE: The individual filters in TemplateFilters.swift are `private static let`
//  closures registered onto a Mustache.Template via `register(on:)`; they are NOT
//  individually callable from tests, and constructing/evaluating a Mustache.Template
//  here would be a brittle integration test. Instead we pin the PURE formatting
//  primitives those filters delegate to — TextFormatHelpers, HTMLUtility.stripTags,
//  and String.decodingHTMLEntities() — which carry the actual formatting logic.
//

import XCTest
@testable import Sprung

final class TemplateFiltersTests: XCTestCase {

    // MARK: - decodingHTMLEntities (used by nearly every filter)

    func testDecodingNamedEntities() {
        XCTAssertEqual("a &amp; b".decodingHTMLEntities(), "a & b")
        XCTAssertEqual("&lt;tag&gt;".decodingHTMLEntities(), "<tag>")
        XCTAssertEqual("she said &quot;hi&quot;".decodingHTMLEntities(), "she said \"hi\"")
        XCTAssertEqual("it&#39;s".decodingHTMLEntities(), "it's")
        XCTAssertEqual("a&nbsp;b".decodingHTMLEntities(), "a b")
    }

    func testDecodingDoesNotDoubleDecodeAmp() {
        // &amp;lt; should become &lt; (amp decoded last), not <.
        XCTAssertEqual("&amp;lt;".decodingHTMLEntities(), "&lt;")
    }

    // MARK: - HTMLUtility.stripTags (htmlStrip filter)

    func testStripTagsRemovesMarkup() {
        let stripped = HTMLUtility.stripTags("<p>Hello <b>world</b></p>")
        XCTAssertEqual(stripped.trimmingCharacters(in: .whitespacesAndNewlines), "Hello world")
    }

    // MARK: - TextFormatHelpers.joiner (join / joinBullet filters)

    func testJoinerJoinsWithSeparator() {
        XCTAssertEqual(TextFormatHelpers.joiner(["a", "b", "c"], separator: " · "), "a · b · c")
    }

    func testJoinerSingleElement() {
        XCTAssertEqual(TextFormatHelpers.joiner(["solo"], separator: " · "), "solo")
    }

    func testJoinerEmpty() {
        XCTAssertEqual(TextFormatHelpers.joiner([], separator: " · "), "")
    }

    // MARK: - TextFormatHelpers.sectionLine (sectionLine filter)

    func testSectionLineUppercasesAndCenters() {
        // width 20, title "Work" (4) ⇒ 12 dashes split 6/6.
        XCTAssertEqual(TextFormatHelpers.sectionLine("Work", width: 20), "*------ WORK ------*")
    }

    func testSectionLineStripsTags() {
        let line = TextFormatHelpers.sectionLine("<b>Work</b>", width: 20)
        XCTAssertTrue(line.contains("WORK"))
        XCTAssertFalse(line.contains("<b>"), "tags must be stripped before formatting")
    }

    // MARK: - TextFormatHelpers.bulletText (bulletList filter)

    func testBulletTextFirstLinePrefix() {
        let out = TextFormatHelpers.bulletText("Hi", marginLeft: 2, width: 80, bullet: "•")
        XCTAssertEqual(out, "  • Hi")
    }

    func testBulletTextWrapsContinuationLines() {
        // Force a wrap with a small width so a second line appears, indented under the text.
        let out = TextFormatHelpers.bulletText("one two three four", marginLeft: 0, width: 8, bullet: "*")
        let lines = out.components(separatedBy: "\n")
        XCTAssertGreaterThan(lines.count, 1, "long text must wrap")
        XCTAssertTrue(lines[0].hasPrefix("* "), "first line carries the bullet")
        // bulletSpace = bullet.count + 1 = 2; continuation lines are indented by marginLeft + bulletSpace = 2.
        XCTAssertTrue(lines[1].hasPrefix("  "), "continuation lines align under the text")
    }

    // MARK: - TextFormatHelpers.wrapper (center / wrap filters)

    func testWrapperCenteredPadsSymmetrically() {
        let out = TextFormatHelpers.wrapper("Hi", width: 6, centered: true)
        // "Hi" len 2, totalPadding 4, left 2 right 2 ⇒ "  Hi  "
        XCTAssertEqual(out, "  Hi  ")
    }

    func testWrapperLeftMarginIndents() {
        let out = TextFormatHelpers.wrapper("Hi", width: 80, leftMargin: 3)
        XCTAssertEqual(out, "   Hi")
    }
}
