//
//  LLMSchemaBuilder.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 5/20/25.
//

import Foundation
import SwiftOpenAI

/// Centralized utility for building JSON schemas for LLM structured outputs
/// This eliminates duplicated schema generation logic across the codebase
class LLMSchemaBuilder {
    // MARK: - Schema generation for common types
    
    /// Creates a JSONSchema for a Decodable type
    /// - Parameter type: The Decodable type
    /// - Returns: A JSONSchema object for the type
    static func createSchema(for type: Decodable.Type) -> SwiftOpenAI.JSONSchema {
        if type == RevisionsContainer.self {
            return createRevisionsContainerSchema()
        }
        
        if type == BestCoverLetterResponse.self {
            return createBestCoverLetterResponseSchema()
        }
        
        // Fallback - empty schema
        return SwiftOpenAI.JSONSchema(type: .object)
    }
    
    /// Creates a JSONSchema for RevisionsContainer type
    /// - Returns: A JSONSchema for RevisionsContainer
    private static func createRevisionsContainerSchema() -> SwiftOpenAI.JSONSchema {
        return SwiftOpenAI.JSONSchema(
            type: .object,
            properties: [
                "revArray": SwiftOpenAI.JSONSchema(
                    type: .array,
                    items: SwiftOpenAI.JSONSchema(
                        type: .object,
                        properties: [
                            "id": SwiftOpenAI.JSONSchema(type: .string),
                            "oldValue": SwiftOpenAI.JSONSchema(type: .string),
                            "newValue": SwiftOpenAI.JSONSchema(type: .string),
                            "valueChanged": SwiftOpenAI.JSONSchema(type: .boolean),
                            "why": SwiftOpenAI.JSONSchema(type: .string),
                            "isTitleNode": SwiftOpenAI.JSONSchema(type: .boolean),
                            "treePath": SwiftOpenAI.JSONSchema(type: .string)
                        ],
                        required: ["id", "oldValue", "newValue", "valueChanged", "why", "isTitleNode", "treePath"]
                    )
                )
            ],
            required: ["revArray"]
        )
    }
    
    /// Creates a JSONSchema for BestCoverLetterResponse type
    /// - Returns: A JSONSchema for BestCoverLetterResponse
    private static func createBestCoverLetterResponseSchema() -> SwiftOpenAI.JSONSchema {
        return SwiftOpenAI.JSONSchema(
            type: .object,
            properties: [
                "strengthAndVoiceAnalysis": SwiftOpenAI.JSONSchema(
                    type: .string,
                    description: "Brief summary ranking/assessment of each letter's strength and voice"
                ),
                "bestLetterUuid": SwiftOpenAI.JSONSchema(
                    type: .string,
                    description: "UUID of the selected best cover letter"
                ),
                "verdict": SwiftOpenAI.JSONSchema(
                    type: .string,
                    description: "Reason for the ultimate choice"
                )
            ],
            required: ["strengthAndVoiceAnalysis", "bestLetterUuid", "verdict"]
        )
    }
    
    // MARK: - Schema parsing from JSON
    
