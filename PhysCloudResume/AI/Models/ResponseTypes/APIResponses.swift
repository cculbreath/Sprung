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

/// Response from an OpenAI Responses API request
struct ResponsesAPIResponse: Codable, Equatable {
    /// The unique ID of the response (used for continuation)
    let id: String
    /// The content of the response
    let content: String
    /// The model used for the response
    let model: String

    /// Converts to a ChatCompletionResponse for backward compatibility
    func toChatCompletionResponse() -> ChatCompletionResponse {
        return ChatCompletionResponse(content: content, model: model, id: id)
    }
}

/// A chunk from a streaming Responses API request
struct ResponsesAPIStreamChunk: Codable, Equatable {
    /// The ID of the response (only present in the final chunk)
    let id: String?
    /// The content of the chunk
    let content: String
    /// The model used for the response
    let model: String
}

/// Wrapper for decoding responses from the OpenAI API
struct ResponsesAPIResponseWrapper: Codable {
    var id: String
    var model: String
    var content: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case model
        case content
    }
    
    /// Converts to a standard ResponsesAPIResponse
    func toResponsesAPIResponse() -> ResponsesAPIResponse {
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

/// Error response from the OpenAI API
struct ResponsesAPIErrorResponse: Codable {
    struct ErrorDetails: Codable {
        let message: String
        let type: String?
        let param: String?
        let code: String?
    }
    
    let error: ErrorDetails
}

// MARK: - Chat Message Types

/// Represents a chat message in a conversation
struct ChatMessage: Codable, Equatable {
    /// The role of the message sender (system, user, assistant)
    let role: ChatRole
    /// The content of the message
    let content: String

    /// Creates a new chat message
    /// - Parameters:
    ///   - role: The role of the message sender
    ///   - content: The content of the message
    init(role: ChatRole, content: String) {
        self.role = role
        self.content = content
    }

    enum ChatRole: String, Codable {
        case system
        case user
        case assistant
    }
}
