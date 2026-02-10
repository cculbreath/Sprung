//
//  AnthropicSchemaConverter.swift
//  Sprung
//
//  Stateless utilities for converting tool schemas to Anthropic format.
//  Used by any agent that communicates with the Anthropic Messages API.
//

import Foundation
import SwiftOpenAI

/// Stateless utilities for converting tool schemas to Anthropic format
enum AnthropicSchemaConverter {
    /// Convert a SwiftOpenAI function tool definition to an AnthropicTool
    static func convertToAnthropicTool(_ funcTool: Tool.FunctionTool) -> AnthropicTool {
        let inputSchema = convertJSONSchemaToDictionary(funcTool.parameters)
        return .function(AnthropicFunctionTool(
            name: funcTool.name,
            description: funcTool.description,
            inputSchema: inputSchema
        ))
    }

    /// Convert JSONSchema to [String: Any] dictionary for Anthropic's input_schema
    static func convertJSONSchemaToDictionary(_ schema: JSONSchema) -> [String: Any] {
        var result: [String: Any] = [:]

        // Type - convert JSONSchemaType to string
        if let schemaType = schema.type {
            result["type"] = jsonSchemaTypeToString(schemaType)
        }

        // Properties
        if let properties = schema.properties {
            var propsDict: [String: Any] = [:]
            for (key, propSchema) in properties {
                propsDict[key] = convertJSONSchemaToDictionary(propSchema)
            }
            result["properties"] = propsDict
        }

        // Required
        if let required = schema.required {
            result["required"] = required
        }

        // Description
        if let description = schema.description {
            result["description"] = description
        }

        // Items (for arrays)
        if let items = schema.items {
            result["items"] = convertJSONSchemaToDictionary(items)
        }

        // Enum (JSONSchema uses backtick `enum`)
        if let enumValues = schema.`enum` {
            result["enum"] = enumValues
        }

        // Additional properties (simple Bool? in JSONSchema)
        if let additionalProps = schema.additionalProperties {
            result["additionalProperties"] = additionalProps
        }

        return result
    }

    /// Convert JSONSchemaType to its string representation
    static func jsonSchemaTypeToString(_ type: JSONSchemaType) -> String {
        switch type {
        case .string: return "string"
        case .number: return "number"
        case .integer: return "integer"
        case .boolean: return "boolean"
        case .object: return "object"
        case .array: return "array"
        case .null: return "null"
        case .union(let types):
            // For union types, return the first non-null type
            // (Anthropic doesn't support union types directly)
            if let firstType = types.first(where: { $0 != .null }) {
                return jsonSchemaTypeToString(firstType)
            }
            return "string"
        }
    }

    /// Convert an AgentTool's [String: Any] schema directly to AnthropicTool.
    /// Convenience for agents using AgentTool protocol — bypasses SwiftOpenAI intermediate types.
    static func anthropicTool<T: AgentTool>(from tool: T.Type) -> AnthropicTool {
        .function(AnthropicFunctionTool(
            name: tool.name,
            description: tool.description,
            inputSchema: tool.parametersSchema
        ))
    }
}
