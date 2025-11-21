//
//  TranscriptPersistenceHandler.swift
//  Sprung
//
//  Phase 1: Transcript persistence to disk
//  Subscribes to LLM events and persists transcript records as JSON
//

import Foundation
import SwiftyJSON

/// Handles persistence of transcript records to disk
/// Listens to user message sends and assistant message finalizations
actor TranscriptPersistenceHandler: OnboardingEventEmitter {
    // MARK: - Properties
    let eventBus: EventCoordinator
    private let dataStore: InterviewDataStore

    private var subscriptionTask: Task<Void, Never>?
    private var isActive = false

    // MARK: - Initialization
    init(eventBus: EventCoordinator, dataStore: InterviewDataStore) {
        self.eventBus = eventBus
        self.dataStore = dataStore
        Logger.info("📝 TranscriptPersistenceHandler initialized", category: .ai)
    }

    // MARK: - Lifecycle
    func start() {
        guard !isActive else { return }
        isActive = true

        subscriptionTask = Task { [weak self] in
            guard let self else { return }

            for await event in await self.eventBus.stream(topic: .llm) {
                if Task.isCancelled { break }
                await self.handleLLMEvent(event)
            }
        }

        Logger.info("▶️ TranscriptPersistenceHandler started", category: .ai)
    }

    func stop() {
        guard isActive else { return }
        isActive = false
        subscriptionTask?.cancel()
        subscriptionTask = nil
        Logger.info("⏹️ TranscriptPersistenceHandler stopped", category: .ai)
    }

    // MARK: - Event Handling
    private func handleLLMEvent(_ event: OnboardingEvent) async {
        switch event {
        case .llmUserMessageSent(let messageId, let payload, _):
            await persistUserMessage(messageId: messageId, payload: payload)

        case .streamingMessageFinalized(let id, let finalText, _, _):
            await persistAssistantMessage(id: id, finalText: finalText)

        default:
            break
        }
    }

    // MARK: - Private Methods
    private func persistUserMessage(messageId: String, payload: JSON) async {
        // Extract text from payload
        guard let text = payload["text"].string else {
            Logger.warning("📝 Cannot persist user message: missing text in payload", category: .ai)
            return
        }

        // Build transcript record
        let record: JSON = [
            "id": messageId,
            "role": "user",
            "text": text,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]

        Logger.info("📝 Persisting user transcript record: \(messageId)", category: .ai)

        do {
            let identifier = try await dataStore.persist(dataType: "transcript_record", payload: record)
            Logger.info("✅ User transcript record persisted with identifier: \(identifier)", category: .ai)
        } catch {
            Logger.error("❌ Failed to persist user transcript record: \(error)", category: .ai)
        }
    }

    private func persistAssistantMessage(id: UUID, finalText: String) async {
        // Build transcript record
        let record: JSON = [
            "id": id.uuidString,
            "role": "assistant",
            "text": finalText,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]

        Logger.info("📝 Persisting assistant transcript record: \(id)", category: .ai)

        do {
            let identifier = try await dataStore.persist(dataType: "transcript_record", payload: record)
            Logger.info("✅ Assistant transcript record persisted with identifier: \(identifier)", category: .ai)
        } catch {
            Logger.error("❌ Failed to persist assistant transcript record: \(error)", category: .ai)
        }
    }
}
