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
        switch event {
        case .artifactRecordProduced(let record):
            Logger.info("💾 Persisting artifact record: \(record["id"].stringValue)", category: .ai)

            // Write to InterviewDataStore using the correct persist API
            do {
                let identifier = try await dataStore.persist(dataType: "artifact_record", payload: record)
                Logger.info("✅ Artifact record persisted with identifier: \(identifier)", category: .ai)

                // Emit confirmation
                await emit(.artifactRecordPersisted(record: record))
            } catch {
                Logger.error("❌ Failed to persist artifact record: \(error)", category: .ai)
            }

        case .artifactMetadataUpdated(let artifact):
            // Re-persist the updated artifact to disk
            let artifactId = artifact["id"].stringValue
            Logger.info("💾 Re-persisting updated artifact: \(artifactId)", category: .ai)

            do {
                let identifier = try await dataStore.persist(dataType: "artifact_record", payload: artifact)
                Logger.info("✅ Artifact metadata persisted with identifier: \(identifier)", category: .ai)
            } catch {
                Logger.error("❌ Failed to persist updated artifact: \(error)", category: .ai)
            }

        default:
            break
        }
    }
}
