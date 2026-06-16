//
//  JobDescriptionMarkdownParserTests.swift
//  SprungTests
//
//  Pins the structural markdown parse extracted from RichTextView: paragraph
//  classification (normal / bold-title / bullet-list) and bold-run segmentation.
//

import XCTest
@testable import Sprung

final class JobDescriptionMarkdownParserTests: XCTestCase {

    // MARK: - paragraphs(from:)

    func testPlainTextIsASingleNormalParagraph() {
        let paras = JobDescriptionMarkdownParser.paragraphs(from: "Just one block of prose.")
        XCTAssertEqual(paras.count, 1)
        guard case .normal = paras[0].type else { return XCTFail("expected .normal") }
        XCTAssertEqual(paras[0].content, "Just one block of prose.")
    }

    func testBoldTitleSectionSplitsIntoBoldThenNormal() {
        let paras = JobDescriptionMarkdownParser.paragraphs(from: "**Overview**\n\nWe build things.")
        XCTAssertEqual(paras.count, 2)
        guard case .bold = paras[0].type else { return XCTFail("expected .bold title") }
        XCTAssertEqual(paras[0].content, "Overview")
        guard case .normal = paras[1].type else { return XCTFail("expected .normal body") }
        XCTAssertEqual(paras[1].content, "We build things.")
    }

    func testInlineBoldTitleWithTrailingTextInSameSection() {
        let paras = JobDescriptionMarkdownParser.paragraphs(from: "**Title** and more text")
        XCTAssertEqual(paras.count, 2)
        guard case .bold = paras[0].type else { return XCTFail("expected .bold") }
        XCTAssertEqual(paras[0].content, "Title")
        guard case .normal = paras[1].type else { return XCTFail("expected .normal") }
        XCTAssertEqual(paras[1].content, "and more text")
    }

    func testBulletSectionIsClassifiedAsList() {
        let paras = JobDescriptionMarkdownParser.paragraphs(from: "* First item\n* Second item")
        XCTAssertEqual(paras.count, 1)
        guard case .list = paras[0].type else { return XCTFail("expected .list") }
    }

    func testInlineAsterisksStrippedWhenNoLeadingTitle() {
        let paras = JobDescriptionMarkdownParser.paragraphs(from: "Some **inline** emphasis")
        XCTAssertEqual(paras.count, 1)
        guard case .normal = paras[0].type else { return XCTFail("expected .normal") }
        XCTAssertEqual(paras[0].content, "Some inline emphasis", "** markers should be stripped")
    }

    // MARK: - boldSegments(in:startIndex:)

    func testBoldSegmentsSplitWithOffsets() {
        let segs = JobDescriptionMarkdownParser.boldSegments(in: "Lead **bold** tail", startIndex: 0)
        XCTAssertEqual(segs.count, 3)
        XCTAssertEqual(segs[0].text, "Lead ");  XCTAssertFalse(segs[0].isBold); XCTAssertEqual(segs[0].offset, 0)
        XCTAssertEqual(segs[1].text, "bold");   XCTAssertTrue(segs[1].isBold);  XCTAssertEqual(segs[1].offset, 5)
        XCTAssertEqual(segs[2].text, " tail");  XCTAssertFalse(segs[2].isBold); XCTAssertEqual(segs[2].offset, 13)
    }

    func testBoldSegmentsOffsetHonorsStartIndex() {
        let segs = JobDescriptionMarkdownParser.boldSegments(in: "**x**", startIndex: 100)
        XCTAssertEqual(segs.count, 1)
        XCTAssertTrue(segs[0].isBold)
        XCTAssertEqual(segs[0].offset, 100)
    }

    func testNoBoldRunsReturnsEmpty() {
        XCTAssertTrue(JobDescriptionMarkdownParser.boldSegments(in: "no emphasis here", startIndex: 0).isEmpty)
    }
}
