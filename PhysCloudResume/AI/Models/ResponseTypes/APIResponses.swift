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



/// Wrapper for decoding responses from the OpenAI API
struct ResponsesAPIResponseWrapper: Codable {
    var id: String
    var model: String
    
    // Support for both direct content and the newer nested output format
    private var _content: String?
    var output: [OutputMessage]?
    
    // Computed property that safely provides content from either source
    var content: String {
        // First try direct content (older format)
        if let directContent = _content, !directContent.isEmpty {
            return directContent
        }
        
        // Then try to extract from output array (newer format)
        if let outputMessages = output {
            // Step 1: First try to find a specific message with type "message" 
            // For JSON schema requests, this is typically the message that contains the actual JSON response
            for message in outputMessages {
                if message.type == "message", 
                   let messageContent = message.content,
                   !messageContent.isEmpty {
                    
                    // Look for output_text in message content
                    for item in messageContent {
                        if item.type == "output_text", 
                           let text = item.text,
                           !text.isEmpty {
                            Logger.debug("ResponsesAPIResponseWrapper: Found content in message of type '\(message.type)'")
                            
                            // Try to parse this as JSON to ensure it's a valid response
                            if let firstChar = text.first, firstChar == "{" {
                                return text
                            } else {
                                // If it doesn't look like JSON, keep searching but remember this text for fallback
                                Logger.debug("ResponsesAPIResponseWrapper: Text doesn't appear to be valid JSON, continuing search")
                            }
                        }
                    }
                }
            }
            
            // Step 2: Next, try to specifically extract JSON content from any message
            Logger.debug("ResponsesAPIResponseWrapper: Searching specifically for JSON content in any message")
            for message in outputMessages {
                if let messageContent = message.content {
                    for item in messageContent {
                        if let text = item.text,
                           !text.isEmpty,
                           let trimmedText = text.components(separatedBy: .newlines).first(where: { $0.contains("{") }),
                           trimmedText.contains("{") && trimmedText.contains("}") {
                            Logger.debug("ResponsesAPIResponseWrapper: Found JSON-like content in message type: \(message.type)")
                            return text
                        }
                    }
                }
            }
            
            // Step 3: Fallback to any message content that's not empty
            Logger.debug("ResponsesAPIResponseWrapper: Fallback to any non-empty message content")
            for message in outputMessages {
                if let messageContent = message.content {
                    for item in messageContent {
                        if let text = item.text, !text.isEmpty {
                            Logger.debug("ResponsesAPIResponseWrapper: Found fallback content in message type: \(message.type)")
                            return text
                        }
                    }
                }
            }
        }
        
        // If we get here, we couldn't extract the content
        Logger.debug("ResponsesAPIResponseWrapper: Failed to extract content from response")
        return "" // Empty fallback
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case model
        case _content = "content"
        case output
    }
    
    struct OutputMessage: Codable {
        var id: String?
        var type: String
        var content: [ContentItem]?
        var status: String?
        var role: String?
        
        enum CodingKeys: String, CodingKey {
            case id
            case type
            case content
            case status
            case role
        }
    }
    
    struct ContentItem: Codable {
        var type: String
        var text: String?
        var annotations: [String]?
        
        enum CodingKeys: String, CodingKey {
            case type
            case text
            case annotations
        }
    }
    
    /// Converts to a standard ResponsesAPIResponse
    func toResponsesAPIResponse() -> ResponsesAPIResponse {
        // Use the computed content property that handles both formats
        return ResponsesAPIResponse(id: id, content: content, model: model)
    }
}

/// Response from an OpenAI chat completion request
struct ChatCompletionResponse: Codable, Equatable {
    /// The completion text
    let content: String
    /// The model used for the completion
    let model: String
    /// The response ID from OpenAI (used for the Responses API)
    var id: String?

    init(content: String, model: String, id: String? = nil) {
        self.content = content
        self.model = model
        self.id = id
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
