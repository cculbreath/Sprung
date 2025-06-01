//
//  ConversationContextManager.swift
//  PhysCloudResume
//
//  Created by Assistant on 5/19/25.
//

import SwiftData
import Foundation
import Observation

// MARK: - Conversation Context Manager (Only for Chat Providers)

@MainActor
@Observable
class ConversationContextManager {
    static let shared = ConversationContextManager()
    
    private var modelContext: ModelContext?
    private let maxContextTokens: Int = 4000 // Default context window
    private var isInitialized = false
    
    private init() {}
    
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
        self.isInitialized = true
    }
    
    // MARK: - Context Management
    
    func getContext(for objectId: UUID, type: ConversationType) -> ConversationContext? {
        guard let modelContext = modelContext else { 
            // Early access before initialization - return nil gracefully
            return nil 
        }
        
        do {
            let contexts = try modelContext.fetch(FetchDescriptor<ConversationContext>())
            return contexts.first { context in
                context.objectId == objectId && context.objectType == type.rawValue
            }
        } catch {
            Logger.debug("Failed to fetch conversation context: \(error)")
            // If database schema issues are detected, log them but continue gracefully
            if error.localizedDescription.contains("no such table") {
                Logger.warning("Conversation context table not found - database may need migration")
            }
            return nil
        }
    }
    
    func getOrCreateContext(for objectId: UUID, type: ConversationType) -> ConversationContext {
        if let existing = getContext(for: objectId, type: type) {
            return existing
        }
        
        guard let modelContext = modelContext else {
            Logger.warning("ModelContext not set - returning new context without persistence")
            return ConversationContext(objectId: objectId, objectType: type)
        }
        
        let context = ConversationContext(objectId: objectId, objectType: type)
        modelContext.insert(context)
        
        do {
            try modelContext.save()
            return context
        } catch {
            Logger.debug("Failed to create context: \(error)")
            // If database schema issues are detected, provide graceful fallback
            if error.localizedDescription.contains("no such table") {
                Logger.warning("Cannot save conversation context - database schema issue detected")
            }
            return context
        }
    }
    
    // MARK: - Message Management
    
    func addMessage(_ message: ChatMessage, to context: ConversationContext) {
        guard let modelContext = modelContext else { return }
        
        let contextMessage = ConversationMessage(role: message.role, content: message.content, imageData: message.imageData)
        context.messages.append(contextMessage)
        context.lastUpdated = Date()
        
        // Auto-prune if context gets too large
        pruneContextIfNeeded(context)
        
        do {
            try modelContext.save()
        } catch {
            Logger.debug("Failed to save message: \(error)")
        }
    }
    
    func getMessages(for context: ConversationContext) -> [ChatMessage] {
        return context.messages
            .sorted { $0.timestamp < $1.timestamp }
            .map { $0.chatMessage }
    }
    
    func clearContext(for objectId: UUID, type: ConversationType) {
        guard let modelContext = modelContext else { 
            // Early access before initialization - only log if we expected to be initialized
            if isInitialized {
                Logger.debug("ConversationContextManager modelContext is nil after initialization")
            }
            return 
        }
        
        guard let context = getContext(for: objectId, type: type) else { return }
        
        modelContext.delete(context)
        
        do {
            try modelContext.save()
        } catch {
            Logger.debug("Failed to clear context: \(error)")
        }
    }
    
    // MARK: - Context Pruning
    
    private func pruneContextIfNeeded(_ context: ConversationContext) {
        guard context.estimatedTokenCount > maxContextTokens else { return }
        
        let messages = getMessages(for: context)
        let prunedMessages = TokenCounter.pruneMessagesToFit(messages: messages, maxTokens: maxContextTokens)
        
        // Clear existing messages and replace with pruned set
        context.messages.removeAll()
        for message in prunedMessages {
            let contextMessage = ConversationMessage(role: message.role, content: message.content)
            context.messages.append(contextMessage)
        }
    }
}
