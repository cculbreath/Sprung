//
//  ConversationCoordinator.swift
//  Sprung
//
//  Coordinates in-memory caching and SwiftData persistence for LLM conversations.
//
import Foundation
actor ConversationCoordinator {
    private var cache: [UUID: [LLMMessageDTO]] = [:]
    private let store: LLMConversationStore?
    init(store: LLMConversationStore? = nil) {
        self.store = store
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
}
