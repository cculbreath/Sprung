//
//  JobScoutToolSchemasTests.swift
//  SprungTests
//
//  The Job Scout tool schemas' strict-tool-use contract: every object closed
//  (additionalProperties:false) with every property required, every key we
//  control camelCase, the board enum pinned to ScoutBoard's raw values, the
//  camelCase datePosted values, and all three tools declared strict.
//

import XCTest
import SwiftOpenAI
@testable import Sprung

final class JobScoutToolSchemasTests: XCTestCase {

    // MARK: - Helpers

    /// Recursively assert strict-tool-use compatibility: every object schema
    /// is closed and requires every property, and every property key is
    /// camelCase (mirrors SiteJobSearchLoopTests' walker).
    private func assertStrictObject(_ schema: [String: Any], path: String) {
        let isObject = (schema["type"] as? String) == "object" || schema["properties"] != nil
        guard isObject else { return }

        XCTAssertEqual(schema["additionalProperties"] as? Bool, false,
                       "\(path): every object needs additionalProperties:false")
        let properties = schema["properties"] as? [String: [String: Any]] ?? [:]
        let required = Set(schema["required"] as? [String] ?? [])
        XCTAssertEqual(Set(properties.keys), required,
                       "\(path): strict tool use requires every property in required")

        for (key, subSchema) in properties {
            XCTAssertFalse(key.contains("_"),
                           "\(path).\(key): schema keys we control must be camelCase")
            assertStrictObject(subSchema, path: "\(path).\(key)")
            if let items = subSchema["items"] as? [String: Any] {
                assertStrictObject(items, path: "\(path).\(key).items")
            }
        }
    }

    // MARK: - Strict compatibility, all three schemas

    func testSearchBoardSchemaIsStrictCompatibleAndCamelCase() {
        assertStrictObject(JobScoutToolSchemas.searchBoardSchema, path: "searchBoard")
    }

    func testGetJobDetailsSchemaIsStrictCompatibleAndCamelCase() {
        assertStrictObject(JobScoutToolSchemas.getJobDetailsSchema, path: "getJobDetails")
    }

    func testRecommendJobsSchemaIsStrictCompatibleAndCamelCase() {
        assertStrictObject(JobScoutToolSchemas.recommendJobsSchema, path: "recommendJobs")
    }

    // MARK: - search_board shape

    func testSearchBoardSchemaPinsBoardEnumAndNullableLeaves() throws {
        let schema = JobScoutToolSchemas.searchBoardSchema
        let properties = try XCTUnwrap(schema["properties"] as? [String: [String: Any]])
        XCTAssertEqual(Set(properties.keys), ["board", "keywords", "location", "datePosted"])

        XCTAssertEqual(properties["board"]?["enum"] as? [String],
                       ["dice", "zipRecruiter", "linkedIn"],
                       "the board enum is exactly ScoutBoard's raw values")
        XCTAssertEqual(properties["keywords"]?["type"] as? String, "string")
        XCTAssertEqual(properties["location"]?["type"] as? [String], ["string", "null"])
        XCTAssertEqual(properties["datePosted"]?["type"] as? [String], ["string", "null"])
    }

    func testDatePostedValuesAreCamelCase() {
        XCTAssertEqual(JobScoutToolSchemas.datePostedValues,
                       ["pastHour", "past24Hours", "pastWeek", "pastMonth"])
        for value in JobScoutToolSchemas.datePostedValues {
            XCTAssertFalse(value.contains("_"),
                           "datePosted values are keys we control — camelCase, mapped to the wire facet in the service")
        }
    }

    // MARK: - recommend_jobs shape

    func testRecommendJobsSchemaPinsRecommendationFields() throws {
        let schema = JobScoutToolSchemas.recommendJobsSchema
        let properties = try XCTUnwrap(schema["properties"] as? [String: [String: Any]])
        XCTAssertEqual(Set(properties.keys), ["recommendations", "emptyReason"],
                       "top level = the picks + the honest empty reason")
        XCTAssertEqual(properties["emptyReason"]?["type"] as? [String], ["string", "null"])

        let items = try XCTUnwrap(properties["recommendations"]?["items"] as? [String: Any])
        let recommendationProperties = try XCTUnwrap(items["properties"] as? [String: [String: Any]])
        XCTAssertEqual(Set(recommendationProperties.keys), ["url", "title", "company", "reasoning", "match"])
        for key in ["url", "title", "company", "reasoning"] {
            XCTAssertEqual(recommendationProperties[key]?["type"] as? String, "string")
        }
    }

    func testRecommendJobsSchemaPinsMatchAssessment() throws {
        let schema = JobScoutToolSchemas.recommendJobsSchema
        let properties = try XCTUnwrap(schema["properties"] as? [String: [String: Any]])
        let items = try XCTUnwrap(properties["recommendations"]?["items"] as? [String: Any])
        let recommendationProperties = try XCTUnwrap(items["properties"] as? [String: [String: Any]])
        let match = try XCTUnwrap(recommendationProperties["match"])
        let matchProperties = try XCTUnwrap(match["properties"] as? [String: [String: Any]])

        XCTAssertEqual(Set(matchProperties.keys),
                       ["skills", "seniority", "locationFit", "compensation", "verdict"])
        for dimension in ["skills", "seniority", "locationFit", "compensation"] {
            XCTAssertEqual(matchProperties[dimension]?["enum"] as? [String],
                           ["strong", "moderate", "weak", "unknown"],
                           "\(dimension) is an honest enum with an explicit unknown, never a number")
        }
        XCTAssertEqual(matchProperties["verdict"]?["enum"] as? [String],
                       ["strong", "promising", "marginal"])
    }

    // MARK: - Tool declarations

    func testAllToolsDeclaresThreeStrictFunctionToolsPlusWebFetch() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = String(decoding: try encoder.encode(JobScoutToolSchemas.allTools), as: UTF8.self)

        XCTAssertTrue(json.contains(#""name":"search_board""#))
        XCTAssertTrue(json.contains(#""name":"get_job_details""#))
        XCTAssertTrue(json.contains(#""name":"recommend_jobs""#))
        XCTAssertEqual(json.components(separatedBy: #""strict":true"#).count - 1, 3,
                       "the three client tools are strict — the schemas guarantee decodable inputs")
        XCTAssertTrue(json.contains("web_fetch"),
                      "Dice/ZipRecruiter postings are read with the server-side web_fetch tool")
        XCTAssertFalse(json.contains("web_search"),
                       "the scout reads specific posting urls — it declares web_fetch but not web_search")
    }
}
