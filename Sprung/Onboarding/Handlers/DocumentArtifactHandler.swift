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
    private let budgetPauseGate: BudgetPauseGate
    private let budgetFailedExtractionRegistry: BudgetFailedExtractionRegistry
    private let timeoutPauseGate: TimeoutPauseGate

    /// Soft cap: after this many Keep-Waiting retries for one document we force an
    /// abort so a stuck analysis can never trap the interview indefinitely.
    private static let maxTimeoutRetries = 3

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

    /// Per-agent state retained so a failed/incomplete document can be resumed from
    /// the agent panel: the queued file, a stable transcription checkpoint id (reused
    /// across resumes so saved chunks are restored instead of re-transcribed), and the
    /// last record produced (carries the IR + failed-pass labels for an IR-based,
    /// $0 pass resume). Cleared once the document completes cleanly.
    private struct ResumeState {
        let queuedFile: QueuedFile
        let checkpointId: String
        var lastRecord: JSON?
    }
    private var resumeStates: [String: ResumeState] = [:]

    // MARK: - Lifecycle State
    private var subscriptionTask: Task<Void, Never>?
    private var isActive = false
    // MARK: - Initialization
    init(
        eventBus: EventBus,
        documentProcessingService: DocumentProcessingService,
        agentTracker: AgentActivityTracker,
        stateCoordinator: StateCoordinator,
        budgetPauseGate: BudgetPauseGate,
        budgetFailedExtractionRegistry: BudgetFailedExtractionRegistry,
        timeoutPauseGate: TimeoutPauseGate
    ) {
        self.eventBus = eventBus
        self.documentProcessingService = documentProcessingService
        self.agentTracker = agentTracker
        self.stateCoordinator = stateCoordinator
        self.budgetPauseGate = budgetPauseGate
        self.budgetFailedExtractionRegistry = budgetFailedExtractionRegistry
        self.timeoutPauseGate = timeoutPauseGate
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
        // A timeout pause suspends on a (cancellation-unaware) continuation, so a
        // plain task cancel can't unblock it — interrupt the gate to resolve .abort.
        let gate = timeoutPauseGate
        Task { @MainActor in gate.interrupt() }
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

    /// Process a single queued file: set up its agent + a stable checkpoint id, then
    /// run the ingest pipeline. A resume handler is registered up front so a failed or
    /// incomplete document can be re-run from the same panel entry — reusing the
    /// checkpoint id (transcription resumes from saved chunks) and any saved IR
    /// (re-runs only the failed analysis passes for $0).
    private func processQueuedFile(_ queuedFile: QueuedFile) async {
        let filename = queuedFile.file.filename
        let agentId = UUID().uuidString
        let checkpointId = UUID().uuidString
        resumeStates[agentId] = ResumeState(queuedFile: queuedFile, checkpointId: checkpointId, lastRecord: nil)

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
            agentTracker.setRetryHandler(agentId: agentId) { [weak self] in
                await self?.resumeDocument(agentId: agentId)
            }
        }

        Logger.info("📄 Processing document: \(filename)", category: .ai)
        await runDocumentPipeline(agentId: agentId)
        // Note: activeProcessingCount is managed by pumpQueue()/extractionSlotFreed()
    }

    /// Resume a failed/incomplete document via its registered handler: flip the agent
    /// back to running and re-enter the pipeline with the same checkpoint id + saved IR.
    private func resumeDocument(agentId: String) async {
        guard resumeStates[agentId] != nil else {
            Logger.warning("⚠️ No resume state for agent \(agentId.prefix(8)) — cannot resume", category: .ai)
            return
        }
        await MainActor.run { agentTracker.markRunning(agentId: agentId) }
        await runDocumentPipeline(agentId: agentId)
    }

    /// The ingest pipeline for one document, re-runnable for resume. Reads the agent's
    /// resume state, seeds a pass-stage resume from a saved IR when present, and
    /// otherwise re-ingests (transcription resumes from saved chunks). A clean finish
    /// completes the agent and clears the state; an incomplete finish marks it failed
    /// but keeps the resume handler so the panel offers a Resume button.
    private func runDocumentPipeline(agentId: String) async {
        guard let state = resumeStates[agentId] else { return }
        let queuedFile = state.queuedFile
        let checkpointId = state.checkpointId
        let file = queuedFile.file
        let filename = file.filename

        // Status callback shared by the first ingest and any IR-based resume.
        let statusCallback: @Sendable (String) -> Void = { [weak self, agentId, filename] statusMsg in
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

        // Keep-Waiting retry loop. On a timeout, Keep Waiting resumes:
        //  • pass-stage (transcription succeeded → an IR is on the record): re-run
        //    ONLY the timed-out passes against the saved IR — no re-transcription.
        //  • transcription-stage (no IR yet): re-ingest the whole document (Step 4's
        //    checkpoint resumes transcription from the last saved chunk).
        // A soft cap of `maxTimeoutRetries` forces an abort so a stuck doc can't trap
        // the interview. Exactly one `recordProduced` is emitted, after the loop resolves.
        var timeoutAttempts = 0
        var pendingPassRetry: (record: JSON, passes: AnthropicDocumentAnalysisService.PassSelection)? = nil

        // Seed a pass-stage resume: if a prior attempt saved a complete IR and left
        // failed analysis passes, re-run ONLY those against the IR ($0, no
        // re-transcription). Otherwise fall through to a full (chunk-resuming) ingest.
        if let prior = state.lastRecord,
           prior["intermediateRepresentation"].string != nil,
           let failed = Self.failedPassSelection(from: prior["extractionFailures"].arrayValue.map(\.stringValue)) {
            pendingPassRetry = (prior, failed)
        }

        while true {
            do {
                let artifactRecord: JSON
                if let retry = pendingPassRetry {
                    pendingPassRetry = nil
                    if let resumed = await documentProcessingService.reanalyzeFromIR(
                        record: retry.record,
                        passes: retry.passes,
                        statusCallback: statusCallback
                    ) {
                        artifactRecord = resumed
                    } else {
                        // IR vanished — fall back to a full re-ingest.
                        artifactRecord = try await documentProcessingService.processDocument(
                            fileURL: file.storageURL,
                            documentType: queuedFile.requestKind,
                            callId: queuedFile.callId,
                            metadata: queuedFile.metadata,
                            displayFilename: filename,
                            checkpointId: checkpointId,
                            statusCallback: statusCallback
                        )
                    }
                } else {
                    artifactRecord = try await documentProcessingService.processDocument(
                        fileURL: file.storageURL,
                        documentType: queuedFile.requestKind,
                        callId: queuedFile.callId,
                        metadata: queuedFile.metadata,
                        displayFilename: filename,
                        checkpointId: checkpointId,
                        statusCallback: statusCallback
                    )
                }

                let extractionFailures = artifactRecord["extractionFailures"].arrayValue.map(\.stringValue)

                // Timeout failure: a pass (or the whole document) failed specifically
                // on a timeout (the no-silent-fallback foundation records it rather
                // than fabricating a stub). Offer Keep Waiting / Abort before finalizing.
                if let failedPasses = Self.timeoutFailedPassSelection(from: extractionFailures) {
                    timeoutAttempts += 1
                    let resolution: TimeoutPauseResolution
                    if timeoutAttempts >= Self.maxTimeoutRetries {
                        Logger.warning("⏱️ Timeout retry cap reached for \(filename) — keeping partial analysis", category: .ai)
                        resolution = .abort
                    } else {
                        resolution = await timeoutPauseGate.awaitResolution(
                            TimeoutPauseInfo(filename: filename, attempt: timeoutAttempts)
                        )
                    }
                    if case .keepWaiting = resolution {
                        // Transcription IR present → resume cheaply (rerun only the failed
                        // passes against it); absent → full re-ingest on the next pass.
                        if artifactRecord["intermediateRepresentation"].string != nil {
                            pendingPassRetry = (artifactRecord, failedPasses)
                        }
                        continue
                    }
                    // .abort → fall through and finalize the partial record as-is.
                }

                // Finalize. A clean run completes the agent and drops its resume
                // state. An incomplete run (any failed pass) is surfaced as a
                // resumable failure — the partial record is still emitted, and the
                // resume handler + state are kept so the panel offers a Resume button
                // that re-runs only the failed passes (or resumes transcription).
                // Budget-exhausted passes are additionally recorded so they re-run
                // after a top-up (otherwise outages silently degrade card quality).
                let budgetFailedPasses = Self.budgetFailedPassSelection(from: extractionFailures)
                let incomplete = !extractionFailures.isEmpty
                if incomplete {
                    resumeStates[agentId]?.lastRecord = artifactRecord
                } else {
                    resumeStates[agentId] = nil
                }
                await MainActor.run {
                    for failure in extractionFailures {
                        agentTracker.appendTranscript(
                            agentId: agentId,
                            entryType: .error,
                            content: "Analysis pass failed",
                            details: failure
                        )
                    }
                    if let passes = budgetFailedPasses {
                        budgetFailedExtractionRegistry.record(filename: filename, passes: passes)
                        budgetPauseGate.surface(.anthropic())
                    }
                    if incomplete {
                        agentTracker.markFailed(
                            agentId: agentId,
                            error: "Extraction incomplete — \(extractionFailures.count) analysis pass(es) failed. Resume to retry."
                        )
                    } else {
                        agentTracker.appendTranscript(
                            agentId: agentId,
                            entryType: .system,
                            content: "Extraction completed",
                            details: "Artifact ID: \(artifactRecord["id"].stringValue)"
                        )
                        agentTracker.markCompleted(agentId: agentId)
                    }
                }

                await emit(.artifact(.recordProduced(record: artifactRecord)))
                Logger.info("✅ Document processed: \(filename)\(incomplete ? " (incomplete — resumable)" : "")", category: .ai)
                break

            } catch {
                // Transcription-stage timeout (or any timeout that propagated):
                // suspend on the gate; Keep Waiting re-runs the whole document.
                if LLMErrorHandler().isTimeoutError(error) && timeoutAttempts < Self.maxTimeoutRetries {
                    timeoutAttempts += 1
                    let resolution = await timeoutPauseGate.awaitResolution(
                        TimeoutPauseInfo(filename: filename, attempt: timeoutAttempts)
                    )
                    if case .keepWaiting = resolution { continue }
                    // .abort → keep the already-extracted text; report as a failure.
                }
                await handleProcessingFailure(error, filename: filename, agentId: agentId)
                break
            }
        }
        // Note: activeProcessingCount is managed by pumpQueue()/extractionSlotFreed()
    }

    /// Report a terminal document-processing failure: mark the agent failed and
    /// surface a brief user-facing message. The already-extracted text/transcription
    /// is preserved upstream; this never marks the artifact "complete".
    private func handleProcessingFailure(_ error: Error, filename: String, agentId: String) async {
            Logger.error("❌ Document processing failed: \(error.localizedDescription)", category: .ai)

            // Mark agent as failed
            await MainActor.run {
                agentTracker.markFailed(agentId: agentId, error: error.localizedDescription)
            }

            // Show error briefly
            let userMessage: String
            if let extractionError = error as? DocumentExtractionService.ExtractionError {
                userMessage = extractionError.userFacingMessage
            } else if let modelError = error as? ModelConfigurationError {
                // Repo standard: missing model config surfaces the settings picker.
                userMessage = "Document analysis model not configured. Choose one in Settings → Models, then re-upload \(filename)."
                await MainActor.run {
                    NotificationCenter.default.post(
                        name: .showModelSettings, object: nil,
                        userInfo: ["settingKey": modelError.settingKey]
                    )
                }
            } else {
                userMessage = "Failed to extract \(filename)"
            }
            await emit(.processing(.extractionStateChanged(inProgress: true, statusMessage: userMessage)))
            try? await Task.sleep(for: .seconds(2))
    }

    // MARK: - Budget-Failed Pass Detection

    /// Reduce a document's extraction-failure labels to the set of passes that
    /// failed specifically because the API balance was exhausted, or nil if none
    /// did. Non-budget failures (e.g. a malformed-response retry exhaustion) are
    /// ignored here — they aren't fixed by topping up.
    static func budgetFailedPassSelection(
        from failures: [String]
    ) -> AnthropicDocumentAnalysisService.PassSelection? {
        var accumulated: AnthropicDocumentAnalysisService.PassSelection?
        for failure in failures where LLMErrorHandler.descriptionIndicatesInsufficientBalance(failure) {
            guard let passes = BudgetFailedExtractionRegistry.passSelection(forFailureLabel: failure) else { continue }
            accumulated = accumulated?.merged(with: passes) ?? passes
        }
        return accumulated
    }

    // MARK: - Timeout-Failed Pass Detection

    /// Reduce a document's extraction-failure labels to the set of passes that
    /// failed specifically because the request timed out, or nil if none did.
    /// Mirrors `budgetFailedPassSelection` but on the disjoint timeout predicate so
    /// the two recovery modals never fire for the same failure.
    static func timeoutFailedPassSelection(
        from failures: [String]
    ) -> AnthropicDocumentAnalysisService.PassSelection? {
        var accumulated: AnthropicDocumentAnalysisService.PassSelection?
        for failure in failures where LLMErrorHandler.descriptionIndicatesTimeout(failure) {
            guard let passes = BudgetFailedExtractionRegistry.passSelection(forFailureLabel: failure) else { continue }
            accumulated = accumulated?.merged(with: passes) ?? passes
        }
        return accumulated
    }

    /// Reduce a document's extraction-failure labels to the union of passes that
    /// failed for ANY reason — used to seed a manual Resume so it re-runs only the
    /// incomplete passes against the saved IR. Returns nil when no label maps to a
    /// known pass (caller then re-ingests from scratch).
    static func failedPassSelection(
        from failures: [String]
    ) -> AnthropicDocumentAnalysisService.PassSelection? {
        var accumulated: AnthropicDocumentAnalysisService.PassSelection?
        for failure in failures {
            guard let passes = BudgetFailedExtractionRegistry.passSelection(forFailureLabel: failure) else { continue }
            accumulated = accumulated?.merged(with: passes) ?? passes
        }
        return accumulated
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
        let agentId = UUID().uuidString

        await MainActor.run {
            agentTracker.trackAgent(id: agentId, type: .documentIngestion, name: filename, task: nil as Task<Void, Never>?)
        }

        Logger.info("📄 Sending resume PDF directly to LLM: \(filename)", category: .ai)

        guard let pdfData = try? Data(contentsOf: file.storageURL) else {
            let error = NSError(
                domain: "DocumentArtifactHandler",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Couldn't read the resume PDF — the file may have been moved or deleted."]
            )
            await handleProcessingFailure(error, filename: filename, agentId: agentId)
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

        await MainActor.run {
            agentTracker.appendTranscript(agentId: agentId, entryType: .system, content: "Resume PDF sent to LLM", details: "\(sizeKB) KB")
            agentTracker.markCompleted(agentId: agentId)
        }
        await emit(.llm(.sendUserMessage(payload: payload, isSystemGenerated: true)))
        Logger.info("✅ Resume PDF sent as ui-action-result: \(filename) (\(sizeKB) KB)", category: .ai)
    }
}
