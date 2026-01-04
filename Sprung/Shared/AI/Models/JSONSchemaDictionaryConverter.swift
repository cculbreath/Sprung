//
//  JSONSchemaDictionaryConverter.swift
//  Sprung
//
//  Converts [String: Any] dictionary-based JSON schemas to SwiftOpenAI's JSONSchema type.
//  This enables polymorphic structured output across different LLM backends.
//

import Foundation
import SwiftOpenAI

enum JSONSchemaConversionError: Error, LocalizedError {
    case invalidType(String)
    case invalidSchema(String)

    var errorDescription: String? {
        switch self {
        case .invalidType(let type):
            return "Invalid JSON schema type: \(type)"
        case .invalidSchema(let message):
            return "Invalid JSON schema: \(message)"
        }
    }
}

extension JSONSchema {
    /// Creates a JSONSchema from a dictionary representation.
    /// Supports the standard JSON Schema subset used by OpenAI's structured output.
    ///
    /// Example:
    /// ```swift
    /// let dict: [String: Any] = [
    ///     "type": "object",
    ///     "properties": [
    ///         "name": ["type": "string"],
    ///         "age": ["type": "integer"]
    ///     ],
    ///     "required": ["name"]
    /// ]
    /// let schema = try JSONSchema.from(dictionary: dict)
    /// ```
    static func from(dictionary: [String: Any]) throws -> JSONSchema {
        // Parse type
        var schemaType: JSONSchemaType?
        if let typeString = dictionary["type"] as? String {
            schemaType = try parseType(typeString)
        } else if let typeArray = dictionary["type"] as? [String] {
            // Union type e.g. ["string", "null"]
            let types = try typeArray.map { try parseType($0) }
            schemaType = .union(types)
        }

        // Parse description
        let description = dictionary["description"] as? String

        // Parse properties (recursive)
        var properties: [String: JSONSchema]?
        if let propsDict = dictionary["properties"] as? [String: Any] {
            properties = [:]
            for (key, value) in propsDict {
                guard let propDict = value as? [String: Any] else {
                    throw JSONSchemaConversionError.invalidSchema("Property '\(key)' is not a valid schema object")
                }
                properties?[key] = try JSONSchema.from(dictionary: propDict)
            }
        }

        // Parse items (for arrays, recursive)
        var items: JSONSchema?
        if let itemsDict = dictionary["items"] as? [String: Any] {
            items = try JSONSchema.from(dictionary: itemsDict)
        }

        // Parse required
        let required = dictionary["required"] as? [String]

        // Parse additionalProperties (default to false for strict mode)
        let additionalProperties = dictionary["additionalProperties"] as? Bool ?? false

        // Parse enum
        let enumValues = dictionary["enum"] as? [String]

        // Parse $ref
        let ref = dictionary["$ref"] as? String

        return JSONSchema(
            type: schemaType,
            description: description,
            properties: properties,
            items: items,
            required: required,
            additionalProperties: additionalProperties,
            enum: enumValues,
            ref: ref
        )
    }

    private static func parseType(_ typeString: String) throws -> JSONSchemaType {
        switch typeString.lowercased() {
        case "string": return .string
        case "number": return .number
        case "integer": return .integer
        case "boolean": return .boolean
        case "object": return .object
        case "array": return .array
        case "null": return .null
        default:
            throw JSONSchemaConversionError.invalidType(typeString)
        }
    }
}
