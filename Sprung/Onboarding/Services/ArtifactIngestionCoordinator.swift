//
//  ArtifactIngestionCoordinator.swift
//  Sprung
//
//  Unified coordinator for all artifact ingestion.
//  Manages pending artifacts, notifies LLM, and gates knowledge card generation.
//
import Foundation
import SwiftyJSON

/// Coordinates artifact ingestion from all sources
/// Tracks pending artifacts and notifies LLM when artifacts are ready
actor ArtifactIngestionCoordinator {
    private let eventBus: EventCoordinator
    private let documentKernel: DocumentIngestionKernel
    private let gitKernel: GitIngestionKernel

    /// Currently pending artifacts by ID
    private var pendingArtifacts: [String: PendingArtifact] = [:]

    /// Artifacts grouped by plan item ID for gating
    private var artifactsByPlanItem: [String: Set<String>] = [:]

    init(
        eventBus: EventCoordinator,
        documentKernel: DocumentIngestionKernel,
        gitKernel: GitIngestionKernel
    ) {
        self.eventBus = eventBus
        self.documentKernel = documentKernel
        self.gitKernel = gitKernel
        Logger.info("📦 ArtifactIngestionCoordinator initialized", category: .ai)
    }

    // MARK: - Public API

    /// Ingest a document file (PDF, DOCX, etc.)
    func ingestDocument(
        fileURL: URL,
        planItemId: String?,
        metadata: JSON = JSON()
    ) async {
        do {
            let pending = try await documentKernel.startIngestion(
                source: fileURL,
                planItemId: planItemId,
                metadata: metadata
            )
            trackPending(pending)
            await notifyIngestionStarted(pending)
        } catch {
            Logger.error("❌ Document ingestion failed to start: \(error.localizedDescription)", category: .ai)
            await notifyIngestionFailed(
                filename: fileURL.lastPathComponent,
                source: .document,
                planItemId: planItemId,
                error: error.localizedDescription
            )
        }
    }

    /// Ingest a git repository
    func ingestGitRepository(
        repoURL: URL,
        planItemId: String?
    ) async {
        do {
            let pending = try await gitKernel.startIngestion(
                source: repoURL,
                planItemId: planItemId,
                metadata: JSON()
            )
            trackPending(pending)
            await notifyIngestionStarted(pending)
        } catch {
            Logger.error("❌ Git ingestion failed to start: \(error.localizedDescription)", category: .ai)
            await notifyIngestionFailed(
                filename: repoURL.lastPathComponent,
                source: .gitRepository,
                planItemId: planItemId,
                error: error.localizedDescription
            )
        }
    }

    /// Check if there are pending artifacts for a plan item
    func hasPendingArtifacts(forPlanItem planItemId: String) -> Bool {
        guard let artifactIds = artifactsByPlanItem[planItemId] else { return false }
        return artifactIds.contains { pendingArtifacts[$0]?.status == .pending || pendingArtifacts[$0]?.status == .processing }
    }

    /// Get all pending artifacts for a plan item
    func getPendingArtifacts(forPlanItem planItemId: String) -> [PendingArtifact] {
        guard let artifactIds = artifactsByPlanItem[planItemId] else { return [] }
        return artifactIds.compactMap { pendingArtifacts[$0] }
            .filter { $0.status == .pending || $0.status == .processing }
    }

    /// Get status message for pending artifacts
    func getPendingStatusMessage(forPlanItem planItemId: String) -> String? {
        let pending = getPendingArtifacts(forPlanItem: planItemId)
        guard !pending.isEmpty else { return nil }

        if pending.count == 1 {
            return "Waiting for \(pending[0].filename) to finish processing..."
        } else {
            return "Waiting for \(pending.count) items to finish processing..."
        }
    }

    /// Cancel all active ingestion tasks across all kernels
    func cancelAllIngestion() async {
        Logger.info("🛑 ArtifactIngestionCoordinator: Cancelling all ingestion tasks", category: .ai)
        await documentKernel.cancelAllTasks()
        await gitKernel.cancelAllTasks()

        // Clear pending tracking
        let pendingCount = pendingArtifacts.count
        pendingArtifacts.removeAll()
        artifactsByPlanItem.removeAll()

        Logger.info("✅ Cancelled \(pendingCount) pending artifact(s)", category: .ai)
    }

    // MARK: - Internal: Called by kernels when ingestion completes

    /// Called when a kernel completes ingestion
    func handleIngestionCompleted(pendingId: String, result: IngestionResult) async {
        guard var pending = pendingArtifacts[pendingId] else {
            Logger.warning("⚠️ Completed ingestion for unknown pending ID: \(pendingId)", category: .ai)
            return
        }

        pending.status = .completed
        pendingArtifacts[pendingId] = pending

        // Emit artifact record produced event
        await eventBus.publish(.artifactRecordProduced(record: result.artifactRecord))

        // Notify LLM that artifact is ready
        await eventBus.publish(.artifactIngestionCompleted(result: result, planItemId: pending.planItemId))

        Logger.info("✅ Artifact ingestion completed: \(pending.filename)", category: .ai)
    }

    /// Called when a kernel fails ingestion
    func handleIngestionFailed(pendingId: String, error: String) async {
        guard var pending = pendingArtifacts[pendingId] else {
            Logger.warning("⚠️ Failed ingestion for unknown pending ID: \(pendingId)", category: .ai)
            return
        }

        pending.status = .failed
        pending.statusMessage = error
        pendingArtifacts[pendingId] = pending

        await notifyIngestionFailed(
            filename: pending.filename,
            source: pending.source,
            planItemId: pending.planItemId,
            error: error
        )

        Logger.error("❌ Artifact ingestion failed: \(pending.filename) - \(error)", category: .ai)
    }

    // MARK: - Private Helpers

    private func trackPending(_ pending: PendingArtifact) {
        pendingArtifacts[pending.id] = pending

        if let planItemId = pending.planItemId {
            artifactsByPlanItem[planItemId, default: []].insert(pending.id)
        }
    }

    private func notifyIngestionStarted(_ pending: PendingArtifact) async {
        await eventBus.publish(.processingStateChanged(true, statusMessage: "Processing \(pending.filename)..."))
        await eventBus.publish(.artifactIngestionStarted(pending: pending))
    }

    private func notifyIngestionFailed(filename: String, source: IngestionSource, planItemId: String?, error: String) async {
        var payload = JSON()
        payload["type"].string = "artifact_failed"
        payload["filename"].string = filename
        payload["source"].string = source.rawValue
        if let planItemId = planItemId {
            payload["plan_item_id"].string = planItemId
        }
        payload["error"].string = error

        await eventBus.publish(.llmSendDeveloperMessage(payload: payload))
        await eventBus.publish(.processingStateChanged(false))
    }
}
