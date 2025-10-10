//
//  ConversationCoordinator.swift
//  PhysCloudResume
//
//  Coordinates in-memory caching and SwiftData persistence for LLM conversations.
//

import Foundation

actor ConversationCoordinator {
    private var cache: [UUID: [LLMMessageDTO]] = [:]
    private var store: LLMConversationStore?

    init(store: LLMConversationStore? = nil) {
        self.store = store
    }

    func updateStore(_ store: LLMConversationStore?) {
        self.store = store
    }

    func messages(for conversationId: UUID) async -> [LLMMessageDTO] {
        if let cached = cache[conversationId] {
            return cached
        }

        let persisted = await store?.loadMessages(conversationId: conversationId) ?? []
        if !persisted.isEmpty {
            cache[conversationId] = persisted
        }
        return persisted
    }

    func persist(
        conversationId: UUID,
        messages: [LLMMessageDTO],
        objectId: UUID? = nil,
        objectType: ConversationType? = nil
    ) async {
        cache[conversationId] = messages
        await store?.saveMessages(
            conversationId: conversationId,
            objectId: objectId,
            objectType: objectType,
            messages: messages
        )
    }

    func clear(conversationId: UUID) async {
        cache.removeValue(forKey: conversationId)
        await store?.clearConversation(conversationId: conversationId)
    }
}
