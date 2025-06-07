//
//  ConversationModels.swift
//  PhysCloudResume
//
//  Created by Assistant on 5/19/25.
//

import SwiftData
import Foundation

// MARK: - SwiftData Models for Conversational AI Context
// Note: Type aliases for SwiftOpenAI types are defined in ConversationTypes.swift

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
}

@Model
class ConversationMessage {
    var id: UUID
    var role: String        // "system", "user", "assistant"
    var content: String
    var imageData: String?  // Base64-encoded image data for vision models
    var timestamp: Date
    
    // Relationship to context
    var context: ConversationContext?
    
    init(role: ChatCompletionParameters.Message.Role, content: String, imageData: String? = nil) {
        self.id = UUID()
        self.role = role.rawValue
        self.content = content
        self.imageData = imageData
        self.timestamp = Date()
    }
    
}

// MARK: - Supporting Types

enum ConversationType: String, CaseIterable {
    case resume = "resume"
    case coverLetter = "coverLetter"
}
