//
//  SchemaConverterTests.swift
//  SprungTests
//
//  Pure-logic coverage for the two schema converters:
//   - JSONSchema.from(dictionary:)  — [String: Any] -> SwiftOpenAI JSONSchema
//   - AnthropicSchemaConverter      — JSONSchema -> [String: Any] (Anthropic shape)
//  Covers union (nullable) types, required fields, additionalProperties defaulting,
//  recursion (nested objects / array items), enums, $ref, and a round-trip.
//

import XCTest
import SwiftOpenAI
@testable import Sprung

final class SchemaConverterTests: XCTestCase {

    // MARK: - JSONSchema.from(dictionary:)

    func testScalarTypeAndDescription() throws {
        let schema = try JSONSchema.from(dictionary: [
            "type": "string",
            "description": "a name"
        ])
        XCTAssertEqual(schema.type, .string)
        XCTAssertEqual(schema.description, "a name")
        // additionalProperties defaults to false (strict mode) when absent.
        XCTAssertEqual(schema.additionalProperties, false)
    }

    func testUnknownTypeThrows() {
        XCTAssertThrowsError(try JSONSchema.from(dictionary: ["type": "frobnicate"])) { error in
            guard case JSONSchemaConversionError.invalidType(let t) = error else {
                return XCTFail("expected .invalidType, got \(error)")
            }
            XCTAssertEqual(t, "frobnicate")
        }
    }

    func testUnionTypeFromTypeArray() throws {
        let schema = try JSONSchema.from(dictionary: ["type": ["string", "null"]])
        XCTAssertEqual(schema.type, .union([.string, .null]))
    }

    func testObjectWithPropertiesAndRequired() throws {
        let schema = try JSONSchema.from(dictionary: [
            "type": "object",
            "properties": [
                "name": ["type": "string"],
                "age": ["type": "integer"]
            ],
            "required": ["name"]
        ])
        XCTAssertEqual(schema.type, .object)
        XCTAssertEqual(schema.properties?["name"]?.type, .string)
        XCTAssertEqual(schema.properties?["age"]?.type, .integer)
        XCTAssertEqual(schema.required, ["name"])
    }

    func testNestedObjectRecursion() throws {
        let schema = try JSONSchema.from(dictionary: [
            "type": "object",
            "properties": [
                "address": [
                    "type": "object",
                    "properties": [
                        "city": ["type": "string"]
                    ]
                ]
            ]
        ])
        let address = try XCTUnwrap(schema.properties?["address"])
        XCTAssertEqual(address.type, .object)
        XCTAssertEqual(address.properties?["city"]?.type, .string)
    }

    func testArrayItemsRecursion() throws {
        let schema = try JSONSchema.from(dictionary: [
            "type": "array",
            "items": ["type": "number"]
        ])
        XCTAssertEqual(schema.type, .array)
        XCTAssertEqual(schema.items?.type, .number)
    }

    func testAdditionalPropertiesHonoredWhenExplicit() throws {
        let permissive = try JSONSchema.from(dictionary: [
            "type": "object", "additionalProperties": true
        ])
        XCTAssertEqual(permissive.additionalProperties, true)

        let strict = try JSONSchema.from(dictionary: [
            "type": "object", "additionalProperties": false
        ])
        XCTAssertEqual(strict.additionalProperties, false)
    }

    func testEnumOfStrings() throws {
        let schema = try JSONSchema.from(dictionary: [
            "type": "string",
            "enum": ["a", "b", "c"]
        ])
        XCTAssertEqual(schema.enum, ["a", "b", "c"])
    }

    func testEnumWithNullEntryKeepsStringsOnly() throws {
        // enum as [Any?] (e.g. ["x", nil]) -> compactMap to strings.
        let schema = try JSONSchema.from(dictionary: [
            "type": "string",
            "enum": ["x", nil, "y"] as [Any?]
        ])
        XCTAssertEqual(schema.enum, ["x", "y"])
    }

    func testRefPassThrough() throws {
        let schema = try JSONSchema.from(dictionary: ["$ref": "#/defs/Thing"])
        XCTAssertEqual(schema.ref, "#/defs/Thing")
    }

    func testInvalidPropertyValueThrows() {
        // A property whose value isn't a dictionary is rejected.
        XCTAssertThrowsError(try JSONSchema.from(dictionary: [
            "type": "object",
            "properties": ["bad": "not-a-schema"]
        ])) { error in
            guard case JSONSchemaConversionError.invalidSchema = error else {
                return XCTFail("expected .invalidSchema, got \(error)")
            }
        }
    }

