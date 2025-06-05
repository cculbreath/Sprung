//
//  ConversationTypes.swift
//  PhysCloudResume
//
//  Created on 6/5/2025
//
//  Shared conversation and messaging types used across the application

import Foundation
import SwiftOpenAI

// MARK: - Type Aliases for SwiftOpenAI

/// Use SwiftOpenAI's native message type throughout the application
public typealias LLMMessage = ChatCompletionParameters.Message

/// Use SwiftOpenAI's native response type throughout the application
public typealias LLMResponse = ChatCompletionObject

// MARK: - Convenience Extensions for LLMMessage

extension ChatCompletionParameters.Message {
    
    /// Create a text-only message
    public static func text(role: Role, content: String) -> ChatCompletionParameters.Message {
        return ChatCompletionParameters.Message(
            role: role,
            content: .text(content)
        )
    }
    
    /// Create a message with text and image
    public static func textWithImage(
        role: Role, 
        text: String, 
        imageData: String, 
        mimeType: String = "image/png"
    ) -> ChatCompletionParameters.Message {
        let imageURL = URL(string: "data:\(mimeType);base64,\(imageData)")!
        let textContent = ChatCompletionParameters.Message.ContentType.MessageContent.text(text)
        let imageContent = ChatCompletionParameters.Message.ContentType.MessageContent.imageUrl(
            ChatCompletionParameters.Message.ContentType.MessageContent.ImageDetail(url: imageURL)
        )
        
        return ChatCompletionParameters.Message(
            role: role,
            content: .contentArray([textContent, imageContent])
        )
    }
    
    /// Get text content from message (helper for existing code compatibility)
    public var textContent: String {
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