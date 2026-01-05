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
    private let documentProcessingService: DocumentProcessingService

    /// Currently pending artifacts by ID
    private var pendingArtifacts: [String: PendingArtifact] = [:]

    /// Artifacts grouped by plan item ID for gating
    private var artifactsByPlanItem: [String: Set<String>] = [:]

    init(
        eventBus: EventCoordinator,
        documentKernel: DocumentIngestionKernel,
        gitKernel: GitIngestionKernel,
        documentProcessingService: DocumentProcessingService
    ) {
        self.eventBus = eventBus
        self.documentKernel = documentKernel
        self.gitKernel = gitKernel
        self.documentProcessingService = documentProcessingService
        Logger.info("📦 ArtifactIngestionCoordinator initialized", category: .ai)
    }

    // MARK: - Public API

    /// Process an evidence upload and store as artifact (Phase 2 evidence requirements)
    func handleEvidenceUpload(url: URL, requirementId: String) async {
        Logger.info("📎 Handling evidence upload for requirement: \(requirementId)", category: .ai)
        await eventBus.publish(.processingStateChanged(true, statusMessage: "Processing evidence..."))

        do {
            var metadata = JSON()
            metadata["evidence_requirement_id"].string = requirementId

            let record = try await documentProcessingService.processDocument(
                fileURL: url,
                documentType: "evidence",
                callId: nil,
                metadata: metadata
            )
            await eventBus.publish(.artifactRecordProduced(record: record))
            Logger.info("✅ Evidence processed and artifact stored (ID: \(record["id"].stringValue))", category: .ai)
        } catch {
            Logger.error("❌ Evidence upload failed: \(error.localizedDescription)", category: .ai)
            await eventBus.publish(.errorOccurred("Failed to process evidence: \(error.localizedDescription)"))
        }

        await eventBus.publish(.processingStateChanged(false))
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
        // DocumentArtifactMessenger handles this:
        // - PDF artifacts are batched and sent as user messages
        // - Git artifacts are sent as developer messages (queued until next user action)
        await eventBus.publish(.artifactRecordProduced(record: result.artifactRecord))

        // Note: We no longer send a separate artifactIngestionCompleted user message for git repos.
        // The developer message from DocumentArtifactMessenger.sendGitArtifact() contains
        // the full analysis and will be bundled with the next user action.

        Logger.info("✅ Artifact ingestion completed: \(pending.filename)", category: .ai)
    }

    /// Called when a kernel fails ingestion
    func handleIngestionFailed(pendingId: String, error: String) async {
        guard var pending = pendingArtifacts[pendingId] else {
            Logger.warning("⚠️ Failed ingestion for unknown pending ID: \(pendingId)", category: .ai)
            return
        }

        pending.status = .failed
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
        // Only trigger blocking processing state for documents, not git repos
        // Git repos run in background via AgentActivityTracker and use extractionStateChanged
        if pending.source != .gitRepository {
            await eventBus.publish(.processingStateChanged(true, statusMessage: "Processing \(pending.filename)..."))
        }
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

        await eventBus.publish(.llmSendCoordinatorMessage(payload: payload))
        await eventBus.publish(.processingStateChanged(false))
    }
}
