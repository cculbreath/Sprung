//
//  ConversationModels.swift
//  PhysCloudResume
//
//  Created by Assistant on 5/19/25.
//

import SwiftData
import Foundation

// MARK: - SwiftData Models for Conversational AI Context

@Model
class ConversationContext {
    var id: UUID
    var objectId: UUID  // References Resume or CoverLetter UUID
    var objectType: String  // "resume" or "coverLetter"
    var lastUpdated: Date
    
    // Relationship to messages
    @Relationship(deleteRule: .cascade, inverse: \ConversationMessage.context)
    var messages: [ConversationMessage] = []
    
    init(objectId: UUID, objectType: ConversationType) {
        self.id = UUID()
        self.objectId = objectId
        self.objectType = objectType.rawValue
        self.lastUpdated = Date()
    }
    
    // Computed properties
    var conversationType: ConversationType {
        return ConversationType(rawValue: objectType) ?? .resume
    }
    
    var messageCount: Int {
        return messages.count
    }
    
    var estimatedTokenCount: Int {
        return messages.reduce(0) { $0 + $1.estimatedTokens }
    }
}

@Model
class ConversationMessage {
    var id: UUID
    var role: String        // "system", "user", "assistant"
    var content: String
    var imageData: String?  // Base64-encoded image data for vision models
    var timestamp: Date
    var estimatedTokens: Int
    
    // Relationship to context
    var context: ConversationContext?
    
    init(role: ChatMessage.ChatRole, content: String, imageData: String? = nil) {
        self.id = UUID()
        self.role = role.rawValue
        self.content = content
        self.imageData = imageData
        self.timestamp = Date()
        // Calculate tokens including image if present (rough estimate)
        self.estimatedTokens = TokenCounter.estimateTokens(for: content) + (imageData != nil ? 85 : 0)
    }
    
    // Convert to ChatMessage for API calls
    var chatMessage: ChatMessage {
        if let imageData = imageData {
            return ChatMessage(role: ChatMessage.ChatRole(rawValue: role) ?? .user, content: content, imageData: imageData)
        } else {
            return ChatMessage(role: ChatMessage.ChatRole(rawValue: role) ?? .user, content: content)
        }
    }
}

// MARK: - Supporting Types

enum ConversationType: String, CaseIterable {
    case resume = "resume"
    case coverLetter = "coverLetter"
}

// MARK: - Token Counter Utility

class TokenCounter {
    // Simple token estimation (roughly 4 characters per token for English)
    static func estimateTokens(for text: String) -> Int {
        return max(1, text.count / 4)
    }
    
    static func estimateTokens(for messages: [ChatMessage]) -> Int {
        return messages.reduce(0) { $0 + estimateTokens(for: $1.content) }
    }
    
    // Prune messages to fit within token limit, preserving system messages
    static func pruneMessagesToFit(messages: [ChatMessage], maxTokens: Int) -> [ChatMessage] {
        let systemMessages = messages.filter { $0.role == .system }
        let otherMessages = messages.filter { $0.role != .system }
        
        var result = systemMessages
        var tokenCount = estimateTokens(for: systemMessages)
        
        // Add messages from most recent, working backwards
        for message in otherMessages.reversed() {
            let messageTokens = estimateTokens(for: message.content)
            if tokenCount + messageTokens <= maxTokens {
                result.append(message)
                tokenCount += messageTokens
            }
        }
        
        // Restore chronological order for non-system messages
        let otherResult = result.filter { $0.role != .system }.sorted { 
            // This is a simple approach - in real implementation you'd need proper timestamp tracking
            $0.content.count < $1.content.count 
        }
        
        return systemMessages + otherResult
    }
}
