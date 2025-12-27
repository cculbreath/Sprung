//
//  SchemaLoader.swift
//  Sprung
//
//  Utility for loading JSON schemas from resource files.
//

import Foundation
import SwiftOpenAI

enum SchemaLoader {
    /// Loads a JSON schema from a resource file and converts it to SwiftOpenAI's JSONSchema format.
    /// - Parameter resourceName: The name of the JSON file (without extension) in Resources/DiscoverySchemas/
    /// - Returns: A JSONSchema object constructed from the JSON file
    static func loadSchema(resourceName: String) -> JSONSchema {
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "json", subdirectory: "DiscoverySchemas") else {
            fatalError("Schema resource '\(resourceName).json' not found in DiscoverySchemas directory")
        }

        guard let data = try? Data(contentsOf: url) else {
            fatalError("Failed to load data from schema resource '\(resourceName).json'")
        }

        guard let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []),
              let schemaDict = jsonObject as? [String: Any] else {
            fatalError("Failed to parse schema resource '\(resourceName).json' as JSON dictionary")
        }

        return parseJSONSchemaDict(schemaDict)
    }

    /// Recursively converts a JSON dictionary into a JSONSchema object.
    private static func parseJSONSchemaDict(_ dict: [String: Any]) -> JSONSchema {
        // Extract type
        let typeValue = dict["type"] as? String
        let schemaType: JSONSchemaType = {
            switch typeValue {
            case "object": return .object
            case "array": return .array
            case "string": return .string
            case "integer": return .integer
            case "number": return .number
            case "boolean": return .boolean
            default: return .object
            }
        }()

        // Extract optional fields
        let description = dict["description"] as? String
        let enumValues = dict["enum"] as? [String]

        // Parse properties (for object types)
        var properties: [String: JSONSchema]?
        if let propsDict = dict["properties"] as? [String: [String: Any]] {
            properties = propsDict.mapValues { parseJSONSchemaDict($0) }
        }

        // Parse items (for array types)
        var items: JSONSchema?
        if let itemsDict = dict["items"] as? [String: Any] {
            items = parseJSONSchemaDict(itemsDict)
        }

        // Parse required fields
        let required = dict["required"] as? [String]

        // Parse additionalProperties (defaults to false for structured outputs)
        let additionalProperties = dict["additionalProperties"] as? Bool ?? false

        // Construct the JSONSchema (parameter order: type, description, properties, items, required, additionalProperties, enum)
        return JSONSchema(
            type: schemaType,
            description: description,
            properties: properties,
            items: items,
            required: required,
            additionalProperties: additionalProperties,
            enum: enumValues
        )
    }
}
