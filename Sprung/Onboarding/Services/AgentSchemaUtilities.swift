//
//  AgentSchemaUtilities.swift
//  Sprung
//
//  Shared utilities for building JSON schemas for agent tools.
//  Eliminates duplicate buildJSONSchema implementations across agents.
//

import Foundation
import SwiftOpenAI

// MARK: - Agent Schema Utilities

/// Shared utilities for building JSON schemas from dictionary representations.
/// Used by all multi-turn agents for tool registration with OpenRouter.
enum AgentSchemaUtilities {
    /// Build JSONSchema from dictionary representation.
    /// Recursively processes nested objects and arrays.
    static func buildJSONSchema(from dict: [String: Any]) -> JSONSchema {
        let typeStr = dict["type"] as? String ?? "object"
        let desc = dict["description"] as? String
        let enumValues = dict["enum"] as? [String]

        let schemaType: JSONSchemaType
        switch typeStr {
        case "string": schemaType = .string
        case "integer": schemaType = .integer
        case "number": schemaType = .number
        case "boolean": schemaType = .boolean
        case "array": schemaType = .array
        case "object": schemaType = .object
        default: schemaType = .string
        }

        var properties: [String: JSONSchema]? = nil
        if let propsDict = dict["properties"] as? [String: [String: Any]] {
            var propSchemas: [String: JSONSchema] = [:]
            for (key, propSpec) in propsDict {
                propSchemas[key] = buildJSONSchema(from: propSpec)
            }
            properties = propSchemas
        }

        var items: JSONSchema? = nil
        if schemaType == .array, let itemsDict = dict["items"] as? [String: Any] {
            items = buildJSONSchema(from: itemsDict)
        }

        let required = dict["required"] as? [String]
        let additionalProps = dict["additionalProperties"] as? Bool ?? false

        return JSONSchema(
            type: schemaType,
            description: desc,
            properties: properties,
            items: items,
            required: required,
            additionalProperties: additionalProps,
            enum: enumValues
        )
    }
}
