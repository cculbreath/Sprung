//
//  DocumentArtifactHandler.swift
//  Sprung
//
//  Thin handler that processes uploaded documents and produces artifact records.
//  Delegates business logic to DocumentProcessingService.
//
import Foundation
@preconcurrency import SwiftyJSON
/// Handles document upload completion by processing files and emitting artifact records
actor DocumentArtifactHandler: OnboardingEventEmitter {
    // MARK: - Properties
    let eventBus: EventCoordinator
    private let documentProcessingService: DocumentProcessingService
    private let agentTracker: AgentActivityTracker

    // MARK: - Configuration

    /// Maximum number of concurrent document extractions (reads from Settings)
    private var maxConcurrentExtractions: Int {
        let settingsValue = UserDefaults.standard.integer(forKey: "onboardingKCAgentMaxConcurrent")
        return settingsValue > 0 ? settingsValue : 5
    }

    // MARK: - Lifecycle State
    private var subscriptionTask: Task<Void, Never>?
    private var isActive = false
    // MARK: - Initialization
    init(
        eventBus: EventCoordinator,
        documentProcessingService: DocumentProcessingService,
        agentTracker: AgentActivityTracker
    ) {
        self.eventBus = eventBus
        self.documentProcessingService = documentProcessingService
        self.agentTracker = agentTracker
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
        let extractableExtensions = Set(["pdf", "docx", "html", "htm", "txt", "rtf"])
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

        // Show extraction indicator at start of batch (non-blocking - chat remains enabled)
        let initialStatus = isBatch
            ? "Extracting \(totalCount) document(s)..."
            : "Extracting \(files.first?.filename ?? "file")..."
        await emit(.extractionStateChanged(true, statusMessage: initialStatus))

        // Process each file in the batch
        var successCount = 0
        var failedFiles: [String] = []

        // Process text-extractable documents IN PARALLEL with concurrency limit
        if !extractableFiles.isEmpty {
            Logger.info("📄 Processing \(extractableFiles.count) documents in parallel (max concurrent: \(maxConcurrentExtractions))", category: .ai)

            let results = await withTaskGroup(of: ExtractionResult.self, returning: [ExtractionResult].self) { group in
                var activeCount = 0
                var fileIndex = 0
                var collectedResults: [ExtractionResult] = []

                // Add initial batch of tasks up to max concurrent
                while fileIndex < extractableFiles.count && activeCount < maxConcurrentExtractions {
                    let file = extractableFiles[fileIndex]
                    let currentIdx = fileIndex + 1
                    fileIndex += 1
                    activeCount += 1

                    group.addTask { [self] in
                        await self.processExtractableDocument(
                            file: file,
                            index: currentIdx,
                            totalCount: totalCount,
                            requestKind: requestKind,
                            callId: callId,
                            metadata: metadata,
                            isBatch: isBatch
                        )
                    }
                }

                // Process results and add new tasks as slots become available
                for await result in group {
                    collectedResults.append(result)
                    activeCount -= 1

                    // Add next file if available
                    if fileIndex < extractableFiles.count {
                        let file = extractableFiles[fileIndex]
                        let currentIdx = fileIndex + 1
                        fileIndex += 1
                        activeCount += 1

                        group.addTask { [self] in
                            await self.processExtractableDocument(
                                file: file,
                                index: currentIdx,
                                totalCount: totalCount,
                                requestKind: requestKind,
                                callId: callId,
                                metadata: metadata,
                                isBatch: isBatch
                            )
                        }
                    }
                }

                return collectedResults
            }

            // Process results - emit artifact records and track failures
            for result in results {
                if let artifactRecord = result.artifactRecord {
                    await emit(.artifactRecordProduced(record: artifactRecord))
                    successCount += 1
                } else {
                    failedFiles.append(result.filename)
                }
            }
        }

        // Track document count for images (processed after extractables)
        var currentIndex = extractableFiles.count

        // Process image files (no text extraction, just create artifact record)
        for file in imageFiles {
            currentIndex += 1
            let filename = file.filename
            Logger.info("🖼️ Image detected: \(filename) (\(currentIndex)/\(totalCount))", category: .ai)

            // Update extraction status for current file
            let status = isBatch
                ? "Adding \(filename) (\(currentIndex)/\(totalCount))..."
                : "Adding \(filename)..."
            await emit(.extractionStateChanged(true, statusMessage: status))

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

        // All files processed - clear extraction indicator
        if !failedFiles.isEmpty {
            // Show final error summary briefly
            let errorSummary = failedFiles.count == 1
                ? "Failed to extract \(failedFiles[0])"
                : "Failed to extract \(failedFiles.count) of \(totalCount) files"
            await emit(.extractionStateChanged(true, statusMessage: errorSummary))
            try? await Task.sleep(for: .seconds(2))
        }

        // Clear extraction indicator after ALL files in batch are processed
        await emit(.extractionStateChanged(false))
        Logger.info("📄 Batch extraction complete: \(successCount)/\(totalCount) succeeded", category: .ai)
    }

    // MARK: - Document Processing Helpers

    /// Result type for parallel document processing
    private struct ExtractionResult: Sendable {
        let filename: String
        let artifactRecord: JSON?
        let error: String?
    }

    /// Process a single extractable document with agent tracking
    private func processExtractableDocument(
        file: ProcessedUploadInfo,
        index: Int,
        totalCount: Int,
        requestKind: String,
        callId: String?,
        metadata: JSON,
        isBatch: Bool
    ) async -> ExtractionResult {
        let filename = file.filename
        let agentId = UUID().uuidString

        // Track this document extraction in Agents tab
        await MainActor.run {
            agentTracker.trackAgent(
                id: agentId,
                type: .documentIngestion,
                name: filename,
                task: nil as Task<Void, Never>?
            )
            agentTracker.appendTranscript(
                agentId: agentId,
                entryType: .system,
                content: "Starting extraction",
                details: "File: \(filename) (\(index)/\(totalCount))"
            )
        }

        Logger.info("📄 Document detected: \(filename) (\(index)/\(totalCount))", category: .ai)

        // Update extraction status for current file
        let status = isBatch
            ? "Extracting \(filename) (\(index)/\(totalCount))..."
            : "Extracting \(filename)..."
        await emit(.extractionStateChanged(true, statusMessage: status))

        do {
            // Call service to perform business logic with status callback
            let artifactRecord = try await documentProcessingService.processDocument(
                fileURL: file.storageURL,
                documentType: requestKind,
                callId: callId,
                metadata: metadata,
                displayFilename: filename,
                statusCallback: { [weak self, agentId] statusMsg in
                    guard let self else { return }
                    Task {
                        // Update extraction status (non-blocking)
                        let batchStatus = isBatch ? "[\(index)/\(totalCount)] \(statusMsg)" : statusMsg
                        await self.emit(.extractionStateChanged(true, statusMessage: batchStatus))

                        // Log to agent transcript
                        await MainActor.run {
                            self.agentTracker.appendTranscript(
                                agentId: agentId,
                                entryType: .system,
                                content: statusMsg
                            )
                        }
                    }
                }
            )

            // Mark agent as completed
            await MainActor.run {
                agentTracker.appendTranscript(
                    agentId: agentId,
                    entryType: .system,
                    content: "Extraction completed",
                    details: "Artifact ID: \(artifactRecord["id"].stringValue)"
                )
                agentTracker.markCompleted(agentId: agentId)
            }

            return ExtractionResult(filename: filename, artifactRecord: artifactRecord, error: nil)
        } catch {
            Logger.error("❌ Document processing failed: \(error.localizedDescription)", category: .ai)

            // Mark agent as failed
            await MainActor.run {
                agentTracker.markFailed(agentId: agentId, error: error.localizedDescription)
            }

            // Show error briefly in status
            let userMessage: String
            if let extractionError = error as? DocumentExtractionService.ExtractionError {
                userMessage = extractionError.userFacingMessage
            } else {
                userMessage = "Failed to extract \(filename)"
            }
            await emit(.extractionStateChanged(true, statusMessage: userMessage))

            return ExtractionResult(filename: filename, artifactRecord: nil, error: error.localizedDescription)
        }
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
