//
//  TranscriptPersistenceService.swift
//  Sprung
//
//  Phase 1: Transcript persistence to disk
//  Subscribes to LLM events and persists transcript records as JSON
//
import Foundation
import SwiftyJSON
/// Handles persistence of transcript records to disk
/// Listens to user message sends and assistant message finalizations
actor TranscriptPersistenceService: OnboardingEventEmitter {
    // MARK: - Properties
    let eventBus: EventBus
    private let dataStore: InterviewDataStore
    private var subscriptionTask: Task<Void, Never>?
    private var isActive = false

    /// Accumulates descriptions of transcript records that failed to persist.
    /// Non-empty means the replay tape is incomplete; exposed for diagnostics
    /// (e.g. debug UI or session-summary logging).
    private(set) var recordingIntegrityIssues: [String] = []
    // MARK: - Initialization
    init(eventBus: EventBus, dataStore: InterviewDataStore) {
        self.eventBus = eventBus
        self.dataStore = dataStore
        Logger.info("📝 TranscriptPersistenceService initialized", category: .ai)
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
        Logger.info("▶️ TranscriptPersistenceService started", category: .ai)
    }
    // MARK: - Event Handling
    private func handleLLMEvent(_ event: OnboardingEvent) async {
        switch event {
        case .llm(.userMessageSent(let messageId, let payload, _)):
            await persistUserMessage(messageId: messageId, payload: payload)
        case .llm(.streamingMessageFinalized(let id, let finalText, _, _)):
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
            recordingIntegrityIssues.append("user:\(messageId) — \(error.localizedDescription)")
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
            recordingIntegrityIssues.append("assistant:\(id) — \(error.localizedDescription)")
        }
    }
}
