//
//  ArtifactHandler.swift
//  Sprung
//
//  Artifact persistence and indexing reactor (Spec §4.8)
//  Subscribes to artifactRecordProduced events and persists to dataStore
//

import Foundation
import SwiftyJSON

/// Artifact persistence and indexing reactor
/// Responsibilities (Spec §4.8):
/// - Subscribe to .artifactRecordProduced events
/// - Persist artifact records to InterviewDataStore
/// - Emit .artifactRecordPersisted after successful persistence
/// - Does NOT perform extraction (that's in ExtractDocumentTool)
actor ArtifactHandler: OnboardingEventEmitter {
    // MARK: - Properties

    let eventBus: EventCoordinator
    private let dataStore: InterviewDataStore

    // MARK: - Initialization

    init(eventBus: EventCoordinator, dataStore: InterviewDataStore) {
        self.eventBus = eventBus
        self.dataStore = dataStore
        Logger.info("📦 ArtifactHandler initialized as persistence reactor", category: .ai)
    }

    // MARK: - Event Subscriptions

    /// Start listening to artifact events
    func startEventSubscriptions() {
        Task {
            for await event in await eventBus.stream(topic: .artifact) {
                await handle(event)
            }
        }

        Logger.info("📡 ArtifactHandler subscribed to artifact events", category: .ai)
    }

    // MARK: - Event Handlers

    private func handle(_ event: OnboardingEvent) async {
        guard case .artifactRecordProduced(let record) = event else { return }

        Logger.info("📦 Persisting artifact record: \(record["id"].stringValue)", category: .ai)

        do {
            // Persist to dataStore
            _ = try await dataStore.persist(dataType: "artifact_record", payload: record)

            // Emit confirmation event (so state/UI can react)
            await emit(.artifactRecordPersisted(record: record))

            Logger.info("✅ Artifact record persisted: \(record["id"].stringValue)", category: .ai)
        } catch {
            Logger.error("❌ Failed to persist artifact record: \(error)", category: .ai)
        }
    }
}
