import Foundation
import SwiftOpenAI
struct ToolDefinition: Codable, Sendable {
    let name: String
    let description: String
    let parameters: ToolParameters
    let strict: Bool
    let displayMessage: String?
    init(
        name: String,
        description: String,
        parameters: ToolParameters,
        strict: Bool = true,
        displayMessage: String? = nil
    ) {
        self.name = name
        self.description = description
        self.parameters = parameters
        self.strict = strict
        self.displayMessage = displayMessage
    }
}
struct ToolParameters: Codable, Sendable {
    let type: String
    let properties: [String: ToolProperty]
    let required: [String]?
}
struct ToolProperty: Codable, Sendable {
    let type: String
    let description: String?
    let items: ToolArrayItems?
    let properties: [String: ToolProperty]?
    let required: [String]?
    let allowAdditionalProperties: Bool?
    let nullable: Bool
    init(
        type: String,
        description: String? = nil,
        items: ToolArrayItems? = nil,
        properties: [String: ToolProperty]? = nil,
        required: [String]? = nil,
        allowAdditionalProperties: Bool? = nil,
        nullable: Bool = false
    ) {
        self.type = type
        self.description = description
        self.items = items
        self.properties = properties
        self.required = required
        self.allowAdditionalProperties = allowAdditionalProperties
        self.nullable = nullable
    }
}
struct ToolArrayItems: Codable, Sendable {
    let type: String
    let description: String?
    let properties: [String: ToolProperty]?
    let required: [String]?
    let allowAdditionalProperties: Bool?
    init(
        type: String,
        description: String? = nil,
        properties: [String: ToolProperty]? = nil,
        required: [String]? = nil,
        allowAdditionalProperties: Bool? = nil
    ) {
        self.type = type
        self.description = description
        self.properties = properties
        self.required = required
        self.allowAdditionalProperties = allowAdditionalProperties
    }
}
extension ToolDefinition {
    var asFunctionTool: Tool {
        .function(
            Tool.FunctionTool(
                name: name,
                parameters: parameters.asJSONSchema(description: description),
                strict: strict,
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
        let schemaType = resolvedSchemaType()
        return JSONSchema(
            type: finalSchemaType(basedOn: schemaType),
            description: description,
            properties: properties?.mapValues { $0.asJSONSchema() },
            items: items?.asJSONSchema(),
            required: required,
            additionalProperties: resolvedAdditionalProperties
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
    func finalSchemaType(basedOn baseType: JSONSchemaType) -> JSONSchemaType {
        guard nullable else {
            return baseType
        }
        switch baseType {
        case .union(let types):
            if types.contains(.null) {
                return baseType
            } else {
                return .union(types + [.null])
            }
        default:
            return .union([baseType, .null])
        }
    }
    var resolvedAdditionalProperties: Bool {
        return allowAdditionalProperties ?? false
    }
}
private extension ToolArrayItems {
    func asJSONSchema() -> JSONSchema {
        JSONSchema(
            type: resolvedSchemaType(),
            description: description,
            properties: properties?.mapValues { $0.asJSONSchema() },
            required: required,
            additionalProperties: resolvedAdditionalProperties
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
    var resolvedAdditionalProperties: Bool {
        return allowAdditionalProperties ?? false
    }
}
