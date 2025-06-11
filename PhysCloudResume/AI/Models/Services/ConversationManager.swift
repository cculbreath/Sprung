//
//  ConversationManager.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 6/10/25.
//

import Foundation
import SwiftData
import SwiftOpenAI

/// Simple conversation manager for maintaining conversation state
@MainActor
internal class ConversationManager {
    private var conversations: [UUID: [LLMMessage]] = [:]
    private var modelContext: ModelContext?
    
    init(modelContext: ModelContext?) {
        self.modelContext = modelContext
    }
    
    func storeConversation(id: UUID, messages: [LLMMessage]) {
        conversations[id] = messages
        // TODO: Implement SwiftData persistence if needed
    }
    
    func getConversation(id: UUID) -> [LLMMessage] {
        return conversations[id] ?? []
    }
    
    func clearConversation(id: UUID) {
        conversations.removeValue(forKey: id)
    }
}