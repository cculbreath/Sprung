//
//  ArtifactArchiveManager.swift
//  Sprung
//
//  Manages artifact archive operations: promotion, demotion, deletion, and JSON conversion.
//  Extracted from OnboardingInterviewCoordinator to follow Single Responsibility Principle.
//

import Foundation
import SwiftyJSON

/// Result of a demote operation, containing info needed for LLM notification
struct DemoteResult {
    let artifactId: String
    let filename: String
    let success: Bool
}

/// Manages artifact archive operations: promotion from archive to session,
/// demotion from session to archive, and permanent deletion.
@MainActor
final class ArtifactArchiveManager {
    private let artifactRecordStore: ArtifactRecordStore
    private let artifactRepository: ArtifactRepository
    private let sessionPersistenceHandler: SwiftDataSessionPersistenceHandler
    private let eventBus: EventCoordinator

    init(
        artifactRecordStore: ArtifactRecordStore,
        artifactRepository: ArtifactRepository,
        sessionPersistenceHandler: SwiftDataSessionPersistenceHandler,
        eventBus: EventCoordinator
    ) {
        self.artifactRecordStore = artifactRecordStore
        self.artifactRepository = artifactRepository
        self.sessionPersistenceHandler = sessionPersistenceHandler
        self.eventBus = eventBus
    }

    // MARK: - Accessors

    /// Get archived artifacts for UI display (directly from SwiftData)
    var archivedArtifacts: [ArtifactRecord] {
        artifactRecordStore.archivedArtifacts
    }

    /// Get current session artifacts for UI display (directly from SwiftData)
    func currentSessionArtifacts() -> [ArtifactRecord] {
        guard let session = sessionPersistenceHandler.getActiveSession() else { return [] }
        return artifactRecordStore.artifacts(for: session)
    }

    // MARK: - Promotion

    /// Promote multiple archived artifacts to the current session as a batch.
    /// Emits batchUploadStarted to trigger DocumentArtifactMessenger collection.
    func promoteArchivedArtifacts(ids: [String]) async {
        Logger.info("📦 promoteArchivedArtifacts called with \(ids.count) ID(s)", category: .ai)
        guard !ids.isEmpty else {
            Logger.warning("📦 promoteArchivedArtifacts: Empty IDs array, returning early", category: .ai)
            return
        }

        guard let session = sessionPersistenceHandler.getActiveSession() else {
            Logger.warning("Cannot promote artifacts: no active session", category: .ai)
            return
        }
        Logger.info("📦 promoteArchivedArtifacts: Active session found", category: .ai)

        // Collect valid artifacts first
        var artifactsToPromote: [(artifact: ArtifactRecord, json: JSON)] = []
        for id in ids {
            if let artifact = artifactRecordStore.artifact(byIdString: id) {
                let json = artifactRecordToJSON(artifact)
                artifactsToPromote.append((artifact, json))
                Logger.debug("📦 Found artifact to promote: \(artifact.filename)", category: .ai)
            } else {
                Logger.warning("Cannot promote artifact: not found in SwiftData: \(id)", category: .ai)
            }
        }

        guard !artifactsToPromote.isEmpty else {
            Logger.warning("📦 promoteArchivedArtifacts: No valid artifacts found to promote", category: .ai)
            return
        }

        // Start batch by emitting batchUploadStarted (triggers DocumentArtifactMessenger to collect)
        await eventBus.publish(.processing(.batchUploadStarted(expectedCount: artifactsToPromote.count)))
        Logger.info("📦 Starting batch promotion of \(artifactsToPromote.count) archived artifact(s)", category: .ai)

        // Promote each artifact
        for (artifact, json) in artifactsToPromote {
            // Update SwiftData: move artifact to current session
            artifactRecordStore.promoteArtifact(artifact, to: session)

            // Add to in-memory artifact list
            await artifactRepository.addArtifactRecord(json)

            // Emit event (will be batched by DocumentArtifactMessenger)
            await eventBus.publish(.artifact(.recordProduced(record: json)))

            Logger.info("📦 Promoted archived artifact: \(artifact.filename)", category: .ai)
        }
    }

    /// Promote a single archived artifact to the current session.
    func promoteArchivedArtifact(id: String) async {
        await promoteArchivedArtifacts(ids: [id])
    }

    // MARK: - Deletion

    /// Permanently delete an archived artifact.
    /// This removes the artifact from SwiftData - it cannot be recovered.
    func deleteArchivedArtifact(id: String) {
        guard let artifact = artifactRecordStore.artifact(byIdString: id) else {
            Logger.warning("Cannot delete archived artifact: not found: \(id)", category: .ai)
            return
        }

        let filename = artifact.filename

        // Delete from SwiftData
        artifactRecordStore.deleteArtifact(artifact)

        Logger.info("🗑️ Permanently deleted archived artifact: \(filename)", category: .ai)
    }

    // MARK: - Demotion

    /// Demote an artifact from the current session to archived status.
    /// Returns result containing info needed for LLM notification.
    func demoteArtifact(id: String) async -> DemoteResult {
        guard let artifact = artifactRecordStore.artifact(byIdString: id) else {
            Logger.warning("Cannot demote artifact: not found: \(id)", category: .ai)
            return DemoteResult(artifactId: id, filename: "", success: false)
        }

        let filename = artifact.filename

        // Demote in SwiftData (removes from session, keeps artifact)
        artifactRecordStore.demoteArtifact(artifact)

        // Remove from in-memory current artifacts
        _ = await artifactRepository.deleteArtifactRecord(id: id)

        Logger.info("📦 Demoted artifact to archive: \(filename)", category: .ai)

        return DemoteResult(artifactId: id, filename: filename, success: true)
    }

    // MARK: - JSON Conversion

    /// Convert ArtifactRecord to JSON format.
    /// Uses metadataJSON as base to preserve all fields (skills, narrative cards, summary, etc.)
    func artifactRecordToJSON(_ record: ArtifactRecord) -> JSON {
        // Start with the full persisted record (includes skills, narrative cards, metadata, etc.)
        var json: JSON
        if let metadataJSON = record.metadataJSON,
           let data = metadataJSON.data(using: .utf8),
           let fullRecord = try? JSON(data: data) {
            json = fullRecord
        } else {
            json = JSON()
        }

        // Override with canonical SwiftData fields (in case of any discrepancy)
        json["id"].string = record.id.uuidString
        json["sourceType"].string = record.sourceType
        json["filename"].string = record.filename
        json["extractedText"].string = record.extractedContent
        json["sourceHash"].string = record.sha256
        json["rawFilePath"].string = record.rawFileRelativePath
        json["planItemId"].string = record.planItemId
        json["ingestedAt"].string = ISO8601DateFormatter().string(from: record.ingestedAt)
        json["summary"].string = record.summary
        json["briefDescription"].string = record.briefDescription
        json["title"].string = record.title
        json["contentType"].string = record.contentType
        json["sizeBytes"].int = record.sizeInBytes
        json["hasSkills"].bool = record.hasSkills
        json["hasNarrativeCards"].bool = record.hasNarrativeCards
        json["skills"].string = record.skillsJSON
        json["narrativeCards"].string = record.narrativeCardsJSON

        return json
    }
}
