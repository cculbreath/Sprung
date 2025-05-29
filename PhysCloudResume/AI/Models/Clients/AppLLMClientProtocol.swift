//
//  AppLLMClientProtocol.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 5/20/25.
//

import Foundation

/// Represents the content of a message part, supporting text and images.
enum AppLLMMessageContentPart {
    case text(String)
    case imageUrl(base64Data: String, mimeType: String) // e.g., "image/png" or "image/jpeg"
}

/// Represents a single message in a conversation for the application.
struct AppLLMMessage {
    enum Role: String, Codable {
        case system, user, assistant
    }
    let role: Role
    let contentParts: [AppLLMMessageContentPart] // Array to support multimodal

    // Convenience initializer for text-only messages
    init(role: Role, text: String) {
        self.role = role
        self.contentParts = [.text(text)]
    }

    // Initializer for potentially multimodal messages
    init(role: Role, contentParts: [AppLLMMessageContentPart]) {
        self.role = role
        self.contentParts = contentParts
    }
}

/// Defines the parameters for an LLM query from the application's perspective.
struct AppLLMQuery {
    let messages: [AppLLMMessage] // For conversational context or single-shot prompts
    let modelIdentifier: String // e.g., "gpt-4o", "gemini-1.5-flash"
    let temperature: Double?
    // Add other common parameters like maxTokens, topP if needed
    
    // For structured JSON output
    let desiredResponseType: Decodable.Type? // The Swift type expected for JSON output
    let jsonSchema: String? // Optional: A JSON schema string if type inference isn't enough or for complex cases

    // Initializer for simple text query (can be single-shot or part of a conversation)
    init(messages: [AppLLMMessage], modelIdentifier: String, temperature: Double? = 1.0) {
        self.messages = messages
        self.modelIdentifier = modelIdentifier
        self.temperature = temperature
        self.desiredResponseType = nil
        self.jsonSchema = nil
    }

    // Initializer for structured JSON query (typically single-shot, but messages can provide context)
    init<T: Decodable>(messages: [AppLLMMessage], modelIdentifier: String, temperature: Double? = 1.0, responseType: T.Type, jsonSchema: String? = nil) {
        self.messages = messages
        self.modelIdentifier = modelIdentifier
        self.temperature = temperature
        self.desiredResponseType = responseType
        self.jsonSchema = jsonSchema // You might need a utility to generate this from T.Type or define it manually
    }
}

/// Represents the response from an LLM interaction for the application.
enum AppLLMResponse {
    case text(String) // For single, complete text responses
    case structured(Data) // Raw Data, to be decoded by the caller into desiredResponseType
}

enum AppLLMError: Error {
    case decodingFailed(Error)
    case unexpectedResponseFormat
    case clientError(String)
    case decodingError(String)
    case timeout(String)
    case rateLimited(retryAfter: TimeInterval?)
    // Add other specific errors as needed
}

// Provide user-friendly descriptions for LLM errors
extension AppLLMError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .decodingFailed(let error):
            return "Decoding failed: \(error.localizedDescription)"
        case .unexpectedResponseFormat:
            return "Unexpected response format from provider"
        case .clientError(let message):
            return message
        case .decodingError(let message):
            return message
        case .timeout(let message):
            return message
        case .rateLimited(let retryAfter):
            if let retryAfter = retryAfter {
                return "Rate limit exceeded. Please try again in \(Int(retryAfter)) seconds."
            } else {
                return "Rate limit exceeded. Please try again later."
            }
        }
    }
}

/// Core protocol defining the unified interface for LLM client interactions
protocol AppLLMClientProtocol {
    /// Executes a query expecting a single, non-streaming response (text or structured).
    func executeQuery(_ query: AppLLMQuery) async throws -> AppLLMResponse
}

// Extension to support conversion between legacy ChatMessage and AppLLMMessage
// These extensions are thin wrappers around the MessageConverter for backward compatibility
extension AppLLMMessage {
    // Convert from legacy ChatMessage to AppLLMMessage
    static func from(chatMessage: ChatMessage) -> AppLLMMessage {
        return MessageConverter.appLLMMessageFrom(chatMessage: chatMessage)
    }
    
    // Convert to legacy ChatMessage
    func toChatMessage() -> ChatMessage {
        return MessageConverter.chatMessageFrom(appMessage: self)
    }
}

// Extension to convert arrays of messages
extension Array where Element == AppLLMMessage {
    // Convert from legacy [ChatMessage] to [AppLLMMessage]
    static func fromChatMessages(_ chatMessages: [ChatMessage]) -> [AppLLMMessage] {
        return MessageConverter.appLLMMessagesFrom(chatMessages: chatMessages)
    }
    
    // Convert to legacy [ChatMessage]
    func toChatMessages() -> [ChatMessage] {
        return MessageConverter.chatMessagesFrom(appMessages: self)
    }
}
