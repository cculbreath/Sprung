import Foundation
import SwiftOpenAI

struct ToolDefinition: Codable, Sendable {
    let name: String
    let description: String
    let parameters: ToolParameters
}

struct ToolParameters: Codable, Sendable {
    let type: String
    let properties: [String: ToolProperty]
    let required: [String]?
}

struct ToolProperty: Codable, Sendable {
    let type: String
    let description: String?
}

extension ToolDefinition {
    var asFunctionTool: Tool {
        .function(
            Tool.FunctionTool(
                name: name,
                parameters: parameters.asJSONSchema(description: description),
                strict: true,
                description: description
            )
        )
    }
}

private extension ToolParameters {
    func asJSONSchema(description: String?) -> JSONSchema {
        let propertySchemas = properties.reduce(into: [String: JSONSchema]()) { result, entry in
            result[entry.key] = entry.value.asJSONSchema()
        }

        return JSONSchema(
            type: .object,
            description: description,
            properties: propertySchemas,
            required: required,
            additionalProperties: false
        )
    }
}

private extension ToolProperty {
    func asJSONSchema() -> JSONSchema {
        JSONSchema(
            type: resolvedSchemaType(),
            description: description,
            additionalProperties: shouldAllowAdditionalProperties
        )
    }

    func resolvedSchemaType() -> JSONSchemaType {
        switch type.lowercased() {
        case "string":
            return .string
        case "number":
            return .number
        case "integer":
            return .integer
        case "boolean":
            return .boolean
        case "array":
            return .array
        case "object":
            return .object
        case "null":
            return .null
        default:
            return .string
        }
    }

    var shouldAllowAdditionalProperties: Bool {
        resolvedSchemaType() == .object
    }
}