    /// Parses a JSONSchema string into a SwiftOpenAI.JSONSchema object
    /// - Parameter jsonString: The schema as a JSON string
    /// - Returns: The parsed JSONSchema, or nil if parsing fails
    static func parseJSONSchemaString(_ jsonString: String) -> SwiftOpenAI.JSONSchema? {
        guard let data = jsonString.data(using: .utf8) else {
            Logger.error("Failed to convert schema JSON string to data")
            return nil
        }
        
        do {
            // Parse JSON into dictionary
            let jsonDict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let dict = jsonDict else {
                Logger.error("Failed to parse schema JSON into dictionary")
                return nil
            }
            
            // Extract type
            let typeString = dict["type"] as? String
            let type = schemaTypeFrom(typeString)
            
            // Extract description
            let description = dict["description"] as? String
            
            // Extract properties if this is an object
            var properties: [String: SwiftOpenAI.JSONSchema]?
            if typeString == "object", let props = dict["properties"] as? [String: [String: Any]] {
                properties = [:]
                for (key, propDict) in props {
                    // Get property type
                    let propType = schemaTypeFrom(propDict["type"] as? String)
                    
                    // Parse subproperties recursively if this is an object
                    var subProperties: [String: SwiftOpenAI.JSONSchema]?
                    if propDict["type"] as? String == "object", 
                       let subProps = propDict["properties"] as? [String: [String: Any]] {
                        subProperties = [:]
                        for (subKey, subPropDict) in subProps {
                            let subPropType = schemaTypeFrom(subPropDict["type"] as? String)
                            subProperties?[subKey] = SwiftOpenAI.JSONSchema(
                                type: subPropType,
                                description: subPropDict["description"] as? String
                            )
                        }
                    }
                    
                    // Parse items if this is an array
                    var items: SwiftOpenAI.JSONSchema?
                    if propDict["type"] as? String == "array", 
                       let itemsDict = propDict["items"] as? [String: Any] {
                        let itemType = schemaTypeFrom(itemsDict["type"] as? String)
                        items = SwiftOpenAI.JSONSchema(
                            type: itemType,
                            description: itemsDict["description"] as? String
                        )
                    }
                    
                    // Create property schema
                    properties?[key] = SwiftOpenAI.JSONSchema(
                        type: propType,
                        description: propDict["description"] as? String,
                        properties: subProperties,
                        items: items,
                        required: propDict["required"] as? [String]
                    )
                }
            }
            
            // Extract items if this is an array
            var items: SwiftOpenAI.JSONSchema?
            if typeString == "array", let itemsDict = dict["items"] as? [String: Any] {
                let itemType = schemaTypeFrom(itemsDict["type"] as? String)
                items = SwiftOpenAI.JSONSchema(
                    type: itemType,
                    description: itemsDict["description"] as? String
                )
            }
            
            // Build the schema
            return SwiftOpenAI.JSONSchema(
                type: type,
                description: description,
                properties: properties,
                items: items,
                required: dict["required"] as? [String],
                additionalProperties: dict["additionalProperties"] as? Bool ?? false
            )
        } catch {
            Logger.error("Error parsing JSON schema: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Converts a string type to SwiftOpenAI.JSONSchemaType
    /// - Parameter typeString: The string type
    /// - Returns: The corresponding JSONSchemaType, or nil if not recognized
    private static func schemaTypeFrom(_ typeString: String?) -> SwiftOpenAI.JSONSchemaType? {
        guard let typeString = typeString else { return nil }
        
        switch typeString {
        case "string": return .string
        case "object": return .object
        case "array": return .array
        case "boolean": return .boolean
        case "integer": return .integer
        case "number": return .number
        case "null": return .null
        default: return nil
        }
    }
    
    // MARK: - Schema creation for SwiftOpenAI
    
    /// Creates a SwiftOpenAI.ResponseFormat for structured JSON output
    /// - Parameters:
    ///   - responseType: The type to use for structured output
    ///   - jsonSchema: Optional JSON schema string to use
    /// - Returns: The appropriate ResponseFormat for the query
    static func createResponseFormat(for responseType: Decodable.Type?, jsonSchema: String? = nil) -> SwiftOpenAI.ResponseFormat? {
        guard let responseType = responseType else {
            return nil
        }
        
        // If a specific JSON schema was provided, parse and use it
        if let jsonSchema = jsonSchema, let schema = parseJSONSchemaString(jsonSchema) {
            return .jsonSchema(
                SwiftOpenAI.JSONSchemaResponseFormat(
                    name: String(describing: responseType),
                    strict: true,
                    schema: schema
                )
            )
        }
        // If we have a built-in schema for this type, use it
        else if createSchema(for: responseType).type != nil {
            // Get schema for the response type
            let schema = createSchema(for: responseType)
            return .jsonSchema(
                SwiftOpenAI.JSONSchemaResponseFormat(
                    name: String(describing: responseType),
                    strict: true,
                    schema: schema
                )
            )
        }
        // Otherwise use the simpler JSON object format
        else {
            return .jsonObject
        }
    }
}
