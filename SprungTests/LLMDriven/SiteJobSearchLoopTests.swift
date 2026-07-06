//
//  SiteJobSearchLoopTests.swift
//  SprungTests
//
//  Pure halves of the agentic small-site job search (SiteJobSearchLoop +
//  SiteJobSearchToolSchemas + SiteJobSearchService), no LLMFacade needed:
//
//  1. The strict submit_job_listings schema: camelCase keys we control, every
//     object closed (additionalProperties:false) with every property
//     required — the strict-tool-use compatibility contract — and the
//     server-tool declarations carrying this loop's budgets (search 8 /
//     fetch 25 / 8000 content tokens).
//  2. The submission contract: valid payloads, explicit-null optionals
//     (strict tool use sends null, not absent), the honest-empty shape
//     (empty listings + emptyReason), malformed payloads, and the
//     invalid-URL / duplicate-URL rejections that feed the runner's
//     corrective retry.
//  3. Task-message assembly: site URL + host + today, and the delimited
//     user-guidance block present only when provided.
//  4. Site-URL normalization for the view's Search gate.
//
//  Import-side halves (makeJobApp mapping, importAsLead dedup) live in
//  Persistence/SiteJobSearchImportTests.swift with an in-memory store.
//

import XCTest
import SwiftOpenAI
@testable import Sprung

@MainActor
final class SiteJobSearchLoopTests: XCTestCase {

    // MARK: - Helpers

    private func decodeToolUse(inputJSON: String) throws -> AnthropicToolUseResponseBlock {
        let json = #"{"type":"tool_use","id":"tu_1","name":"submit_job_listings","input":"# + inputJSON + "}"
        return try JSONDecoder().decode(AnthropicToolUseResponseBlock.self, from: Data(json.utf8))
    }

    private func encodedJSON<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    /// Recursively assert strict-tool-use compatibility: every object schema is
    /// closed and requires every property, and every property key is camelCase.
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

    // MARK: - 1. Tool schema shape

    func testSubmitListingsSchemaIsStrictCompatibleAndCamelCase() {
        assertStrictObject(SiteJobSearchToolSchemas.submitListingsSchema, path: "submitListings")
    }

    func testSubmitListingsSchemaPinsListingFieldsAndNullableLeaves() throws {
        let schema = SiteJobSearchToolSchemas.submitListingsSchema
        let properties = try XCTUnwrap(schema["properties"] as? [String: [String: Any]])
        XCTAssertEqual(Set(properties.keys), ["listings", "emptyReason"],
                       "top level = verified list + honest empty reason")

        let items = try XCTUnwrap(properties["listings"]?["items"] as? [String: Any])
        let listingProperties = try XCTUnwrap(items["properties"] as? [String: [String: Any]])
        XCTAssertEqual(Set(listingProperties.keys),
                       ["title", "company", "url", "location", "salary", "summary", "postedDate"])

        // Nullable leaves are ["type","null"]; verbatim fields are plain strings.
        for nullable in ["location", "salary", "postedDate"] {
            XCTAssertEqual(listingProperties[nullable]?["type"] as? [String], ["string", "null"],
                           "\(nullable) must be a nullable string leaf")
        }
        for verbatim in ["title", "company", "url", "summary"] {
            XCTAssertEqual(listingProperties[verbatim]?["type"] as? String, "string")
        }
        XCTAssertEqual(properties["emptyReason"]?["type"] as? [String], ["string", "null"])
    }

