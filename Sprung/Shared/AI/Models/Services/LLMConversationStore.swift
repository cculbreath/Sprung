//
//  LLMConversationStore.swift
//  Sprung
//
//  Actor responsible for persisting conversation history using SwiftData and
//  domain DTOs.
//
//  @ModelActor: the actor owns a ModelContext bound to its own executor.
//  ModelContext is not thread-safe, so persistence work off the main actor
//  must go through a context created HERE — sharing the main-actor context
//  with this actor crashes (EXC_BAD_ACCESS) in fetch/save.
//
import Foundation
import SwiftData

@ModelActor
actor LLMConversationStore {
    func loadMessages(conversationId: UUID) -> [LLMMessageDTO] {
        let descriptor = FetchDescriptor<ConversationContext>(predicate: #Predicate { $0.id == conversationId }, sortBy: [])
        do {
            guard let stored = try modelContext.fetch(descriptor).first else {
                // Legitimately new conversation — no stored history yet.
                return []
            }
            return stored.messages.sorted { $0.timestamp < $1.timestamp }.map { $0.dto }
        } catch {
            Logger.error("❌ Failed to load conversation: \(error)", category: .storage)
            Task { @MainActor in
                ToastCenter.shared.show(.error("Could not load this conversation history. \(error.localizedDescription)"))
            }
            return []
        }
    }

    func saveMessages(
        conversationId: UUID,
        objectId: UUID? = nil,
        objectType: ConversationType? = nil,
        messages: [LLMMessageDTO]
    ) {
        let descriptor = FetchDescriptor<ConversationContext>(predicate: #Predicate { $0.id == conversationId }, sortBy: [])
        let existing = try? modelContext.fetch(descriptor).first
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
            modelContext.insert(conversation)
        }
        do {
            try modelContext.save()
        } catch {
            Logger.error("❌ Failed to save conversation: \(error)", category: .storage)
            Task { @MainActor in
                ToastCenter.shared.show(.error("Couldn't save conversation history — your chat may not persist after relaunch. \(error.localizedDescription)"))
            }
        }
    }
}
