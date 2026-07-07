//
//  CheckPageCountToolTests.swift
//  SprungTests
//
//  The revision agent's page-overflow skill: `check_page_count` renders the
//  CURRENT workspace state into a scratch clone (never the real resume) and
//  reports {pageCount, previousPageCount}. The tool's pure halves — the
//  Anthropic input schema and the result-JSON construction — are dependency-
//  free, so we pin them here: strict schema (additionalProperties: false, no
//  parameters) and camelCase result keys with an explicit JSON null (never a
//  fabricated number) when no previous count exists.
//

import XCTest
@testable import Sprung

final class CheckPageCountToolTests: XCTestCase {

    // MARK: - Schema strictness

    func testToolNameIsStable() {
        XCTAssertEqual(CheckPageCountTool.name, "check_page_count")
    }

    func testSchemaIsStrictEmptyObject() throws {
        let schema = CheckPageCountTool.parametersSchema
        XCTAssertEqual(schema["type"] as? String, "object")
        XCTAssertEqual(schema["additionalProperties"] as? Bool, false,
                       "tool-schema objects we control must set additionalProperties: false")
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        XCTAssertTrue(properties.isEmpty, "check_page_count takes no parameters")
        let required = try XCTUnwrap(schema["required"] as? [String])
        XCTAssertTrue(required.isEmpty)
    }

    func testParametersDecodeFromEmptyObject() throws {
        // The model sends "{}" for a no-parameter tool; decoding must succeed.
        XCTAssertNoThrow(try JSONDecoder().decode(
            CheckPageCountTool.Parameters.self,
            from: Data("{}".utf8)
        ))
    }

    // MARK: - Result JSON (pure half)

    func testResultJSONUsesCamelCaseKeysOnly() throws {
        let json = CheckPageCountTool.resultJSON(pageCount: 2, previousPageCount: 3)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        )
        XCTAssertEqual(object["pageCount"] as? Int, 2)
        XCTAssertEqual(object["previousPageCount"] as? Int, 3)
        XCTAssertEqual(Set(object.keys), ["pageCount", "previousPageCount"],
                       "exactly the two camelCase keys we control, nothing else")
    }

    func testResultJSONReportsMissingPreviousCountAsExplicitNull() throws {
        let json = CheckPageCountTool.resultJSON(pageCount: 1, previousPageCount: nil)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        )
        XCTAssertEqual(object["pageCount"] as? Int, 1)
        XCTAssertTrue(object["previousPageCount"] is NSNull,
                      "no previous render → explicit JSON null, never a fabricated count")
    }
}
