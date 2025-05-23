//
//  APIResponses.swift
//  PhysCloudResume
//
//  Created by Team on 5/13/25.
//

import Foundation
import PDFKit
import AppKit
import SwiftUI

// MARK: - Local Protocol Definitions
// These protocols replace OpenAI dependencies for our abstraction layer

// This line is commented out since we now have a better implementation in StructuredOutput.swift
// protocol StructuredOutput: Codable {}

// MARK: - Chat Response Format Types

/// Defines the format of the response from the chat completion API
enum ResponseFormat: Codable, Equatable {
    /// Response should be in JSON format
    case json
    /// Response should use a custom JSON schema
    case jsonSchema(JSONSchemaFormat)
    
    /// JSON schema format for structured responses
    struct JSONSchemaFormat: Codable, Equatable {
        /// The name of the schema
        let name: String
        /// Whether to enforce strict schema validation
        let strict: Bool
        /// The schema definition as a JSON object
        let schema: [String: Any]
        
        enum CodingKeys: String, CodingKey {
            case name
            case strict
            case schema
        }
        
        // Custom coding for schema since it's a Dictionary with Any values
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(name, forKey: .name)
            try container.encode(strict, forKey: .strict)
            
            // Convert schema to Data and encode as String
            let jsonData = try JSONSerialization.data(withJSONObject: schema)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
            try container.encode(jsonString, forKey: .schema)
        }
        
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decode(String.self, forKey: .name)
            strict = try container.decode(Bool.self, forKey: .strict)
            
            // Decode schema from String to Dictionary
            let jsonString = try container.decode(String.self, forKey: .schema)
            let jsonData = jsonString.data(using: .utf8) ?? Data()
            schema = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] ?? [:]
        }
        
        public init(name: String, strict: Bool, schema: [String: Any]) {
            self.name = name
            self.strict = strict
            self.schema = schema
        }
        
        // Custom Equatable implementation to handle [String: Any] schema
        public static func == (lhs: JSONSchemaFormat, rhs: JSONSchemaFormat) -> Bool {
            // Compare simple properties
            guard lhs.name == rhs.name && lhs.strict == rhs.strict else {
                return false
            }
            
            // For schema comparison, we'll convert both to JSON strings and compare those
            do {
                let lhsData = try JSONSerialization.data(withJSONObject: lhs.schema, options: [.sortedKeys])
                let rhsData = try JSONSerialization.data(withJSONObject: rhs.schema, options: [.sortedKeys])
                
                let lhsString = String(data: lhsData, encoding: .utf8)
                let rhsString = String(data: rhsData, encoding: .utf8)
                
                return lhsString == rhsString
            } catch {
                // If JSON serialization fails, consider them not equal
                return false
            }
        }
    }
}

/// Response from an OpenAI Responses API request
struct ResponsesAPIResponse: Codable, Equatable {
    /// The unique ID of the response (used for continuation)
    let id: String
    /// The content of the response
    let content: String
    /// The model used for the response
    let model: String
}

/// Response schema for best cover letter selection
struct BestCoverLetterResponse: Codable, StructuredOutput {
    let strengthAndVoiceAnalysis: String
    let bestLetterUuid: String
    let verdict: String
    
    // Implement validate for StructuredOutput
    func validate() -> Bool {
        // Check if we have non-empty values
        return !strengthAndVoiceAnalysis.isEmpty &&
               !bestLetterUuid.isEmpty &&
               !verdict.isEmpty
    }
}


// MARK: - Chat Message Types

/// Represents a chat message in a conversation
struct ChatMessage: Codable, Equatable {
    /// The role of the message sender (system, user, assistant)
    let role: ChatRole
    /// The content of the message
    let content: String
    /// Optional base64-encoded image data for vision models
    let imageData: String?

    /// Creates a new chat message with text only
    /// - Parameters:
    ///   - role: The role of the message sender
    ///   - content: The content of the message
    init(role: ChatRole, content: String) {
        self.role = role
        self.content = content
        self.imageData = nil
    }
    
    /// Creates a new chat message with text and image
    /// - Parameters:
    ///   - role: The role of the message sender
    ///   - content: The content of the message
    ///   - imageData: Base64-encoded image data
    init(role: ChatRole, content: String, imageData: String) {
        self.role = role
        self.content = content
        self.imageData = imageData
    }

    enum ChatRole: String, Codable {
        case system
        case user
        case assistant
    }
}
