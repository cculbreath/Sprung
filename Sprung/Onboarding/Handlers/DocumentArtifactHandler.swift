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

        // Categorize files by type
        let extractableExtensions = Set(["pdf", "doc", "docx", "html", "htm", "txt", "rtf"])
        let imageExtensions = Set(["png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "bmp"])

        let extractableFiles = files.filter { file in
            let ext = file.storageURL.pathExtension.lowercased()
            return extractableExtensions.contains(ext)
        }

        let imageFiles = files.filter { file in
            let ext = file.storageURL.pathExtension.lowercased()
            return imageExtensions.contains(ext)
        }

        guard !extractableFiles.isEmpty || !imageFiles.isEmpty else {
            Logger.debug("📄 No processable files in upload batch", category: .ai)
            return
        }

        let totalCount = extractableFiles.count + imageFiles.count
        let isBatch = totalCount > 1

        // Show spinner at start of batch - will remain visible until all files processed
        let initialStatus = isBatch
            ? "Processing \(totalCount) file(s)..."
            : "Processing \(files.first?.filename ?? "file")..."
        await emit(.processingStateChanged(true, statusMessage: initialStatus))

        // Process each file in the batch
        var successCount = 0
        var failedFiles: [String] = []
        var currentIndex = 0

        // Process text-extractable documents
        for file in extractableFiles {
            currentIndex += 1
            let filename = file.filename
            Logger.info("📄 Document detected: \(filename) (\(currentIndex)/\(totalCount))", category: .ai)

            // Update status for current file (keep spinner visible)
            let status = isBatch
                ? "Processing \(filename) (\(currentIndex)/\(totalCount))..."
                : "Processing \(filename)..."
            await emit(.processingStateChanged(true, statusMessage: status))

            do {
                // Call service to perform business logic with status callback
                let idx = currentIndex
                let artifactRecord = try await documentProcessingService.processDocument(
                    fileURL: file.storageURL,
                    documentType: requestKind,
                    callId: callId,
                    metadata: metadata,
                    statusCallback: { [weak self] status in
                        Task {
                            // Update status but keep spinner visible
                            let batchStatus = isBatch ? "[\(idx)/\(totalCount)] \(status)" : status
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

        // Process image files (no text extraction, just create artifact record)
        for file in imageFiles {
            currentIndex += 1
            let filename = file.filename
            Logger.info("🖼️ Image detected: \(filename) (\(currentIndex)/\(totalCount))", category: .ai)

            // Update status for current file
            let status = isBatch
                ? "Adding \(filename) (\(currentIndex)/\(totalCount))..."
                : "Adding \(filename)..."
            await emit(.processingStateChanged(true, statusMessage: status))

            // Create artifact record for image without text extraction
            let artifactRecord = createImageArtifactRecord(
                file: file,
                requestKind: requestKind,
                callId: callId,
                metadata: metadata
            )
            await emit(.artifactRecordProduced(record: artifactRecord))
            successCount += 1
            Logger.info("🖼️ Image artifact created: \(filename)", category: .ai)
        }

        // All files processed - now hide spinner
        if !failedFiles.isEmpty {
            // Show final error summary briefly
            let errorSummary = failedFiles.count == 1
                ? "Failed to process \(failedFiles[0])"
                : "Failed to process \(failedFiles.count) of \(totalCount) files"
            await emit(.processingStateChanged(true, statusMessage: errorSummary))
            try? await Task.sleep(for: .seconds(2))
        }

        // Hide spinner after ALL files in batch are processed
        await emit(.processingStateChanged(false))
        Logger.info("📄 Batch processing complete: \(successCount)/\(totalCount) succeeded", category: .ai)
    }

    /// Create an artifact record for an image file (no text extraction)
    private func createImageArtifactRecord(
        file: ProcessedUploadInfo,
        requestKind: String,
        callId: String?,
        metadata: JSON
    ) -> JSON {
        var record = JSON()
        record["id"].string = UUID().uuidString
        record["filename"].string = file.filename
        record["content_type"].string = file.contentType ?? "image/\(file.storageURL.pathExtension.lowercased())"
        record["storage_url"].string = file.storageURL.absoluteString
        record["document_type"].string = requestKind

        // Get file size
        if let attrs = try? FileManager.default.attributesOfItem(atPath: file.storageURL.path),
           let size = attrs[.size] as? Int {
            record["size_bytes"].int = size
        }

        record["extracted_content"].string = "[Image file - no text extraction]"
        record["extraction_method"].string = "none"
        record["created_at"].string = ISO8601DateFormatter().string(from: Date())

        if let callId {
            record["call_id"].string = callId
        }

        // Copy relevant metadata
        if let targetObjectives = metadata["target_phase_objectives"].array {
            record["metadata"]["target_phase_objectives"] = JSON(targetObjectives)
        }

        return record
    }
}
