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
        
        // Add support for ReorderSkillsResponse type
        if type == ReorderSkillsResponse.self {
            return createReorderSkillsResponseSchema()
        }
        
        // Add support for FixFitsResponseContainer type
        if type == FixFitsResponseContainer.self {
            return createFixFitsResponseContainerSchema()
        }
        
        // Add support for ContentsFitResponse type
        if type == ContentsFitResponse.self {
            return createContentsFitResponseSchema()
        }
        
        // Add support for JobRecommendation type
        if let typeName = String(describing: type).components(separatedBy: ".").last,
           typeName == "JobRecommendation" {
            return createJobRecommendationSchema()
        }
        
        // Add support for ClarifyingQuestionsRequest type
        if type == ClarifyingQuestionsRequest.self {
            return createClarifyingQuestionsRequestSchema()
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
                    description: "Array of revision nodes for the resume",
                    items: SwiftOpenAI.JSONSchema(
                        type: .object,
                        properties: [
                            "id": SwiftOpenAI.JSONSchema(
                                type: .string,
                                description: "A unique string identifier for the revision"
                            ),
                            "oldValue": SwiftOpenAI.JSONSchema(
                                type: .string,
                                description: "The original text content from the resume"
                            ),
                            "newValue": SwiftOpenAI.JSONSchema(
                                type: .string,
                                description: "The suggested replacement text content"
                            ),
                            "valueChanged": SwiftOpenAI.JSONSchema(
                                type: .boolean,
                                description: "Whether the value has been changed (true if oldValue != newValue)"
                            ),
                            "why": SwiftOpenAI.JSONSchema(
                                type: .string,
                                description: "Explanation for why this change was suggested"
                            ),
                            "isTitleNode": SwiftOpenAI.JSONSchema(
                                type: .boolean,
                                description: "Whether this node represents a section title"
                            ),
                            "treePath": SwiftOpenAI.JSONSchema(
                                type: .string,
                                description: "Path to the node in the document tree structure"
                            )
                        ],
                        required: ["id", "oldValue", "newValue", "valueChanged", "why", "isTitleNode", "treePath"],
                        additionalProperties: false
                    )
                )
            ],
            required: ["revArray"],
            additionalProperties: false
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
    
    /// Creates a JSONSchema for JobRecommendation type
    /// - Returns: A JSONSchema for JobRecommendation
    private static func createJobRecommendationSchema() -> SwiftOpenAI.JSONSchema {
        return SwiftOpenAI.JSONSchema(
            type: .object,
            properties: [
                "recommendedJobId": SwiftOpenAI.JSONSchema(
                    type: .string,
                    description: "The exact UUID string from the job listing to recommend"
                ),
                "reason": SwiftOpenAI.JSONSchema(
                    type: .string,
                    description: "A brief explanation of why this job is the best match"
                )
            ],
            required: ["recommendedJobId", "reason"],
            additionalProperties: false
        )
    }
    
    /// Creates a JSONSchema for ClarifyingQuestionsRequest type
    /// - Returns: A JSONSchema for ClarifyingQuestionsRequest
    private static func createClarifyingQuestionsRequestSchema() -> SwiftOpenAI.JSONSchema {
        return SwiftOpenAI.JSONSchema(
            type: .object,
            properties: [
                "questions": SwiftOpenAI.JSONSchema(
                    type: .array,
                    description: "Array of clarifying questions (up to 3)",
                    items: SwiftOpenAI.JSONSchema(
                        type: .object,
                        properties: [
                            "id": SwiftOpenAI.JSONSchema(
                                type: .string,
                                description: "Unique identifier for the question"
                            ),
                            "question": SwiftOpenAI.JSONSchema(
                                type: .string,
                                description: "The clarifying question to ask"
                            )
                        ],
                        required: ["id", "question"],
                        additionalProperties: false
                    )
                ),
                "proceedWithRevisions": SwiftOpenAI.JSONSchema(
                    type: .boolean,
                    description: "True if proceeding without questions, false if questions are needed"
                )
            ],
            required: ["questions", "proceedWithRevisions"],
            additionalProperties: false
        )
    }
    
    /// Creates a JSONSchema for ReorderSkillsResponse type
    /// - Returns: A JSONSchema for ReorderSkillsResponse
    private static func createReorderSkillsResponseSchema() -> SwiftOpenAI.JSONSchema {
        return SwiftOpenAI.JSONSchema(
            type: .object,
            properties: [
                "reordered_skills_and_expertise": SwiftOpenAI.JSONSchema(
                    type: .array,
                    description: "Array of reordered skill items with their new positions and reasons",
                    items: SwiftOpenAI.JSONSchema(
                        type: .object,
                        properties: [
                            "id": SwiftOpenAI.JSONSchema(
                                type: .string,
                                description: "The exact UUID string from the input skill"
                            ),
                            "originalValue": SwiftOpenAI.JSONSchema(
                                type: .string,
                                description: "The original skill name from the input"
                            ),
                            "newPosition": SwiftOpenAI.JSONSchema(
                                type: .integer,
                                description: "The recommended new position (0-based index)"
                            ),
                            "reasonForReordering": SwiftOpenAI.JSONSchema(
                                type: .string,
                                description: "Brief explanation of why this position is appropriate"
                            )
                        ],
                        required: ["id", "originalValue", "newPosition", "reasonForReordering"],
                        additionalProperties: false
                    )
                )
            ],
            required: ["reordered_skills_and_expertise"],
            additionalProperties: false
        )
    }
    
    /// Creates a JSONSchema for FixFitsResponseContainer type
    /// - Returns: A JSONSchema for FixFitsResponseContainer
    private static func createFixFitsResponseContainerSchema() -> SwiftOpenAI.JSONSchema {
        return SwiftOpenAI.JSONSchema(
            type: .object,
            properties: [
                "revised_skills_and_expertise": SwiftOpenAI.JSONSchema(
                    type: .array,
                    description: "An array of objects, each representing a skill or expertise item with its original ID and revised content.",
                    items: SwiftOpenAI.JSONSchema(
                        type: .object,
                        properties: [
                            "id": SwiftOpenAI.JSONSchema(
                                type: .string,
                                description: "The original ID of the TreeNode for the skill."
                            ),
                            "newValue": SwiftOpenAI.JSONSchema(
                                type: .string,
                                description: "The revised content for the skill/expertise item. If no change, this should be the same as originalValue."
                            ),
                            "originalValue": SwiftOpenAI.JSONSchema(
                                type: .string,
                                description: "The original content of the skill/expertise item (echoed back)."
                            ),
                            "treePath": SwiftOpenAI.JSONSchema(
                                type: .string,
                                description: "The original treePath of the skill TreeNode (echoed back)."
                            ),
                            "isTitleNode": SwiftOpenAI.JSONSchema(
                                type: .boolean,
                                description: "Indicates if this skill entry is a title/heading (echoed back)."
                            )
                        ],
                        required: ["id", "newValue", "originalValue", "treePath", "isTitleNode"],
                        additionalProperties: false
                    )
                )
            ],
            required: ["revised_skills_and_expertise"],
            additionalProperties: false
        )
    }
    
    /// Creates a JSONSchema for ContentsFitResponse type
    /// - Returns: A JSONSchema for ContentsFitResponse
    private static func createContentsFitResponseSchema() -> SwiftOpenAI.JSONSchema {
        return SwiftOpenAI.JSONSchema(
            type: .object,
            properties: [
                "contentsFit": SwiftOpenAI.JSONSchema(
                    type: .boolean,
                    description: "True if the content fits within its designated box without overflowing or overlapping other elements, false otherwise."
                ),
                "overflow_line_count": SwiftOpenAI.JSONSchema(
                    type: .integer,
                    description: "Estimated number of text lines that are overflowing or overlapping the content below. 0 if contentsFit is true, or if text overlaps bounding boxes but no actual text lines overflow."
                )
            ],
            required: ["contentsFit", "overflow_line_count"],
            additionalProperties: false
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
    
    /// Creates a ResponseFormat for SwiftOpenAI
    /// - Parameters:
    ///   - responseType: The type to use for structured output
    ///   - jsonSchema: Optional JSON schema string to use
    /// - Returns: The appropriate ResponseFormat for the query
    static func createResponseFormat(for responseType: Decodable.Type?, jsonSchema: String? = nil) -> SwiftOpenAI.ResponseFormat? {
        guard let responseType = responseType else {
            return nil
        }
        
        // Get type name for logging
        let typeName = String(describing: responseType)
        Logger.debug("Creating response format for type: \(typeName)")
        
        // If a specific JSON schema was provided, parse and use it
        if let jsonSchema = jsonSchema, let schema = parseJSONSchemaString(jsonSchema) {
            Logger.debug("Using provided JSON schema for \(typeName)")
            return .jsonSchema(
                SwiftOpenAI.JSONSchemaResponseFormat(
                    name: typeName,
                    strict: true,
                    schema: schema
                )
            )
        }
        // If we have a built-in schema for this type, use it
        else if createSchema(for: responseType).type != nil {
            // Get schema for the response type
            let schema = createSchema(for: responseType)
            Logger.debug("Using built-in schema for \(typeName)")
            return .jsonSchema(
                SwiftOpenAI.JSONSchemaResponseFormat(
                    name: typeName,
                    strict: true,
                    schema: schema
                )
            )
        }
        // Otherwise use the simpler JSON object format
        else {
            Logger.debug("Using generic JSON object format for \(typeName)")
            return .jsonObject
        }
    }
}
