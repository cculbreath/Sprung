//
//  ResponsesAPIRequest.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 4/26/25.
//

import Foundation

/// Represents a request to the OpenAI Responses API
struct ResponsesAPIRequest: Encodable {
    /// The model to use for the request
    let model: String
    /// The input message to send to the model
    let input: String
    /// Controls the randomness of the output (0-1)
    let temperature: Double
    /// Optional ID of the previous response for conversation state
    let previousResponseId: String?

    enum CodingKeys: String, CodingKey {
        case model
        case input
        case temperature
        case previousResponseId = "previous_response_id"
    }
}

/// Represents the response from the OpenAI Responses API
struct ResponsesAPIResponseWrapper: Decodable {
    /// The unique ID of this response (used for future conversation state)
    let id: String
    /// The model used for the response
    let model: String
    /// The output of the response, containing message(s)
    let output: [OutputMessage]

    enum CodingKeys: String, CodingKey {
        case id
        case model
        case output
    }

    /// Converts the response wrapper to a ResponsesAPIResponse
    func toResponsesAPIResponse() -> ResponsesAPIResponse {
        // Extract text content from the output messages
        let textContent = output
            .flatMap { $0.content }
            .filter { $0.type == "output_text" }
            .compactMap { $0.text }
            .joined(separator: "\n")

        return ResponsesAPIResponse(
            id: id,
            content: textContent,
            model: model
        )
    }
}

/// Represents a message in the output array
struct OutputMessage: Decodable {
    /// The ID of the message
    let id: String
    /// The type of the message (usually "message")
    let type: String
    /// The content blocks of the message
    let content: [MessageContent]
    /// The role of the message sender
    let role: String

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case content
        case role
    }
}

/// Represents a content block in a message
struct MessageContent: Decodable {
    /// The type of content ("output_text", etc.)
    let type: String
    /// The annotations (if any)
    let annotations: [String]?
    /// The text content
    let text: String?

    enum CodingKeys: String, CodingKey {
        case type
        case annotations
        case text
    }
}

/// Represents an error response from the OpenAI API
struct ResponsesAPIErrorResponse: Decodable {
    /// The error details
    let error: ErrorDetails

    struct ErrorDetails: Decodable {
        /// The type of error
        let type: String
        /// The error message
        let message: String
        /// The error code
        let code: String?
    }
}
