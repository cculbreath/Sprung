//
//  DocumentIngestionKernel.swift
//  Sprung
//
//  Kernel for document ingestion using Gemini-based extraction.
//  Wraps DocumentProcessingService with the unified ingestion protocol.
//
import Foundation
import SwiftyJSON

/// Document ingestion kernel using Gemini (or configured model) for text extraction
actor DocumentIngestionKernel {

    private let documentProcessingService: DocumentProcessingService
    private let eventBus: EventCoordinator
    private weak var ingestionCoordinator: ArtifactIngestionCoordinator?

    /// Active ingestion tasks by pending ID
    private var activeTasks: [String: Task<Void, Never>] = [:]

    init(
        documentProcessingService: DocumentProcessingService,
        eventBus: EventCoordinator
    ) {
        self.documentProcessingService = documentProcessingService
        self.eventBus = eventBus
    }

    func setIngestionCoordinator(_ coordinator: ArtifactIngestionCoordinator) {
        self.ingestionCoordinator = coordinator
    }

    func startIngestion(
        source: URL,
        planItemId: String?,
        metadata: JSON
    ) async throws -> PendingArtifact {
        let pendingId = UUID().uuidString
        let filename = source.lastPathComponent

        let pending = PendingArtifact(
            id: pendingId,
            source: .document,
            filename: filename,
            planItemId: planItemId,
            status: .pending
        )

        // Start async processing
        let task = Task { [weak self] in
            guard let self = self else { return }
            await self.processDocument(
                pendingId: pendingId,
                fileURL: source,
                planItemId: planItemId,
                metadata: metadata
            )
        }
        activeTasks[pendingId] = task

        return pending
    }

    // MARK: - Private

    private func processDocument(
        pendingId: String,
        fileURL: URL,
        planItemId: String?,
        metadata: JSON
    ) async {
        do {
            // Emit processing state (don't emit false - let coordinator manage batch state)
            await eventBus.publish(.processingStateChanged(true, statusMessage: "Extracting text from \(fileURL.lastPathComponent)..."))

            let artifactRecord = try await documentProcessingService.processDocument(
                fileURL: fileURL,
                documentType: metadata["document_type"].string ?? "evidence",
                callId: nil,
                metadata: metadata,
                statusCallback: { [weak self] status in
                    Task {
                        await self?.eventBus.publish(.processingStateChanged(true, statusMessage: status))
                    }
                }
            )

            // Add plan item ID to artifact record
            var record = artifactRecord
            if let planItemId = planItemId {
                record["plan_item_id"].string = planItemId
            }

            let result = IngestionResult(artifactRecord: record)

            // Notify coordinator (coordinator manages processing state for batches)
            await ingestionCoordinator?.handleIngestionCompleted(pendingId: pendingId, result: result)

            // Note: We don't emit processingStateChanged(false) here because:
            // 1. For batches, this would hide spinner before all files are done
            // 2. The coordinator or LLM response handler should manage the final state

        } catch {
            await ingestionCoordinator?.handleIngestionFailed(pendingId: pendingId, error: error.localizedDescription)
            // Note: Don't emit processingStateChanged(false) - let coordinator handle it
        }

        // Clean up task reference
        activeTasks[pendingId] = nil
    }

    /// Cancel all active document extraction tasks
    func cancelAllTasks() async {
        Logger.info("🛑 DocumentIngestionKernel: Cancelling \(activeTasks.count) active task(s)", category: .ai)
        for (pendingId, task) in activeTasks {
            task.cancel()
            Logger.debug("Cancelled document extraction task: \(pendingId)", category: .ai)
        }
        activeTasks.removeAll()
    }
}
