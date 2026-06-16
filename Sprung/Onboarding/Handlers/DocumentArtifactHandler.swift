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
    let eventBus: EventBus
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
    /// Queued files waiting for a free extraction slot
    private var pendingFiles: [QueuedFile] = []
    /// Currently processing count (occupied extraction slots)
    private var activeProcessingCount = 0

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
        eventBus: EventBus,
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
        // Skip targeted uploads (e.g., profile photos with targetKey="basics.image")
        // These are handled directly by UploadInteractionHandler and don't need text extraction
        if metadata["targetKey"].string != nil {
            Logger.debug("📄 Skipping targeted upload (targetKey present) - not a document for extraction", category: .ai)
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

        // Newly queued files claim free extraction slots immediately — they
        // run alongside any in-flight extractions rather than waiting for one
        // to finish.
        if queuedCount > 0 {
            pumpQueue()
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

    /// Fill every free extraction slot from the pending queue. Called on every
    /// enqueue and on every completion, so late-arriving files start the moment
    /// a slot is free — immediately when concurrency allows, not after an
    /// in-flight document finishes. Actor isolation serializes slot accounting.
    private func pumpQueue() {
        while activeProcessingCount < maxConcurrentExtractions, !pendingFiles.isEmpty {
            let queued = pendingFiles.removeFirst()
            activeProcessingCount += 1
            Task { [weak self] in
                guard let self else { return }
                await self.processQueuedFile(queued)
                await self.extractionSlotFreed()
            }
        }
        updateExtractionStatus()
    }

    /// Release a slot after an extraction finishes and pull the next file.
    private func extractionSlotFreed() {
        activeProcessingCount -= 1
        if pendingFiles.isEmpty && activeProcessingCount == 0 {
            Logger.info("📄 Queue processing complete", category: .ai)
        }
        pumpQueue()
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

            // Mark agent as completed, noting any analysis passes that failed
            let extractionFailures = artifactRecord["extractionFailures"].arrayValue.map(\.stringValue)
            await MainActor.run {
                for failure in extractionFailures {
                    agentTracker.appendTranscript(
                        agentId: agentId,
                        entryType: .error,
                        content: "Analysis pass failed",
                        details: failure
                    )
                }
                agentTracker.appendTranscript(
                    agentId: agentId,
                    entryType: .system,
                    content: extractionFailures.isEmpty
                        ? "Extraction completed"
                        : "Extraction completed with \(extractionFailures.count) failed analysis pass(es)",
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
            } else if error is ModelConfigurationError {
                // Repo standard: missing model config surfaces the settings picker.
                userMessage = "Document analysis model not configured. Choose one in Settings → Models, then re-upload \(filename)."
                await MainActor.run {
                    NotificationCenter.default.post(name: .showSettings, object: nil)
                }
            } else {
                userMessage = "Failed to extract \(filename)"
            }
            await emit(.processing(.extractionStateChanged(inProgress: true, statusMessage: userMessage)))
            try? await Task.sleep(for: .seconds(2))
        }
        // Note: activeProcessingCount is managed by pumpQueue()/extractionSlotFreed()
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
        record["contentType"].string = file.contentType ?? "image/\(file.storageURL.pathExtension.lowercased())"
        record["storageUrl"].string = file.storageURL.absoluteString
        record["documentType"].string = requestKind

        // Get file size
        if let attrs = try? FileManager.default.attributesOfItem(atPath: file.storageURL.path),
           let size = attrs[.size] as? Int {
            record["sizeBytes"].int = size
        }

        record["extractedContent"].string = "[Image file - no text extraction]"
        record["extractionMethod"].string = "none"
        record["createdAt"].string = ISO8601DateFormatter().string(from: Date())

        if let callId {
            record["callId"].string = callId
        }

        // Copy relevant metadata
        if let targetObjectives = metadata["targetPhaseObjectives"].array {
            record["metadata"]["targetPhaseObjectives"] = JSON(targetObjectives)
        }

        return record
    }

    // MARK: - Direct PDF Sending

    /// Send a PDF file directly to the LLM without extraction pipeline.
    /// Used for resume uploads to allow the LLM to read the document natively
    /// without skills extraction or knowledge card generation.
    ///
    /// The PDF rides on the pdfAttachment.storageUrl marker in the ui-action-result:
    /// AnthropicHistoryBuilder re-includes the document block from disk on the send
    /// path and on every replay via the same code path (byte-stable, survives
    /// session restore). Do NOT also attach payload["pdfData"] — that would record
    /// a wire attachment and the document would be sent twice per request.
    private func sendPDFDirectlyToLLM(
        file: ProcessedUploadInfo,
        requestKind: String,
        callId: String?,
        metadata: JSON
    ) async {
        let filename = file.filename

        Logger.info("📄 Sending resume PDF directly to LLM: \(filename)", category: .ai)

        guard let pdfData = try? Data(contentsOf: file.storageURL) else {
            Logger.error("❌ Failed to read PDF file: \(filename)", category: .ai)
            return
        }

        let sizeKB = pdfData.count / 1024

        // Build UI action result with PDF attachment info
        var result = JSON()
        result["status"].string = "completed"
        result["message"].string = "Resume PDF attached below. Please review to understand the user's professional background."
        var pdfAttachment = JSON()
        pdfAttachment["storageUrl"].string = file.storageURL.path
        pdfAttachment["filename"].string = filename
        pdfAttachment["sizeKb"].int = sizeKB
        result["pdfAttachment"] = pdfAttachment

        let resultString = result.rawString() ?? "{}"

        // Build user message with ui-action-result tags; the pdfAttachment marker
        // above is what delivers the document (see doc comment).
        let taggedMessage = "<ui-action-result tool=\"\(OnboardingToolName.getUserUpload.rawValue)\">\n\(resultString)\n</ui-action-result>"
        var payload = JSON()
        payload["text"].string = taggedMessage

        await emit(.llm(.sendUserMessage(payload: payload, isSystemGenerated: true)))
        Logger.info("✅ Resume PDF sent as ui-action-result: \(filename) (\(sizeKB) KB)", category: .ai)
    }
}
