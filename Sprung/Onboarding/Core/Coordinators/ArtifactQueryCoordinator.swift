import Foundation
import SwiftyJSON

/// Consolidates artifact read operations and metadata updates.
/// Provides a clean interface for querying artifacts from the state.
@MainActor
final class ArtifactQueryCoordinator {
    // MARK: - Dependencies
    private let state: StateCoordinator
    private let eventBus: EventCoordinator

    // MARK: - Initialization
    init(state: StateCoordinator, eventBus: EventCoordinator) {
        self.state = state
        self.eventBus = eventBus
    }

    // MARK: - Artifact Queries

    /// List summaries of all artifacts.
    func listArtifactSummaries() async -> [JSON] {
        await state.listArtifactSummaries()
    }

    /// List all artifact records.
    func listArtifactRecords() async -> [JSON] {
        await state.artifacts.artifactRecords
    }

    /// Get a specific artifact record by ID.
    func getArtifactRecord(id: String) async -> JSON? {
        await state.getArtifactRecord(id: id)
    }

    /// Get a specific artifact (experience card or writing sample) by ID.
    func getArtifact(id: String) async -> JSON? {
        let artifacts = await state.artifacts
        if let card = artifacts.experienceCards.first(where: { $0["id"].string == id }) {
            return card
        }
        if let sample = artifacts.writingSamples.first(where: { $0["id"].string == id }) {
            return sample
        }
        return nil
    }

    // MARK: - Artifact Updates

    /// Request an update to artifact metadata.
    func requestMetadataUpdate(artifactId: String, updates: JSON) async {
        await eventBus.publish(.artifactMetadataUpdateRequested(artifactId: artifactId, updates: updates))
    }

    /// Cancel an upload request.
    func cancelUploadRequest(id: UUID) async {
        await eventBus.publish(.uploadRequestCancelled(id: id))
    }
}