    func testToolsArrayDeclaresServerToolsWithBudgetsAndStrictCompletion() throws {
        let json = try encodedJSON(SiteJobSearchToolSchemas.allTools)

        // web_search: 20260209 variant with the site-scoped search budget.
        XCTAssertTrue(json.contains(#""type":"web_search_20260209""#))
        XCTAssertTrue(json.contains(#""max_uses":8"#))

        // web_fetch: 20260209 variant with fetch budget and content-token bound.
        XCTAssertTrue(json.contains(#""type":"web_fetch_20260209""#))
        XCTAssertTrue(json.contains(#""max_uses":25"#))
        XCTAssertTrue(json.contains(#""max_content_tokens":8000"#))

        // Completion tool: strict.
        XCTAssertTrue(json.contains(#""name":"submit_job_listings""#))
        XCTAssertTrue(json.contains(#""strict":true"#))
    }

    // MARK: - 2. Submission decoding

    func testDecodeSubmissionValidListings() throws {
        let call = try decodeToolUse(inputJSON: #"""
        {"listings":[
          {"title":"Firmware Engineer","company":"Acme Robotics",
           "url":"https://austinjobs.example.com/jobs/firmware-engineer?id=42",
           "location":"Austin, TX","salary":"$140k–$165k",
           "summary":"Ship embedded C++ on ARM Cortex targets for warehouse robots.",
           "postedDate":"July 2, 2026"},
          {"title":"QA Analyst","company":"Initech",
           "url":"https://austinjobs.example.com/jobs/qa-analyst",
           "location":null,"salary":null,
           "summary":"Manual and automated testing across the reporting suite.",
           "postedDate":null}
        ],"emptyReason":null}
        """#)

        let submission = try SiteJobSearchLoop.decodeSubmission(call)
        XCTAssertEqual(submission.listings.count, 2)
        XCTAssertEqual(submission.listings[0].title, "Firmware Engineer")
        XCTAssertEqual(submission.listings[0].url,
                       "https://austinjobs.example.com/jobs/firmware-engineer?id=42",
                       "the canonical URL survives verbatim — query strings are posting identity on small boards")
        XCTAssertEqual(submission.listings[0].salary, "$140k–$165k")
        XCTAssertNil(submission.listings[1].location, "explicit JSON null decodes to nil")
        XCTAssertNil(submission.listings[1].salary)
        XCTAssertNil(submission.listings[1].postedDate)
        XCTAssertNil(submission.emptyReason)
    }

    func testDecodeSubmissionHonestEmptyCarriesReason() throws {
        let call = try decodeToolUse(inputJSON:
            #"{"listings":[],"emptyReason":"The site blocked every fetch attempt (bot wall)."}"#
        )
        let submission = try SiteJobSearchLoop.decodeSubmission(call)
        XCTAssertTrue(submission.listings.isEmpty,
                      "an unreachable/bot-walled site is a legitimate, honest outcome")
        XCTAssertEqual(submission.emptyReason, "The site blocked every fetch attempt (bot wall).")
    }

    func testDecodeSubmissionMissingRequiredFieldThrows() throws {
        // No "title" — decode must fail with a corrective, retryable error.
        let call = try decodeToolUse(inputJSON: #"""
        {"listings":[{"company":"Acme","url":"https://example.com/j/1",
         "location":null,"salary":null,"summary":"s","postedDate":null}],"emptyReason":null}
        """#)
        XCTAssertThrowsError(try SiteJobSearchLoop.decodeSubmission(call)) { error in
            guard case SiteJobSearchError.llmError(let message) = error else {
                return XCTFail("expected .llmError, got \(error)")
            }
            XCTAssertTrue(message.contains("failed to decode"))
        }
    }

    func testDecodeSubmissionBlankEssentialsThrowCorrectiveError() throws {
        let call = try decodeToolUse(inputJSON: #"""
        {"listings":[{"title":"  ","company":"Acme","url":"https://example.com/j/1",
         "location":null,"salary":null,"summary":"s","postedDate":null}],"emptyReason":null}
        """#)
        XCTAssertThrowsError(try SiteJobSearchLoop.decodeSubmission(call)) { error in
            guard case SiteJobSearchError.llmError(let message) = error else {
                return XCTFail("expected .llmError, got \(error)")
            }
            XCTAssertTrue(message.contains("missing a title, company, or summary"),
                          "corrective message must name the defect")
        }
    }

    func testDecodeSubmissionInvalidURLThrowsCorrectiveError() throws {
        let call = try decodeToolUse(inputJSON: #"""
        {"listings":[{"title":"Ghost Job","company":"Acme","url":"the careers page",
         "location":null,"salary":null,"summary":"s","postedDate":null}],"emptyReason":null}
        """#)
        XCTAssertThrowsError(try SiteJobSearchLoop.decodeSubmission(call)) { error in
            guard case SiteJobSearchError.llmError(let message) = error else {
                return XCTFail("expected .llmError, got \(error)")
            }
            XCTAssertTrue(message.contains("invalid posting URLs"))
            XCTAssertTrue(message.contains("Ghost Job"), "corrective message must name the offending listing")
        }
    }

    func testDecodeSubmissionDuplicateURLThrowsCorrectiveError() throws {
        let call = try decodeToolUse(inputJSON: #"""
        {"listings":[
          {"title":"Role A","company":"Acme","url":"https://example.com/j/1",
           "location":null,"salary":null,"summary":"a","postedDate":null},
          {"title":"Role A (again)","company":"Acme","url":"https://example.com/j/1",
           "location":null,"salary":null,"summary":"a","postedDate":null}
        ],"emptyReason":null}
        """#)
        XCTAssertThrowsError(try SiteJobSearchLoop.decodeSubmission(call)) { error in
            guard case SiteJobSearchError.llmError(let message) = error else {
                return XCTFail("expected .llmError, got \(error)")
            }
            XCTAssertTrue(message.contains("repeat a posting URL"))
            XCTAssertTrue(message.contains("Role A (again)"))
        }
    }

    // MARK: - 3. Task-message assembly

    private var fixedToday: Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: "2026-07-06")!
    }

    func testUserMessageCarriesSiteHostAndToday() throws {
        let siteURL = try XCTUnwrap(SiteJobSearchService.normalizedSiteURL("austinjobs.example.com"))
        let message = SiteJobSearchService.userMessage(siteURL: siteURL, guidance: "", today: fixedToday)
        XCTAssertTrue(message.contains("SITE: https://austinjobs.example.com"))
        XCTAssertTrue(message.contains("SITE HOST (for site: search operators): austinjobs.example.com"))
        XCTAssertTrue(message.contains("Today: 2026-07-06"))
    }

    func testUserMessageGuidanceBlockPresentOnlyWhenProvided() throws {
        let siteURL = try XCTUnwrap(SiteJobSearchService.normalizedSiteURL("https://example.com/careers"))

        let plain = SiteJobSearchService.userMessage(siteURL: siteURL, guidance: "", today: fixedToday)
        XCTAssertFalse(plain.contains("SEARCH GUIDANCE"), "empty guidance = plain run")

        let whitespace = SiteJobSearchService.userMessage(siteURL: siteURL, guidance: " \n ", today: fixedToday)
        XCTAssertFalse(whitespace.contains("SEARCH GUIDANCE"), "whitespace-only guidance = plain run")

        let steered = SiteJobSearchService.userMessage(
            siteURL: siteURL, guidance: "Embedded firmware roles, on-site.", today: fixedToday
        )
        XCTAssertTrue(steered.contains("## SEARCH GUIDANCE FROM THE USER\nEmbedded firmware roles, on-site."),
                      "guidance arrives as a clearly delimited steering block")
    }

    // MARK: - 4. Site-URL normalization

    func testNormalizedSiteURLAddsHTTPSToBareHost() {
        XCTAssertEqual(SiteJobSearchService.normalizedSiteURL("austinjobs.com")?.absoluteString,
                       "https://austinjobs.com")
        XCTAssertEqual(SiteJobSearchService.normalizedSiteURL("  example.com/careers  ")?.absoluteString,
                       "https://example.com/careers", "trims whitespace and keeps the path")
    }

    func testNormalizedSiteURLPreservesExplicitScheme() {
        XCTAssertEqual(SiteJobSearchService.normalizedSiteURL("http://jobs.example.com")?.scheme, "http")
        XCTAssertEqual(SiteJobSearchService.normalizedSiteURL("https://jobs.example.com/openings")?.absoluteString,
                       "https://jobs.example.com/openings")
    }

    func testNormalizedSiteURLRejectsNonSites() {
        XCTAssertNil(SiteJobSearchService.normalizedSiteURL(""))
        XCTAssertNil(SiteJobSearchService.normalizedSiteURL("   "))
        XCTAssertNil(SiteJobSearchService.normalizedSiteURL("not a url"))
        XCTAssertNil(SiteJobSearchService.normalizedSiteURL("localhost"), "host must be dotted")
    }
}
