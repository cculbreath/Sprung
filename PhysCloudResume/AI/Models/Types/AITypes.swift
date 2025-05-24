//
//  AITypes.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 5/20/25.
//

import Foundation

/// This file defines types that are used in the AI protocol interfaces
/// These types abstract away the implementation details of specific AI libraries

/// Namespace for chat completion parameter types
/// Acts as a wrapper for response format types used in chat completions
public enum AIResponseFormat {
    /// Plain text response
    case text
    /// JSON object response
    case jsonObject
    /// JSON schema structured response
    case jsonSchema(AIJSONSchemaFormat)
    
    /// JSON schema format for structured responses
    public struct AIJSONSchemaFormat {
        /// The name of the schema
        public let name: String
        /// Whether to enforce strict schema validation
        public let strict: Bool
        /// The schema definition as a JSON object
        public let schema: [String: Any]
        
        public init(name: String, strict: Bool, schema: [String: Any]) {
            self.name = name
            self.strict = strict
            self.schema = schema
        }
    }
}

/// Namespace for JSON schema types used in structured outputs
public enum AIJSONSchema {
    /// Represents a JSON schema data type
    public enum SchemaType {
        case string
        case object
        case array
        case boolean
        case integer
        case number
    }
    
    /// Creates a JSON schema object with properties
    /// - Parameters:
    ///   - type: The schema type
    ///   - description: Optional description
    ///   - properties: Dictionary of property schemas
    ///   - items: Schema for array items
    ///   - required: List of required properties
    ///   - additionalProperties: Whether to allow properties not in schema
    ///   - enumValues: Allowed values for this schema
    /// - Returns: Dictionary representing the schema
    public static func create(
        type: SchemaType?,
        description: String? = nil,
        properties: [String: [String: Any]]? = nil,
        items: [String: Any]? = nil,
        required: [String]? = nil,
        additionalProperties: Bool = false,
        enumValues: [String]? = nil
    ) -> [String: Any] {
        var result: [String: Any] = [:]
        
        if let type = type {
            switch type {
            case .string: result["type"] = "string"
            case .object: result["type"] = "object"
            case .array: result["type"] = "array"
            case .boolean: result["type"] = "boolean"
            case .integer: result["type"] = "integer"
            case .number: result["type"] = "number"
            }
        }
        
        if let description = description {
            result["description"] = description
        }
        
        if let properties = properties {
            result["properties"] = properties
        }
        
        if let items = items {
            result["items"] = items
        }
        
        if let required = required {
            result["required"] = required
        }
        
        result["additionalProperties"] = additionalProperties
        
        if let enumValues = enumValues {
            result["enum"] = enumValues
        }
        
        return result
    }
}

// MARK: - Clarifying Questions Types

/// Structure for the LLM's clarifying questions request
struct ClarifyingQuestionsRequest: Codable {
    let questions: [ClarifyingQuestion]
    let proceedWithRevisions: Bool  // True if LLM wants to skip questions
}

/// Individual clarifying question
struct ClarifyingQuestion: Codable, Identifiable {
    let id: String
    let question: String
    let context: String? // Optional context about why this question is being asked
}

/// Structure for user's answers to clarifying questions
struct ClarifyingQuestionsResponse: Codable {
    let answers: [QuestionAnswer]
}

/// Individual question answer
struct QuestionAnswer: Codable {
    let questionId: String
    let answer: String?  // nil if user declined to answer
}

/// Mode for resume query workflow
enum ResumeQueryMode {
    case normal
    case withClarifyingQuestions
}
