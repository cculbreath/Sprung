//
//  LLMConversationStore.swift
//  PhysCloudResume
//
//  Actor responsible for persisting conversation history using SwiftData and
//  domain DTOs.
//

import Foundation
import SwiftData

actor LLMConversationStore {
    private let modelContext: ModelContext?

    init(modelContext: ModelContext?) {
        self.modelContext = modelContext
    }

    func loadMessages(conversationId: UUID) async -> [LLMMessageDTO] {
        guard let context = modelContext else { return [] }
        let descriptor = FetchDescriptor<ConversationContext>(predicate: #Predicate { $0.id == conversationId }, sortBy: [])
        if let stored = try? context.fetch(descriptor).first {
            return stored.messages.sorted { $0.timestamp < $1.timestamp }.map { $0.dto }
        }
        return []
    }

    func saveMessages(
        conversationId: UUID,
        objectId: UUID? = nil,
        objectType: ConversationType? = nil,
        messages: [LLMMessageDTO]
    ) async {
        guard let context = modelContext else { return }
        let descriptor = FetchDescriptor<ConversationContext>(predicate: #Predicate { $0.id == conversationId }, sortBy: [])
        let existing = try? context.fetch(descriptor).first
        let conversation = existing ?? ConversationContext(
            conversationId: conversationId,
            objectId: objectId,
            objectType: objectType ?? .general
        )

        if let objectId {
            conversation.objectId = objectId
        }
        if let objectType {
            conversation.objectType = objectType.rawValue
        }
        conversation.lastUpdated = Date()

        // Replace messages
        conversation.messages.removeAll()
        messages.forEach { dto in
            let stored = ConversationMessage.fromDTO(dto)
            stored.context = conversation
            conversation.messages.append(stored)
        }

        if existing == nil {
            context.insert(conversation)
        }

        do {
            try context.save()
        } catch {
            Logger.error("❌ Failed to save conversation: \(error)", category: .storage)
        }
    }

    func clearConversation(conversationId: UUID) async {
        guard let context = modelContext else { return }
        let descriptor = FetchDescriptor<ConversationContext>(predicate: #Predicate { $0.id == conversationId }, sortBy: [])
        if let stored = try? context.fetch(descriptor).first {
            context.delete(stored)
            try? context.save()
        }
    }
}
