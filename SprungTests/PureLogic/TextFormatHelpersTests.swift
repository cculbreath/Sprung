//
//  TextFormatHelpersTests.swift
//  SprungTests
//
//  Pure-logic coverage for TextFormatHelpers: word wrapping, margins, centering,
//  right-fill, bullet rendering, section lines, and the joiner.
//

import XCTest
@testable import Sprung

final class TextFormatHelpersTests: XCTestCase {

    // MARK: - joiner

    func testJoinerJoinsWithSeparator() {
        XCTAssertEqual(TextFormatHelpers.joiner(["a", "b", "c"], separator: ", "), "a, b, c")
    }

    func testJoinerEmptyArrayIsEmptyString() {
        XCTAssertEqual(TextFormatHelpers.joiner([], separator: ", "), "")
    }

    func testJoinerSingleElementHasNoSeparator() {
        XCTAssertEqual(TextFormatHelpers.joiner(["solo"], separator: "|"), "solo")
    }

    // MARK: - wrapper

    func testWrapperShortTextStaysOnOneLine() {
        let out = TextFormatHelpers.wrapper("hello world", width: 80)
        XCTAssertEqual(out, "hello world")
    }

    func testWrapperWrapsAtEffectiveWidth() {
        // Effective width = 10. "one two three" -> "one two" (7) then adding " three" -> 13 > 10.
        let out = TextFormatHelpers.wrapper("one two three", width: 10)
        XCTAssertEqual(out, "one two\nthree")
    }

    func testWrapperLeftMarginIndentsEveryLine() {
        let out = TextFormatHelpers.wrapper("one two three", width: 14, leftMargin: 4)
        // effectiveWidth = 14 - 4 = 10 -> wraps "one two" / "three", each prefixed by 4 spaces.
        XCTAssertEqual(out, "    one two\n    three")
    }

    func testWrapperCenteredPadsBothSides() {
        // width 11, line "abc" (count 3) -> totalPadding 8, left 4, right 4.
        let out = TextFormatHelpers.wrapper("abc", width: 11, centered: true)
        XCTAssertEqual(out, "    abc    ")
        XCTAssertEqual(out.count, 11)
    }

    func testWrapperCenteredOddPaddingFavorsRight() {
        // width 10, "abc" -> totalPadding 7, left 3, right 4.
        let out = TextFormatHelpers.wrapper("abc", width: 10, centered: true)
        XCTAssertEqual(out, "   abc    ")
        XCTAssertEqual(out.count, 10)
    }

    func testWrapperRightFillPadsToWidth() {
        let out = TextFormatHelpers.wrapper("abc", width: 8, rightFill: true)
        XCTAssertEqual(out, "abc     ")
        XCTAssertEqual(out.count, 8)
    }

    func testWrapperRightFillWithLeftMargin() {
        // formattedLine = "  abc" then padded to width 8.
        let out = TextFormatHelpers.wrapper("abc", width: 8, leftMargin: 2, rightFill: true)
        XCTAssertEqual(out, "  abc   ")
        XCTAssertEqual(out.count, 8)
    }

    func testWrapperEmptyStringProducesEmptyOutput() {
        // No words -> no lines -> joined empty.
        XCTAssertEqual(TextFormatHelpers.wrapper("", width: 80), "")
    }

    // MARK: - bulletText

    func testBulletTextSingleLine() {
        let out = TextFormatHelpers.bulletText("hello", width: 80)
        XCTAssertEqual(out, "* hello")
    }

    func testBulletTextCustomBulletAndMargin() {
        let out = TextFormatHelpers.bulletText("hello", marginLeft: 2, width: 80, bullet: "-")
        XCTAssertEqual(out, "  - hello")
    }

    func testBulletTextWrapsAndIndentsContinuation() {
        // bullet "*" -> bulletSpace 2; width 12 -> textWidth = 12 - 0 - 2 = 10.
        // "one two three" wraps to "one two" / "three".
        let out = TextFormatHelpers.bulletText("one two three", width: 12)
        XCTAssertEqual(out, "* one two\n  three")
    }

    func testBulletTextWrapContinuationAlignsUnderText() {
        // marginLeft 2, bullet "*" (bulletSpace 2) -> continuation indent = 2 + 2 = 4.
        let out = TextFormatHelpers.bulletText("alpha beta gamma", marginLeft: 2, width: 14, bullet: "*")
        // textWidth = 14 - 2 - 2 = 10 -> "alpha beta" / "gamma".
        XCTAssertEqual(out, "  * alpha beta\n    gamma")
    }

    // MARK: - sectionLine

    func testSectionLineUppercasesAndCenters() {
        // width 20, title "abc" -> cleanTitle "ABC" (3). totalDashes = 20 - 3 - 4 = 13.
        // left 6, right 7.
        let out = TextFormatHelpers.sectionLine("abc", width: 20)
        XCTAssertEqual(out, "*------ ABC -------*")
        XCTAssertEqual(out.count, 20)
    }

    func testSectionLineStripsHTMLTags() {
        // stripTags removes <b></b>; result still uppercased and framed.
        let out = TextFormatHelpers.sectionLine("<b>hi</b>", width: 20)
        XCTAssertTrue(out.contains(" HI "), "tags should be stripped, content uppercased: \(out)")
        XCTAssertTrue(out.hasPrefix("*") && out.hasSuffix("*"))
    }
}
