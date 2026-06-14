//
//  StringExtensionsTests.swift
//  SprungTests
//
//  Pure-logic coverage for String+Extensions: HTML-entity decode,
//  trim, and consecutive-blank-line collapse.
//

import XCTest
@testable import Sprung

final class StringExtensionsTests: XCTestCase {

    // MARK: - decodingHTMLEntities

    func testDecodesNamedEntities() {
        XCTAssertEqual("a &lt; b &gt; c".decodingHTMLEntities(), "a < b > c")
        XCTAssertEqual("&quot;quoted&quot;".decodingHTMLEntities(), "\"quoted\"")
        XCTAssertEqual("it&apos;s".decodingHTMLEntities(), "it's")
        XCTAssertEqual("it&#39;s".decodingHTMLEntities(), "it's")
    }

    func testDecodesAmpersandLast() {
        // &amp;lt; must become &lt; (literal), not <, because &amp; is decoded last.
        XCTAssertEqual("&amp;lt;".decodingHTMLEntities(), "&lt;")
    }

    func testDecodesAmpersandEntity() {
        XCTAssertEqual("Tom &amp; Jerry".decodingHTMLEntities(), "Tom & Jerry")
    }

    func testDecodesNonBreakingSpaces() {
        XCTAssertEqual("a&nbsp;b".decodingHTMLEntities(), "a b")
        XCTAssertEqual("a\u{00A0}b".decodingHTMLEntities(), "a b")
    }

    func testDecodingLeavesPlainTextUntouched() {
        XCTAssertEqual("nothing to decode".decodingHTMLEntities(), "nothing to decode")
    }

    func testDecodingPreservesSurroundingWhitespace() {
        XCTAssertEqual("  &lt;tag&gt;  ".decodingHTMLEntities(), "  <tag>  ")
    }

    // MARK: - trimmed

    func testTrimmedRemovesSurroundingWhitespaceAndNewlines() {
        XCTAssertEqual("  \n hello \t\n".trimmed(), "hello")
    }

    func testTrimmedPreservesInteriorWhitespace() {
        XCTAssertEqual("  a b c  ".trimmed(), "a b c")
    }

    func testTrimmedOnAllWhitespaceIsEmpty() {
        XCTAssertEqual("   \n\t  ".trimmed(), "")
    }

    // MARK: - collapsingConsecutiveBlankLines

    func testCollapsesThreeOrMoreNewlinesToSingleBlankLine() {
        let input = "a\n\n\n\nb"
        XCTAssertEqual(input.collapsingConsecutiveBlankLines(), "a\n\nb")
    }

    func testPreservesSingleBlankLine() {
        let input = "a\n\nb"
        XCTAssertEqual(input.collapsingConsecutiveBlankLines(), "a\n\nb")
    }

    func testNoBlankLinesUnchanged() {
        let input = "a\nb\nc"
        XCTAssertEqual(input.collapsingConsecutiveBlankLines(), "a\nb\nc")
    }

    func testTrimsLeadingBlankLines() {
        let input = "\n\n\nfoo"
        XCTAssertEqual(input.collapsingConsecutiveBlankLines(), "foo")
    }

    func testTrimsTrailingBlankLines() {
        let input = "foo\n\n\n"
        XCTAssertEqual(input.collapsingConsecutiveBlankLines(), "foo")
    }

    func testWhitespaceOnlyLinesCountAsBlank() {
        // A line of spaces is blank; consecutive blanks (one with spaces) collapse.
        let input = "a\n   \n\nb"
        // First blank line ("   ") is kept (preserved with its content), second is dropped.
        XCTAssertEqual(input.collapsingConsecutiveBlankLines(), "a\n   \nb")
    }

    func testAllBlankCollapsesToEmpty() {
        XCTAssertEqual("\n\n\n".collapsingConsecutiveBlankLines(), "")
        XCTAssertEqual("   \n  \n\t".collapsingConsecutiveBlankLines(), "")
    }
}
