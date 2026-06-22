//
//  RepositoryDigestSchemaConformanceTests.swift
//  SprungTests
//
//  Guards the `complete_analysis` strict-tool-use contract at the schema↔decoder
//  seam — the kind of drift that otherwise only surfaces as an Anthropic 400
//  (strict enforcement) or a runtime DecodingError + agent-loop spin:
//    1. the schema is strict-valid (every object sets additionalProperties:false
//       and lists EVERY property in `required`),
//    2. the three formerly-optional leaves are nullable-typed (["string","null"]),
//    3. a strict-shaped JSON payload decodes cleanly into `Parameters`.
//

import XCTest
@testable import Sprung

final class RepositoryDigestSchemaConformanceTests: XCTestCase {

    // MARK: - 1. Strict-valid at every object

    func testSchemaIsStrictValidAtEveryObject() {
        assertStrictValid(RepositoryDigestTool.parametersSchema, path: "root")
    }

    /// Strict tool use requires, at every object node: `additionalProperties: false`
    /// and a `required` array equal to the full set of property keys.
    private func assertStrictValid(_ node: [String: Any], path: String) {
        let typeString = node["type"] as? String

        if typeString == "object" {
            let props = node["properties"] as? [String: Any] ?? [:]
            XCTAssertEqual(node["additionalProperties"] as? Bool, false,
                           "\(path): object must set additionalProperties:false (strict)")
            let required = Set(node["required"] as? [String] ?? [])
            XCTAssertEqual(required, Set(props.keys),
                           "\(path): strict requires every property in `required`")
            for (key, value) in props {
                if let child = value as? [String: Any] {
                    assertStrictValid(child, path: "\(path).\(key)")
                }
            }
        } else if typeString == "array", let items = node["items"] as? [String: Any] {
            assertStrictValid(items, path: "\(path)[]")
        }
    }

    // MARK: - 2. Nullable leaves

    func testNullableLeavesAreNullableTyped() {
        let props = RepositoryDigestTool.parametersSchema["properties"] as? [String: Any]
        let thItems = ((props?["technicalHighlights"] as? [String: Any])?["items"] as? [String: Any])?["properties"] as? [String: Any]
        let ceItems = ((props?["codeExcerpts"] as? [String: Any])?["items"] as? [String: Any])?["properties"] as? [String: Any]

        XCTAssertEqual((thItems?["lineRange"] as? [String: Any])?["type"] as? [String], ["string", "null"],
                       "technicalHighlights[].lineRange must be nullable for strict")
        XCTAssertEqual((ceItems?["lineRange"] as? [String: Any])?["type"] as? [String], ["string", "null"],
                       "codeExcerpts[].lineRange must be nullable for strict")
        XCTAssertEqual((ceItems?["tiedToClaim"] as? [String: Any])?["type"] as? [String], ["string", "null"],
                       "codeExcerpts[].tiedToClaim must be nullable for strict")
    }

    // MARK: - 3. Schema-shaped payload decodes (schema↔decoder agreement)

    func testStrictShapedPayloadDecodesIntoParameters() throws {
        // A minimal payload whose keys match the schema's top-level + productionQuality
        // keys. The production decode path uses a bare JSONDecoder (camelCase) — if the
        // schema and `Parameters`/IR keys ever drift, this decode throws.
        let json = """
        {
          "architecture": "",
          "capabilities": [],
          "technicalHighlights": [],
          "codeExcerpts": [],
          "dependencyUsage": [],
          "productionQuality": {
            "testing": "", "cicd": "", "infraAndDeploy": "", "observability": "",
            "lintFormatTypeSafety": "", "docsQuality": "", "accessibilityI18n": "", "securityTooling": ""
          },
          "skillSignals": [],
          "entryPoints": [],
          "manifests": [],
          "readmeAndDocs": [],
          "omissions": ""
        }
        """
        let params = try JSONDecoder().decode(
            RepositoryDigestTool.Parameters.self, from: Data(json.utf8))
        XCTAssertEqual(params.productionQuality.infraAndDeploy, "")
        XCTAssertTrue(params.manifests.isEmpty)

        // And the schema's top-level property keys are exactly the decoded payload's keys.
        let schemaKeys = Set((RepositoryDigestTool.parametersSchema["properties"] as? [String: Any] ?? [:]).keys)
        let payloadKeys = Set((try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] ?? [:]).keys)
        XCTAssertEqual(schemaKeys, payloadKeys,
                       "schema top-level property keys must match what Parameters decodes (camelCase, no drift)")
    }
}
