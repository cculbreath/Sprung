//
//  ArtifactPersistenceHandler.swift
//  Sprung
//
//  Phase 3: Artifact persistence to disk
//  Subscribes to artifact events and persists to InterviewDataStore
//

import Foundation
import SwiftyJSON

/// Handles persistence of artifact records to disk
actor ArtifactPersistenceHandler: OnboardingEventEmitter {
    // MARK: - Properties

    let eventBus: EventCoordinator
    private let dataStore: InterviewDataStore

    private var subscriptionTask: Task<Void, Never>?
    private var isActive = false

    // MARK: - Initialization

    init(eventBus: EventCoordinator, dataStore: InterviewDataStore) {
        self.eventBus = eventBus
        self.dataStore = dataStore
        Logger.info("💾 ArtifactPersistenceHandler initialized", category: .ai)
    }

    // MARK: - Lifecycle

    func start() {
        guard !isActive else { return }
        isActive = true

        subscriptionTask = Task { [weak self] in
            guard let self else { return }

            for await event in await self.eventBus.stream(topic: .artifact) {
                if Task.isCancelled { break }
                await self.handleArtifactEvent(event)
            }
        }

        Logger.info("▶️ ArtifactPersistenceHandler started", category: .ai)
    }

    func stop() {
        guard isActive else { return }
        isActive = false
        subscriptionTask?.cancel()
        subscriptionTask = nil
        Logger.info("⏹️ ArtifactPersistenceHandler stopped", category: .ai)
    }

    // MARK: - Event Handling

    private func handleArtifactEvent(_ event: OnboardingEvent) async {
        guard case .artifactRecordProduced(let record) = event else {
            return
        }

        Logger.info("💾 Persisting artifact record: \(record["id"].stringValue)", category: .ai)

        // Write to InterviewDataStore
        await dataStore.save(
            data: record,
            dataType: "artifact_record",
            filename: "artifact_\(record["id"].stringValue).json"
        )

        // Emit confirmation
        await emit(.artifactRecordPersisted(record: record))
    }
}
