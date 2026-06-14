//
//  JSONResponseParserTests.swift
//  SprungTests
//
//  Pure-logic coverage for JSONResponseParser's extraction + parsing strategies:
//  fenced ```json blocks, generic fences, balanced brace/bracket counting, and
//  the flexible parse fallbacks. Includes adversarial inputs: nested braces,
//  escaped quotes, trailing prose, and no-JSON.
//

import XCTest
@testable import Sprung

final class JSONResponseParserTests: XCTestCase {

    private struct Sample: Codable, Equatable {
        let name: String
        let count: Int
    }

    private struct Nested: Codable, Equatable {
        let outer: Inner
        struct Inner: Codable, Equatable { let value: Int }
    }

    // MARK: - extractJSON: fenced blocks

    func testExtractFromJSONFence() {
        let text = "Here you go:\n```json\n{\"a\":1}\n```\nThanks!"
        XCTAssertEqual(JSONResponseParser.extractJSON(from: text), "{\"a\":1}")
    }

    func testExtractFromGenericFenceWithObject() {
        let text = "```\n{\"a\":1}\n```"
        XCTAssertEqual(JSONResponseParser.extractJSON(from: text), "{\"a\":1}")
    }

    func testExtractFromGenericFenceWithArray() {
        let text = "```\n[1,2,3]\n```"
        XCTAssertEqual(JSONResponseParser.extractJSON(from: text), "[1,2,3]")
    }

    func testGenericFenceWithNonJSONFallsThroughToBraceScan() {
        // Strategy 2 rejects (no { or [ prefix); strategy 3 finds the brace object.
        let text = "```\nsome code\n```\n{\"a\":1}"
        XCTAssertEqual(JSONResponseParser.extractJSON(from: text), "{\"a\":1}")
    }

    // MARK: - extractJSON: balanced brace/bracket counting

    func testExtractBalancedObjectIgnoringTrailingProse() {
        let text = "Sure: {\"name\":\"bob\"} -- hope that helps"
        XCTAssertEqual(JSONResponseParser.extractJSON(from: text), "{\"name\":\"bob\"}")
    }

    func testExtractBalancedNestedObject() {
        let text = "prefix {\"a\":{\"b\":1},\"c\":2} suffix"
        XCTAssertEqual(JSONResponseParser.extractJSON(from: text), "{\"a\":{\"b\":1},\"c\":2}")
    }

    func testExtractBalancedArrayWhenNoObjectPresent() {
        let text = "Numbers: [1,[2,3],4] done"
        XCTAssertEqual(JSONResponseParser.extractJSON(from: text), "[1,[2,3],4]")
    }

    func testObjectPreferredOverArrayWhenBothPresent() {
        // Strategy 3 (object) runs before strategy 4 (array).
        let text = "{\"k\":1} and [9,9]"
        XCTAssertEqual(JSONResponseParser.extractJSON(from: text), "{\"k\":1}")
    }

    func testUnbalancedObjectFallsThroughToOriginal() {
        // No closing brace anywhere, no array -> returns original text unchanged.
        let text = "this { is not closed"
        XCTAssertEqual(JSONResponseParser.extractJSON(from: text), text)
    }

    func testNoJSONReturnsOriginalText() {
        let text = "absolutely no json here"
        XCTAssertEqual(JSONResponseParser.extractJSON(from: text), text)
    }

    // MARK: - parseText (strict)

    func testParseTextDirectJSON() throws {
        let parsed = try JSONResponseParser.parseText(#"{"name":"bob","count":3}"#, as: Sample.self)
        XCTAssertEqual(parsed, Sample(name: "bob", count: 3))
    }

    func testParseTextEmbeddedJSONWithProse() throws {
        let text = "Here is the result: {\"name\":\"al\",\"count\":7}. Done."
        let parsed = try JSONResponseParser.parseText(text, as: Sample.self)
        XCTAssertEqual(parsed, Sample(name: "al", count: 7))
    }

    func testParseTextHandlesDirectNestedObject() throws {
        // A raw (un-fenced) nested object is valid JSON and decodes directly.
        let parsed = try JSONResponseParser.parseText(#"{"outer":{"value":42}}"#, as: Nested.self)
        XCTAssertEqual(parsed, Nested(outer: .init(value: 42)))
    }

    func testParseFlexibleHandlesNestedObjectInCodeFence() throws {
        // `parseText`'s regex strategies cannot extract a *nested* object out of a
        // code fence, but the flexible path strips the fence and decodes it. This
        // documents the capability boundary between the two entry points.
        let text = "```json\n{\"outer\":{\"value\":42}}\n```"
        let parsed = try JSONResponseParser.parseFlexibleFromText(text, as: Nested.self)
        XCTAssertEqual(parsed, Nested(outer: .init(value: 42)))
    }

    func testParseTextThrowsWhenNoJSON() {
        XCTAssertThrowsError(try JSONResponseParser.parseText("no json at all", as: Sample.self))
    }

    // MARK: - parseFlexibleFromText (lenient)

    func testParseFlexibleStripsFenceAndProse() throws {
        let text = "Sure thing!\n```json\n{\"name\":\"x\",\"count\":1}\n```\nLet me know if you need more."
        let parsed = try JSONResponseParser.parseFlexibleFromText(text, as: Sample.self)
        XCTAssertEqual(parsed, Sample(name: "x", count: 1))
    }

    func testParseFlexibleHandlesEscapedQuotesInValues() throws {
        // The value contains an escaped quote; balanced-brace recovery must keep it intact.
        let text = "result: {\"name\":\"he said \\\"hi\\\"\",\"count\":2} end"
        let parsed = try JSONResponseParser.parseFlexibleFromText(text, as: Sample.self)
        XCTAssertEqual(parsed.name, "he said \"hi\"")
        XCTAssertEqual(parsed.count, 2)
    }

    func testParseFlexibleThrowsWhenUnrecoverable() {
        XCTAssertThrowsError(
            try JSONResponseParser.parseFlexibleFromText("nothing parseable here", as: Sample.self)
        )
    }
}