    // MARK: - AnthropicSchemaConverter.convertJSONSchemaToDictionary

    func testConvertScalarToDictionary() {
        let schema = JSONSchema(type: .string, description: "label")
        let dict = AnthropicSchemaConverter.convertJSONSchemaToDictionary(schema)
        XCTAssertEqual(dict["type"] as? String, "string")
        XCTAssertEqual(dict["description"] as? String, "label")
    }

    func testConvertObjectWithPropertiesAndRequired() {
        let schema = JSONSchema(
            type: .object,
            properties: ["name": JSONSchema(type: .string)],
            required: ["name"]
        )
        let dict = AnthropicSchemaConverter.convertJSONSchemaToDictionary(schema)
        XCTAssertEqual(dict["type"] as? String, "object")
        let props = try? XCTUnwrap(dict["properties"] as? [String: Any])
        let nameProp = props?["name"] as? [String: Any]
        XCTAssertEqual(nameProp?["type"] as? String, "string")
        XCTAssertEqual(dict["required"] as? [String], ["name"])
    }

    func testConvertArrayItemsRecursively() {
        let schema = JSONSchema(type: .array, items: JSONSchema(type: .integer))
        let dict = AnthropicSchemaConverter.convertJSONSchemaToDictionary(schema)
        XCTAssertEqual(dict["type"] as? String, "array")
        let items = dict["items"] as? [String: Any]
        XCTAssertEqual(items?["type"] as? String, "integer")
    }

    func testUnionTypeCollapsesToFirstNonNull() {
        // Anthropic doesn't support unions; converter emits the first non-null type.
        let schema = JSONSchema(type: .union([.null, .string]))
        let dict = AnthropicSchemaConverter.convertJSONSchemaToDictionary(schema)
        XCTAssertEqual(dict["type"] as? String, "string")
    }

    func testUnionOfOnlyNullDefaultsToString() {
        let schema = JSONSchema(type: .union([.null]))
        let dict = AnthropicSchemaConverter.convertJSONSchemaToDictionary(schema)
        XCTAssertEqual(dict["type"] as? String, "string",
                       "an all-null union has no non-null member; converter falls back to string")
    }

    func testConvertEnumAndAdditionalProperties() {
        let schema = JSONSchema(type: .string, additionalProperties: false, enum: ["x", "y"])
        let dict = AnthropicSchemaConverter.convertJSONSchemaToDictionary(schema)
        XCTAssertEqual(dict["enum"] as? [String], ["x", "y"])
        XCTAssertEqual(dict["additionalProperties"] as? Bool, false)
    }

    // MARK: - jsonSchemaTypeToString

    func testTypeToStringMapping() {
        XCTAssertEqual(AnthropicSchemaConverter.jsonSchemaTypeToString(.string), "string")
        XCTAssertEqual(AnthropicSchemaConverter.jsonSchemaTypeToString(.number), "number")
        XCTAssertEqual(AnthropicSchemaConverter.jsonSchemaTypeToString(.integer), "integer")
        XCTAssertEqual(AnthropicSchemaConverter.jsonSchemaTypeToString(.boolean), "boolean")
        XCTAssertEqual(AnthropicSchemaConverter.jsonSchemaTypeToString(.object), "object")
        XCTAssertEqual(AnthropicSchemaConverter.jsonSchemaTypeToString(.array), "array")
        XCTAssertEqual(AnthropicSchemaConverter.jsonSchemaTypeToString(.null), "null")
    }

    // MARK: - Round trip (dict -> JSONSchema -> dict)

    func testRoundTripObjectSchema() throws {
        let original: [String: Any] = [
            "type": "object",
            "properties": [
                "title": ["type": "string"],
                "count": ["type": "integer"]
            ],
            "required": ["title"]
        ]
        let schema = try JSONSchema.from(dictionary: original)
        let dict = AnthropicSchemaConverter.convertJSONSchemaToDictionary(schema)
        XCTAssertEqual(dict["type"] as? String, "object")
        XCTAssertEqual(dict["required"] as? [String], ["title"])
        let props = dict["properties"] as? [String: Any]
        XCTAssertEqual((props?["title"] as? [String: Any])?["type"] as? String, "string")
        XCTAssertEqual((props?["count"] as? [String: Any])?["type"] as? String, "integer")
    }
}
