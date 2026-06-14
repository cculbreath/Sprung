//
//  HTMLUtilityTests.swift
//  SprungTests
//
//  Pure-logic coverage for HTMLUtility: tag stripping and font-reference fixing.
//
//  stripTags uses NSAttributedString HTML import (AppKit), which must run on the
//  main thread — hence @MainActor on the class.
//

import XCTest
@testable import Sprung

@MainActor
final class HTMLUtilityTests: XCTestCase {

    // MARK: - stripTags

    func testStripsSimpleTags() {
        let out = HTMLUtility.stripTags("<b>Hello</b>")
        XCTAssertEqual(out.trimmingCharacters(in: .whitespacesAndNewlines), "Hello")
    }

    func testStripsNestedTags() {
        let out = HTMLUtility.stripTags("<p>Hello <b>bold</b> world</p>")
        XCTAssertEqual(out.trimmingCharacters(in: .whitespacesAndNewlines), "Hello bold world")
    }

    func testPlainTextSurvivesStripping() {
        let out = HTMLUtility.stripTags("just text")
        XCTAssertEqual(out.trimmingCharacters(in: .whitespacesAndNewlines), "just text")
    }

    func testStripsCurvedArrowGlyph() {
        // The arrow glyph is explicitly removed after attributed-string conversion.
        let out = HTMLUtility.stripTags("line↪︎break")
        XCTAssertFalse(out.contains("↪︎"), "the ↪︎ glyph must be removed: \(out)")
    }

    // MARK: - fixFontReferences

    func testRemovesFileURLFontSrc() {
        let template = #"src: url("file:///Users/x/Fonts/MyFont.ttf") format("truetype");"#
        let fixed = HTMLUtility.fixFontReferences(template)
        XCTAssertFalse(fixed.contains("file://"), "file:// font src must be removed: \(fixed)")
        XCTAssertTrue(fixed.contains("Font file removed"), "replacement comment expected: \(fixed)")
    }

    func testLeavesNonFileFontSrcUntouched() {
        let template = #"src: url("https://cdn.example.com/font.woff2") format("woff2");"#
        let fixed = HTMLUtility.fixFontReferences(template)
        XCTAssertEqual(fixed, template, "remote (non-file) font src should be left as-is")
    }

    func testRemovesFontFaceBlockReferencingFile() {
        let template = #"@font-face { font-family: "X"; src: url("file:///x.ttf"); }"#
        let fixed = HTMLUtility.fixFontReferences(template)
        XCTAssertFalse(fixed.contains("file://"), "font-face block with file:// must be removed: \(fixed)")
        XCTAssertTrue(fixed.contains("Font"), "a replacement comment should remain: \(fixed)")
    }

    func testTemplateWithoutFontsUnchanged() {
        let template = "body { color: black; }"
        XCTAssertEqual(HTMLUtility.fixFontReferences(template), template)
    }
}
