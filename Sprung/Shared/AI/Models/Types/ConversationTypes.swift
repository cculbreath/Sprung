//
//  ConversationTypes.swift
//  Sprung
//
//  Created on 6/5/2025
//
//  Shared conversation and messaging types used across the application
import Foundation
import SwiftOpenAI
// MARK: - Type Aliases for SwiftOpenAI
/// Use SwiftOpenAI's native message type throughout the application
typealias LLMMessage = ChatCompletionParameters.Message
/// Use SwiftOpenAI's native response type throughout the application
typealias LLMResponse = ChatCompletionObject
/// JSON Schema types for structured outputs
typealias JSONSchema = SwiftOpenAI.JSONSchema
typealias JSONSchemaResponseFormat = SwiftOpenAI.JSONSchemaResponseFormat
typealias ChatCompletionParameters = SwiftOpenAI.ChatCompletionParameters

// MARK: - Convenience Extensions for LLMMessage
extension ChatCompletionParameters.Message {

    /// Create a text-only message
    static func text(role: Role, content: String) -> ChatCompletionParameters.Message {
        return ChatCompletionParameters.Message(
            role: role,
            content: .text(content)
        )
    }

    /// Get text content from message (helper for existing code compatibility)
    var textContent: String {
        switch content {
        case .text(let text):
            return text
        case .contentArray(let contents):
            return contents.compactMap { content in
                if case let .text(text) = content {
                    return text
                }
                return nil
            }.joined(separator: " ")
        }
    }
}
