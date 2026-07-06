//
//  DiscoveryOnboardingCallsTests.swift
//  SprungTests
//
//  Pure halves of the two Discovery-onboarding structured calls
//  (role suggestions + location-preference extraction), which run on the
//  Discovery Anthropic model via DiscoveryAgentService (2026-07 migration off
//  the module's former OpenAI path). Covers the request-build half (user
//  prompts and the [String: Any] structured-output schemas — camelCase keys we
//  control, additionalProperties: false on every object, all properties
//  required with nullability expressed as ["type","null"]) and the
//  response-parse half (wire DTO decoding plus the tolerant string→enum
//  mappers). The network execution itself rides the shared
//  executeStructuredWithAnthropicCaching facade path and is out of scope here.
//

import XCTest
@testable import Sprung

@MainActor
final class DiscoveryOnboardingCallsTests: XCTestCase {

    private let decoder = JSONDecoder()

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        let data = try XCTUnwrap(json.data(using: .utf8))
        return try decoder.decode(type, from: data)
    }

    // MARK: - Role suggestions: request-build half

    func testRoleSuggestionsPromptIncludesDossierAndOmitsOptionalBlocksWhenAbsent() {
        let prompt = DiscoveryAgentService.roleSuggestionsUserPrompt(
            dossierSummary: "Twelve years of embedded firmware work.",
            existingRoles: [],
            keywords: nil
        )
        XCTAssertTrue(prompt.contains("Twelve years of embedded firmware work."))
        XCTAssertFalse(prompt.contains("already indicated interest"),
                       "no existing-roles block when the user picked nothing yet")
        XCTAssertFalse(prompt.contains("KEYWORDS TO EXPLORE"),
                       "no keywords block without keywords")
        XCTAssertFalse(prompt.contains("4."),
                       "the keywords focus item only appears alongside keywords")
    }

    func testRoleSuggestionsPromptIncludesExistingRolesAndKeywordsBlocks() {
        let prompt = DiscoveryAgentService.roleSuggestionsUserPrompt(
            dossierSummary: "Background.",
            existingRoles: ["Firmware Engineer", "Embedded Lead"],
            keywords: "robotics, medical devices"
        )
        XCTAssertTrue(prompt.contains("Firmware Engineer, Embedded Lead"),
                      "existing roles are joined into the complementary-roles block")
        XCTAssertTrue(prompt.contains("KEYWORDS TO EXPLORE"))
        XCTAssertTrue(prompt.contains("robotics, medical devices"))
        XCTAssertTrue(prompt.contains("4. Roles that connect to the specified keywords/interests"),
                      "keywords add a fourth focus item")
    }

    func testRoleSuggestionsPromptTreatsEmptyKeywordsAsAbsent() {
        let prompt = DiscoveryAgentService.roleSuggestionsUserPrompt(
            dossierSummary: "Background.",
            existingRoles: [],
            keywords: ""
        )
        XCTAssertFalse(prompt.contains("KEYWORDS TO EXPLORE"),
                       "an empty keywords string must not emit an empty block")
    }

    func testRoleSuggestionsSchemaShape() throws {
        let schema = DiscoveryAgentService.roleSuggestionsSchema
        XCTAssertEqual(schema["type"] as? String, "object")
        XCTAssertEqual(schema["additionalProperties"] as? Bool, false,
                       "Anthropic structured output 400s without additionalProperties: false")
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        XCTAssertEqual(Set(properties.keys), ["suggestedRoles", "reasoning"],
                       "camelCase keys we control")
        XCTAssertEqual(Set(try XCTUnwrap(schema["required"] as? [String])),
                       ["suggestedRoles", "reasoning"],
                       "all properties required; optionality is expressed via null types")
        let reasoning = try XCTUnwrap(properties["reasoning"] as? [String: Any])
        XCTAssertEqual(try XCTUnwrap(reasoning["type"] as? [String]), ["string", "null"],
                       "reasoning is a required-but-nullable leaf")
        let roles = try XCTUnwrap(properties["suggestedRoles"] as? [String: Any])
        XCTAssertEqual(roles["type"] as? String, "array")
        XCTAssertEqual((roles["items"] as? [String: Any])?["type"] as? String, "string")
    }

    // MARK: - Role suggestions: response-parse half

    func testRoleSuggestionsResultDecodesCamelCaseAndNullReasoning() throws {
        let result = try decode(RoleSuggestionsResult.self, """
        { "suggestedRoles": ["Staff Firmware Engineer", "Robotics Software Lead"], "reasoning": null }
        """)
        XCTAssertEqual(result.suggestedRoles, ["Staff Firmware Engineer", "Robotics Software Lead"])
        XCTAssertNil(result.reasoning, "explicit JSON null reasoning decodes to nil")

        let withReasoning = try decode(RoleSuggestionsResult.self, """
        { "suggestedRoles": [], "reasoning": "Level-matched to staff scope." }
        """)
        XCTAssertEqual(withReasoning.reasoning, "Level-matched to staff scope.")
    }

    // MARK: - Location preferences: request-build half

    func testLocationPreferencesPromptIncludesBothSources() {
        let prompt = DiscoveryAgentService.locationPreferencesUserPrompt(
            profileInfo: "Name: Ada\nCity: Round Rock",
            dossierSummary: "Prefers hybrid schedules."
        )
        XCTAssertTrue(prompt.contains("APPLICANT PROFILE:"))
        XCTAssertTrue(prompt.contains("City: Round Rock"))
        XCTAssertTrue(prompt.contains("BACKGROUND/DOSSIER:"))
        XCTAssertTrue(prompt.contains("Prefers hybrid schedules."))
    }

    func testLocationPreferencesSchemaShape() throws {
        let schema = DiscoveryAgentService.locationPreferencesSchema
        XCTAssertEqual(schema["type"] as? String, "object")
        XCTAssertEqual(schema["additionalProperties"] as? Bool, false)
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        let expectedKeys: Set<String> = ["location", "workArrangement", "remoteAcceptable", "companySize"]
        XCTAssertEqual(Set(properties.keys), expectedKeys)
        XCTAssertEqual(Set(try XCTUnwrap(schema["required"] as? [String])), expectedKeys,
                       "every field required; the model signals unknown with null")
        for key in ["location", "workArrangement", "companySize"] {
            let leaf = try XCTUnwrap(properties[key] as? [String: Any], key)
            XCTAssertEqual(try XCTUnwrap(leaf["type"] as? [String]), ["string", "null"],
                           "\(key) is a nullable string leaf")
        }
        let remote = try XCTUnwrap(properties["remoteAcceptable"] as? [String: Any])
        XCTAssertEqual(try XCTUnwrap(remote["type"] as? [String]), ["boolean", "null"])
    }

    // MARK: - Location preferences: response-parse half

    func testLocationPreferencesResultDecodesAllNulls() throws {
        let result = try decode(LocationPreferencesResult.self, """
        { "location": null, "workArrangement": null, "remoteAcceptable": null, "companySize": null }
        """)
        XCTAssertNil(result.location)
        XCTAssertNil(result.workArrangement)
        XCTAssertNil(result.remoteAcceptable)
        XCTAssertNil(result.companySize)
    }

    func testExtractedPreferencesMapsWireValuesToEnums() throws {
        let result = try decode(LocationPreferencesResult.self, """
        { "location": "Austin, TX", "workArrangement": "hybrid", "remoteAcceptable": true, "companySize": "mid" }
        """)
        let extracted = DiscoveryAgentService.extractedPreferences(from: result)
        XCTAssertEqual(extracted.location, "Austin, TX")
        XCTAssertEqual(extracted.workArrangement, .hybrid)
        XCTAssertEqual(extracted.remoteAcceptable, true)
        XCTAssertEqual(extracted.companySize, .mid)
    }

    func testParseWorkArrangementToleratesVariants() {
        XCTAssertEqual(DiscoveryAgentService.parseWorkArrangement("remote"), .remote)
        XCTAssertEqual(DiscoveryAgentService.parseWorkArrangement("Hybrid"), .hybrid,
                       "matching is case-insensitive")
        XCTAssertEqual(DiscoveryAgentService.parseWorkArrangement("onsite"), .onsite)
        XCTAssertEqual(DiscoveryAgentService.parseWorkArrangement("on-site"), .onsite)
        XCTAssertEqual(DiscoveryAgentService.parseWorkArrangement("in-office"), .onsite)
        XCTAssertNil(DiscoveryAgentService.parseWorkArrangement("four-day week"),
                     "unrecognized values map to nil, never a guessed default")
        XCTAssertNil(DiscoveryAgentService.parseWorkArrangement(nil))
    }

    func testParseCompanySizePreferenceToleratesVariants() {
        XCTAssertEqual(DiscoveryAgentService.parseCompanySizePreference("startup"), .startup)
        XCTAssertEqual(DiscoveryAgentService.parseCompanySizePreference("small"), .small)
        XCTAssertEqual(DiscoveryAgentService.parseCompanySizePreference("mid"), .mid)
        XCTAssertEqual(DiscoveryAgentService.parseCompanySizePreference("Mid-size"), .mid)
        XCTAssertEqual(DiscoveryAgentService.parseCompanySizePreference("midsize"), .mid)
        XCTAssertEqual(DiscoveryAgentService.parseCompanySizePreference("enterprise"), .enterprise)
        XCTAssertEqual(DiscoveryAgentService.parseCompanySizePreference("large"), .enterprise)
        XCTAssertEqual(DiscoveryAgentService.parseCompanySizePreference("any"), .any)
        XCTAssertNil(DiscoveryAgentService.parseCompanySizePreference("co-op"))
        XCTAssertNil(DiscoveryAgentService.parseCompanySizePreference(nil))
    }
}
