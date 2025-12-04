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
actor DocumentIngestionKernel: ArtifactIngestionKernel {
    let kernelType: IngestionSource = .document

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
            startTime: Date(),
            status: .pending,
            statusMessage: "Starting extraction..."
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

    func completeIngestion(pendingId: String) async throws -> IngestionResult {
        // This is called by the coordinator, but for documents we handle completion
        // in the async task. This method exists for protocol conformance.
        throw NSError(domain: "DocumentIngestionKernel", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Document ingestion completes asynchronously via callback"
        ])
    }

    // MARK: - Private

    private func processDocument(
        pendingId: String,
        fileURL: URL,
        planItemId: String?,
        metadata: JSON
    ) async {
        do {
            // Emit processing state
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

            let result = IngestionResult(
                artifactId: record["id"].stringValue,
                artifactRecord: record,
                source: .document
            )

            // Notify coordinator
            await ingestionCoordinator?.handleIngestionCompleted(pendingId: pendingId, result: result)

            await eventBus.publish(.processingStateChanged(false))

        } catch {
            await ingestionCoordinator?.handleIngestionFailed(pendingId: pendingId, error: error.localizedDescription)
            await eventBus.publish(.processingStateChanged(false))
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
