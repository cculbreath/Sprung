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
    private let stateCoordinator: StateCoordinator

    // MARK: - Configuration

    /// Maximum number of concurrent document extractions
    private var maxConcurrentExtractions: Int {
        let settingsValue = UserDefaults.standard.integer(forKey: "onboardingMaxConcurrentExtractions")
        return settingsValue > 0 ? settingsValue : 5
    }

    // MARK: - Processing Queue
    /// Queued files waiting to be processed
    private var pendingFiles: [QueuedFile] = []
    /// Currently processing count
    private var activeProcessingCount = 0
    /// Task for queue processing
    private var queueProcessingTask: Task<Void, Never>?

    /// Represents a file queued for processing
    private struct QueuedFile {
        let file: ProcessedUploadInfo
        let requestKind: String
        let callId: String?
        let metadata: JSON
    }

    // MARK: - Lifecycle State
    private var subscriptionTask: Task<Void, Never>?
    private var isActive = false
    // MARK: - Initialization
    init(
        eventBus: EventCoordinator,
        documentProcessingService: DocumentProcessingService,
        agentTracker: AgentActivityTracker,
        stateCoordinator: StateCoordinator
    ) {
        self.eventBus = eventBus
        self.documentProcessingService = documentProcessingService
        self.agentTracker = agentTracker
        self.stateCoordinator = stateCoordinator
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

    /// Handle upload event by quickly queueing files and starting processing.
    /// Returns immediately - processing happens asynchronously.
    private func handleEvent(_ event: OnboardingEvent) async {
        guard case .artifact(.uploadCompleted(let files, let requestKind, let callId, let metadata)) = event else {
            return
        }
        // Skip targeted uploads (e.g., profile photos with target_key="basics.image")
        // These are handled directly by UploadInteractionHandler and don't need text extraction
        if metadata["target_key"].string != nil {
            Logger.debug("📄 Skipping targeted upload (target_key present) - not a document for extraction", category: .ai)
            return
        }

        // Categorize and queue files by type using centralized policy
        var queuedCount = 0

        for file in files {
            let ext = file.storageURL.pathExtension.lowercased()

            if DocumentTypePolicy.isExtractable(ext) {
                // Special case: Resume PDFs sent directly to LLM (skip extraction pipeline)
                // This allows the LLM to read the PDF natively without skills extraction
                if requestKind == "resume" && ext == "pdf" {
                    await sendPDFDirectlyToLLM(file: file, requestKind: requestKind, callId: callId, metadata: metadata)
                    continue
                }

                // Queue extractable documents for normal processing
                pendingFiles.append(QueuedFile(
                    file: file,
                    requestKind: requestKind,
                    callId: callId,
                    metadata: metadata
                ))
                queuedCount += 1
                Logger.info("📄 Queued for extraction: \(file.filename) (queue size: \(pendingFiles.count))", category: .ai)
            } else if DocumentTypePolicy.isImage(ext) {
                // Images are fast - process immediately inline
                let artifactRecord = createImageArtifactRecord(
                    file: file,
                    requestKind: requestKind,
                    callId: callId,
                    metadata: metadata
                )
                await emit(.artifact(.recordProduced(record: artifactRecord)))
                Logger.info("🖼️ Image artifact created: \(file.filename)", category: .ai)
            }
        }

        // Update extraction status to show queue state
        if queuedCount > 0 {
            updateExtractionStatus()
            // Kick off queue processing if not already running
            startQueueProcessingIfNeeded()
        }
    }

    /// Update extraction status to reflect current queue state
    private func updateExtractionStatus() {
        let pending = pendingFiles.count
        let active = activeProcessingCount

        if pending == 0 && active == 0 {
            Task { await emit(.processing(.extractionStateChanged(inProgress: false, statusMessage: nil))) }
        } else {
            let status: String
            if pending > 0 && active > 0 {
                status = "Processing \(active) document(s), \(pending) queued..."
            } else if active > 0 {
                status = "Processing \(active) document(s)..."
            } else {
                status = "\(pending) document(s) queued..."
            }
            Task { await emit(.processing(.extractionStateChanged(inProgress: true, statusMessage: status))) }
        }
    }

    /// Start queue processing task if not already running
    private func startQueueProcessingIfNeeded() {
        guard queueProcessingTask == nil else { return }

        queueProcessingTask = Task { [weak self] in
            guard let self else { return }
            await self.processQueue()
            await self.clearQueueTask()
        }
    }

    /// Clear the queue processing task reference (must be called from actor context)
    private func clearQueueTask() {
        queueProcessingTask = nil
    }

    /// Process files from the queue with controlled concurrency using TaskGroup
    private func processQueue() async {
        await withTaskGroup(of: Void.self) { group in
            var fileIterator = pendingFiles.makeIterator()
            pendingFiles.removeAll()  // Clear the pending list as we're processing them

            // Start initial batch up to max concurrency
            var activeCount = 0
            while activeCount < maxConcurrentExtractions,
                  let file = fileIterator.next() {
                activeProcessingCount += 1
                activeCount += 1
                updateExtractionStatus()
                group.addTask { [weak self] in
                    guard let self else { return }
                    await self.processQueuedFile(file)
                }
            }

            // As tasks complete, start new ones
            for await _ in group {
                activeProcessingCount -= 1
                activeCount -= 1
                updateExtractionStatus()

                if let file = fileIterator.next() {
                    activeProcessingCount += 1
                    activeCount += 1
                    updateExtractionStatus()
                    group.addTask { [weak self] in
                        guard let self else { return }
                        await self.processQueuedFile(file)
                    }
                }
            }
        }

        // All done - clear extraction indicator
        await emit(.processing(.extractionStateChanged(inProgress: false, statusMessage: nil)))
        Logger.info("📄 Queue processing complete", category: .ai)
    }

    /// Process a single queued file
    private func processQueuedFile(_ queuedFile: QueuedFile) async {
        let file = queuedFile.file
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
                details: "File: \(filename)"
            )
        }

        Logger.info("📄 Processing document: \(filename)", category: .ai)

        do {
            // Call service to perform business logic with status callback
            let artifactRecord = try await documentProcessingService.processDocument(
                fileURL: file.storageURL,
                documentType: queuedFile.requestKind,
                callId: queuedFile.callId,
                metadata: queuedFile.metadata,
                displayFilename: filename,
                statusCallback: { [weak self, agentId, filename] statusMsg in
                    guard let self else { return }
                    Task {
                        // Update extraction status
                        let pending = await self.pendingFiles.count
                        let queueInfo = pending > 0 ? " (+\(pending) queued)" : ""
                        await self.emit(.processing(.extractionStateChanged(inProgress: true, statusMessage: "\(filename): \(statusMsg)\(queueInfo)")))

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

            await emit(.artifact(.recordProduced(record: artifactRecord)))
            Logger.info("✅ Document processed: \(filename)", category: .ai)

        } catch {
            Logger.error("❌ Document processing failed: \(error.localizedDescription)", category: .ai)

            // Mark agent as failed
            await MainActor.run {
                agentTracker.markFailed(agentId: agentId, error: error.localizedDescription)
            }

            // Show error briefly
            let userMessage: String
            if let extractionError = error as? DocumentExtractionService.ExtractionError {
                userMessage = extractionError.userFacingMessage
            } else {
                userMessage = "Failed to extract \(filename)"
            }
            await emit(.processing(.extractionStateChanged(inProgress: true, statusMessage: userMessage)))
            try? await Task.sleep(for: .seconds(2))
        }
        // Note: activeProcessingCount is managed by the TaskGroup in processQueue()
    }

    // MARK: - Image Artifact Helpers

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

    // MARK: - Direct PDF Sending

    /// Send a PDF file directly to the LLM without extraction pipeline.
    /// Used for resume uploads to allow the LLM to read the document natively
    /// without skills extraction or knowledge card generation.
    ///
    /// The PDF is sent as a user message with PDF data attachment.
    private func sendPDFDirectlyToLLM(
        file: ProcessedUploadInfo,
        requestKind: String,
        callId: String?,
        metadata: JSON
    ) async {
        let filename = file.filename

        Logger.info("📄 Sending resume PDF directly to LLM: \(filename)", category: .ai)

        // Read PDF file as base64
        guard let pdfData = try? Data(contentsOf: file.storageURL) else {
            Logger.error("❌ Failed to read PDF file: \(filename)", category: .ai)
            return
        }

        let pdfBase64 = pdfData.base64EncodedString()
        let sizeKB = pdfData.count / 1024

        // Build UI action result with PDF attachment info
        var result = JSON()
        result["status"].string = "completed"
        result["message"].string = "Resume PDF attached below. Please review to understand the user's professional background."
        var pdfAttachment = JSON()
        pdfAttachment["storage_url"].string = file.storageURL.path
        pdfAttachment["filename"].string = filename
        pdfAttachment["size_kb"].int = sizeKB
        result["pdf_attachment"] = pdfAttachment

        let resultString = result.rawString() ?? "{}"

        // Build user message with ui-action-result tags and PDF data
        let taggedMessage = "<ui-action-result tool=\"\(OnboardingToolName.getUserUpload.rawValue)\">\n\(resultString)\n</ui-action-result>"
        var payload = JSON()
        payload["text"].string = taggedMessage
        // Include PDF data for LLM to see the document
        payload["pdf_data"].string = pdfBase64
        payload["pdf_filename"].string = filename
        payload["pdf_size_kb"].int = sizeKB

        await emit(.llm(.sendUserMessage(payload: payload, isSystemGenerated: true)))
        Logger.info("✅ Resume PDF sent as ui-action-result: \(filename) (\(sizeKB) KB)", category: .ai)
    }
}
