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
