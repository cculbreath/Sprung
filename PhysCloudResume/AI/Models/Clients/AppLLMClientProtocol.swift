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
    init(messages: [AppLLMMessage], modelIdentifier: String, temperature: Double? = 0.7) {
        self.messages = messages
        self.modelIdentifier = modelIdentifier
        self.temperature = temperature
        self.desiredResponseType = nil
        self.jsonSchema = nil
    }

    // Initializer for structured JSON query (typically single-shot, but messages can provide context)
    init<T: Decodable>(messages: [AppLLMMessage], modelIdentifier: String, temperature: Double? = 0.7, responseType: T.Type, jsonSchema: String? = nil) {
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
        }
    }
}

/// Core protocol defining the unified interface for LLM client interactions
protocol AppLLMClientProtocol {
    /// Executes a query expecting a single, non-streaming response (text or structured).
    func executeQuery(_ query: AppLLMQuery) async throws -> AppLLMResponse
}

// Extension to support conversion between legacy ChatMessage and AppLLMMessage
extension AppLLMMessage {
    // Convert from legacy ChatMessage to AppLLMMessage
    static func from(chatMessage: ChatMessage) -> AppLLMMessage {
        let role: Role
        switch chatMessage.role {
        case .system: role = .system
        case .user: role = .user
        case .assistant: role = .assistant
        }
        
        // Handle text-only case
        if chatMessage.imageData == nil {
            return AppLLMMessage(role: role, text: chatMessage.content)
        } 
        // Handle text + image case
        else if let imageData = chatMessage.imageData {
            let textPart = AppLLMMessageContentPart.text(chatMessage.content)
            let imagePart = AppLLMMessageContentPart.imageUrl(base64Data: imageData, mimeType: "image/png")
            return AppLLMMessage(role: role, contentParts: [textPart, imagePart])
        }
        // Fallback to text-only if imageData is somehow nil despite the check
        else {
            return AppLLMMessage(role: role, text: chatMessage.content)
        }
    }
    
    // Convert to legacy ChatMessage
    func toChatMessage() -> ChatMessage {
        let role: ChatMessage.ChatRole
        switch self.role {
        case .system: role = .system
        case .user: role = .user
        case .assistant: role = .assistant
        }
        
        // Extract text content from first text part or use empty string
        let textContent = contentParts.first(where: { 
            if case .text = $0 { return true } else { return false }
        }).flatMap { 
            if case let .text(content) = $0 { return content } else { return nil }
        } ?? ""
        
        // Extract optional image data from first image part
        let imageData = contentParts.first(where: { 
            if case .imageUrl = $0 { return true } else { return false }
        }).flatMap { 
            if case let .imageUrl(base64Data, _) = $0 { return base64Data } else { return nil }
        }
        
        // Create ChatMessage with or without image data
        if let imageData = imageData {
            return ChatMessage(role: role, content: textContent, imageData: imageData)
        } else {
            return ChatMessage(role: role, content: textContent)
        }
    }
}

// Extension to convert arrays of messages
extension Array where Element == AppLLMMessage {
    // Convert from legacy [ChatMessage] to [AppLLMMessage]
    static func fromChatMessages(_ chatMessages: [ChatMessage]) -> [AppLLMMessage] {
        return chatMessages.map { AppLLMMessage.from(chatMessage: $0) }
    }
    
    // Convert to legacy [ChatMessage]
    func toChatMessages() -> [ChatMessage] {
        return self.map { $0.toChatMessage() }
    }
}
