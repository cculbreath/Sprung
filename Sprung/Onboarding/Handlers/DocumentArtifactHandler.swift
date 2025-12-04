//
//  DocumentArtifactHandler.swift
//  Sprung
//
//  Thin handler that processes uploaded documents and produces artifact records.
//  Delegates business logic to DocumentProcessingService.
//
import Foundation
import SwiftyJSON
/// Handles document upload completion by processing files and emitting artifact records
actor DocumentArtifactHandler: OnboardingEventEmitter {
    // MARK: - Properties
    let eventBus: EventCoordinator
    private let documentProcessingService: DocumentProcessingService
    // MARK: - Lifecycle State
    private var subscriptionTask: Task<Void, Never>?
    private var isActive = false
    // MARK: - Initialization
    init(
        eventBus: EventCoordinator,
        documentProcessingService: DocumentProcessingService
    ) {
        self.eventBus = eventBus
        self.documentProcessingService = documentProcessingService
        Logger.info("📄 DocumentArtifactHandler initialized", category: .ai)
    }
    // MARK: - Lifecycle
    func start() {
        guard !isActive else { return }
        isActive = true
        subscriptionTask = Task { [weak self] in
            guard let self else { return }
            for await event in await self.eventBus.stream(topic: .artifact) {
                if Task.isCancelled { break }
                await self.handleEvent(event)
            }
        }
        Logger.info("▶️ DocumentArtifactHandler started", category: .ai)
    }
    func stop() {
        guard isActive else { return }
        isActive = false
        subscriptionTask?.cancel()
        subscriptionTask = nil
        Logger.info("⏹️ DocumentArtifactHandler stopped", category: .ai)
    }
    // MARK: - Event Handling
    private func handleEvent(_ event: OnboardingEvent) async {
        guard case .uploadCompleted(let files, let requestKind, let callId, let metadata) = event else {
            return
        }
        // Skip targeted uploads (e.g., profile photos with target_key="basics.image")
        // These are handled directly by UploadInteractionHandler and don't need text extraction
        if metadata["target_key"].string != nil {
            Logger.debug("📄 Skipping targeted upload (target_key present) - not a document for extraction", category: .ai)
            return
        }

        // Filter to extractable document types
        let extractableExtensions = Set(["pdf", "doc", "docx", "html", "htm", "txt", "rtf"])
        let extractableFiles = files.filter { file in
            let ext = file.storageURL.pathExtension.lowercased()
            return extractableExtensions.contains(ext)
        }

        guard !extractableFiles.isEmpty else {
            Logger.debug("📄 No extractable documents in upload batch", category: .ai)
            return
        }

        let batchCount = extractableFiles.count
        let isBatch = batchCount > 1

        // Show spinner at start of batch - will remain visible until all files processed
        let initialStatus = isBatch
            ? "Processing \(batchCount) documents..."
            : "Processing \(extractableFiles[0].filename)..."
        await emit(.processingStateChanged(true, statusMessage: initialStatus))

        // Process each file in the batch
        var successCount = 0
        var failedFiles: [String] = []

        for (index, file) in extractableFiles.enumerated() {
            let filename = file.filename
            Logger.info("📄 Document detected: \(filename) (\(index + 1)/\(batchCount))", category: .ai)

            // Update status for current file (keep spinner visible)
            let status = isBatch
                ? "Processing \(filename) (\(index + 1)/\(batchCount))..."
                : "Processing \(filename)..."
            await emit(.processingStateChanged(true, statusMessage: status))

            do {
                // Call service to perform business logic with status callback
                let artifactRecord = try await documentProcessingService.processDocument(
                    fileURL: file.storageURL,
                    documentType: requestKind,
                    callId: callId,
                    metadata: metadata,
                    statusCallback: { [weak self] status in
                        Task {
                            // Update status but keep spinner visible
                            let batchStatus = isBatch ? "[\(index + 1)/\(batchCount)] \(status)" : status
                            await self?.emit(.processingStateChanged(true, statusMessage: batchStatus))
                        }
                    }
                )
                // Emit artifact record produced event (don't hide spinner yet)
                await emit(.artifactRecordProduced(record: artifactRecord))
                successCount += 1
            } catch {
                Logger.error("❌ Document processing failed: \(error.localizedDescription)", category: .ai)
                failedFiles.append(filename)

                // Show error briefly in status (keep spinner visible for batch)
                let userMessage: String
                if let extractionError = error as? DocumentExtractionService.ExtractionError {
                    userMessage = extractionError.userFacingMessage
                } else {
                    userMessage = "Failed to process \(filename)"
                }
                await emit(.processingStateChanged(true, statusMessage: userMessage))
                // Brief delay so user can see the error message
                try? await Task.sleep(for: .seconds(2))
            }
        }

        // All files processed - now hide spinner
        if !failedFiles.isEmpty {
            // Show final error summary briefly
            let errorSummary = failedFiles.count == 1
                ? "Failed to process \(failedFiles[0])"
                : "Failed to process \(failedFiles.count) of \(batchCount) documents"
            await emit(.processingStateChanged(true, statusMessage: errorSummary))
            try? await Task.sleep(for: .seconds(2))
        }

        // Hide spinner after ALL files in batch are processed
        await emit(.processingStateChanged(false))
        Logger.info("📄 Batch processing complete: \(successCount)/\(batchCount) succeeded", category: .ai)
    }
}
