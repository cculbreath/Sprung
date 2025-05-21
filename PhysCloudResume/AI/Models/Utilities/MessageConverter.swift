//
//  MessageConverter.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 5/20/25.
//

import Foundation
import SwiftOpenAI

/// Centralized utility for converting between different message formats
/// This eliminates duplicated conversion logic across the codebase
class MessageConverter {
    // MARK: - AppLLMMessage ↔ ChatMessage conversions
    
    /// Convert from legacy ChatMessage to AppLLMMessage
    /// - Parameter chatMessage: Legacy chat message to convert
    /// - Returns: Equivalent AppLLMMessage
    static func appLLMMessageFrom(chatMessage: ChatMessage) -> AppLLMMessage {
        let role: AppLLMMessage.Role
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
    
    /// Convert from AppLLMMessage to legacy ChatMessage
    /// - Parameter appMessage: AppLLMMessage to convert
    /// - Returns: Equivalent ChatMessage
    static func chatMessageFrom(appMessage: AppLLMMessage) -> ChatMessage {
        let role: ChatMessage.ChatRole
        switch appMessage.role {
        case .system: role = .system
        case .user: role = .user
        case .assistant: role = .assistant
        }
        
        // Extract text content from first text part or use empty string
        let textContent = appMessage.contentParts.first(where: { 
            if case .text = $0 { return true } else { return false }
        }).flatMap { 
            if case let .text(content) = $0 { return content } else { return nil }
        } ?? ""
        
        // Extract optional image data from first image part
        let imageData = appMessage.contentParts.first(where: { 
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
    
    /// Convert from array of legacy ChatMessages to array of AppLLMMessages
    /// - Parameter chatMessages: Array of legacy chat messages
    /// - Returns: Array of AppLLMMessages
    static func appLLMMessagesFrom(chatMessages: [ChatMessage]) -> [AppLLMMessage] {
        return chatMessages.map { appLLMMessageFrom(chatMessage: $0) }
    }
    
    /// Convert from array of AppLLMMessages to array of legacy ChatMessages
    /// - Parameter appMessages: Array of AppLLMMessages
    /// - Returns: Array of legacy ChatMessages
    static func chatMessagesFrom(appMessages: [AppLLMMessage]) -> [ChatMessage] {
        return appMessages.map { chatMessageFrom(appMessage: $0) }
    }
    
    // MARK: - AppLLMMessage ↔ SwiftOpenAI.ChatCompletionParameters.Message conversions
    
    /// Convert from AppLLMMessage to SwiftOpenAI's ChatCompletionParameters.Message
    /// - Parameter appMessage: AppLLMMessage to convert
    /// - Returns: SwiftOpenAI message equivalent
    static func swiftOpenAIMessageFrom(appMessage: AppLLMMessage) -> ChatCompletionParameters.Message {
        let role: ChatCompletionParameters.Message.Role
        switch appMessage.role {
        case .system: role = .system
        case .user: role = .user
        case .assistant: role = .assistant
        }
        
        // Handle simple text-only message
        if appMessage.contentParts.count == 1, case let .text(content) = appMessage.contentParts[0] {
            return ChatCompletionParameters.Message(
                role: role,
                content: .text(content)
            )
        }
        
        // Handle multimodal message (text + images)
        else {
            var contents: [ChatCompletionParameters.Message.ContentType.MessageContent] = []
            
            // Convert each content part
            for part in appMessage.contentParts {
                switch part {
                case let .text(content):
                    contents.append(.text(content))
                case let .imageUrl(base64Data, mimeType):
                    let imageUrlString = "data:\(mimeType);base64,\(base64Data)"
                    if let imageURL = URL(string: imageUrlString) {
                        let imageDetail = ChatCompletionParameters.Message.ContentType.MessageContent.ImageDetail(
                            url: imageURL,
                            detail: "high"
                        )
                        contents.append(.imageUrl(imageDetail))
                    } else {
                        Logger.error("Failed to create URL from image data")
                    }
                }
            }
            
            // Create message with content array
            return ChatCompletionParameters.Message(
                role: role,
                content: .contentArray(contents)
            )
        }
    }
    
    /// Convert array of AppLLMMessages to array of SwiftOpenAI Messages
    /// - Parameter appMessages: Array of AppLLMMessages
    /// - Returns: Array of SwiftOpenAI Messages
    static func swiftOpenAIMessagesFrom(appMessages: [AppLLMMessage]) -> [ChatCompletionParameters.Message] {
        return appMessages.map { swiftOpenAIMessageFrom(appMessage: $0) }
    }
    
    /// Convert from SwiftOpenAI's ChatCompletionParameters.Message to AppLLMMessage
    /// - Parameter swiftMessage: SwiftOpenAI message to convert
    /// - Returns: AppLLMMessage equivalent
    static func appLLMMessageFrom(swiftMessage: ChatCompletionParameters.Message) -> AppLLMMessage {
        // Map the role
        let role: AppLLMMessage.Role
        
        // Use string comparison to handle role mapping safely
        let roleString = String(describing: swiftMessage.role)
        if roleString.hasSuffix(".system") {
            role = .system
        } else if roleString.hasSuffix(".assistant") {
            role = .assistant
        } else {
            // Default to user for user role or any unrecognized role
            role = .user
        }
        
        // Initialize with empty content parts
        var contentParts: [AppLLMMessageContentPart] = []
        
        // Handle text content
        if case let .text(text) = swiftMessage.content {
            contentParts.append(.text(text))
        }
        // Handle content array (multimodal)
        else if case let .contentArray(contents) = swiftMessage.content {
            for content in contents {
                if case let .text(text) = content {
                    contentParts.append(.text(text))
                }
                else if case let .imageUrl(imageDetail) = content {
                    // Extract base64 data if present
                    let urlString = imageDetail.url.absoluteString
                    if urlString.hasPrefix("data:") {
                        // Parse data URL format: data:[<mediatype>][;base64],<data>
                        let components = urlString.components(separatedBy: ",")
                        if components.count > 1,
                           let metaParts = components.first?.components(separatedBy: ";"),
                           metaParts.last == "base64" {
                            
                            // Extract MIME type from data URL
                            var mimeType = "image/png" // Default
                            if metaParts.count > 1,
                               let firstPart = metaParts.first,
                               firstPart.hasPrefix("data:") {
                                mimeType = firstPart.replacingOccurrences(of: "data:", with: "")
                            }
                            
                            // Create image content part
                            contentParts.append(.imageUrl(base64Data: components[1], mimeType: mimeType))
                        }
                    }
                }
            }
        }
        
        // If no content parts were added, provide a default empty text part
        if contentParts.isEmpty {
            contentParts.append(.text(""))
        }
        
        // Use the multi-part constructor for consistency
        return AppLLMMessage(role: role, contentParts: contentParts)
    }
    
    /// Convert array of SwiftOpenAI Messages to array of AppLLMMessages
    /// - Parameter swiftMessages: Array of SwiftOpenAI Messages
    /// - Returns: Array of AppLLMMessages
    static func appLLMMessagesFrom(swiftMessages: [ChatCompletionParameters.Message]) -> [AppLLMMessage] {
        return swiftMessages.map { appLLMMessageFrom(swiftMessage: $0) }
    }
}
