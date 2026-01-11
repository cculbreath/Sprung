//
//  DocumentArtifactMessenger.swift
//  Sprung
//
//  Thin handler that sends document artifacts to the LLM.
//  Implements batching: when multiple files are uploaded together, waits for
//  all processing to complete before sending a single consolidated message.
//
//  Key optimization: When a pending UI tool call exists (from get_user_upload),
//  completes it with extracted content instead of sending a separate user message.
//  This eliminates an unnecessary LLM round trip.
//
import Foundation
import SwiftyJSON

/// Handles sending document artifacts to the LLM after production
/// Batches multiple artifacts from a single upload into one message
actor DocumentArtifactMessenger: OnboardingEventEmitter {
    // MARK: - Properties
    let eventBus: EventCoordinator
    private let stateCoordinator: StateCoordinator

    // MARK: - Lifecycle State
    private var artifactSubscriptionTask: Task<Void, Never>?
    private var processingSubscriptionTask: Task<Void, Never>?
    private var isActive = false

    // MARK: - Batch State
    /// Tracks expected artifacts from current batch
    private var pendingBatch: PendingBatch?
    /// Timeout per document in batch (seconds)
    /// Large PDFs (20+ MB) can take 2+ minutes to extract via Google Files API
    private let timeoutPerDocumentSeconds: Double = 120.0
    /// Flag to suppress self-echo when we emit batchUploadStarted
    /// Prevents double-counting: uploadCompleted → startBatch → emit event → handleEvent → startBatch again
    private var suppressNextBatchStarted = false

    private class PendingBatch {
        var expectedCount: Int
        var collectedArtifacts: [JSON] = []
        var skippedCount: Int = 0
        var timeoutTask: Task<Void, Never>?

        init(expectedCount: Int) {
            self.expectedCount = expectedCount
        }

        var totalProcessed: Int {
            collectedArtifacts.count + skippedCount
        }
    }

    // MARK: - Initialization
    init(eventBus: EventCoordinator, stateCoordinator: StateCoordinator) {
        self.eventBus = eventBus
        self.stateCoordinator = stateCoordinator
        Logger.info("📤 DocumentArtifactMessenger initialized", category: .ai)
    }

    // MARK: - Lifecycle
    func start() {
        guard !isActive else { return }
        isActive = true

        // Subscribe to artifact topic for artifact production events
        artifactSubscriptionTask = Task { [weak self] in
            guard let self else { return }
            for await event in await self.eventBus.stream(topic: .artifact) {
                if Task.isCancelled { break }
                await self.handleEvent(event)
            }
        }

        // Subscribe to processing topic for batch upload events (from promoteArchivedArtifacts)
        processingSubscriptionTask = Task { [weak self] in
            guard let self else { return }
            for await event in await self.eventBus.stream(topic: .processing) {
                if Task.isCancelled { break }
                await self.handleEvent(event)
            }
        }

        Logger.info("▶️ DocumentArtifactMessenger started", category: .ai)
    }

    func stop() {
        guard isActive else { return }
        isActive = false
        artifactSubscriptionTask?.cancel()
        artifactSubscriptionTask = nil
        processingSubscriptionTask?.cancel()
        processingSubscriptionTask = nil
        pendingBatch?.timeoutTask?.cancel()
        pendingBatch = nil
        Logger.info("⏹️ DocumentArtifactMessenger stopped", category: .ai)
    }

    // MARK: - Event Handling
    private func handleEvent(_ event: OnboardingEvent) async {
        switch event {
        case .artifact(.uploadCompleted(let files, _, _, let metadata)):
            // Skip targeted uploads (e.g., profile photos)
            if metadata["targetKey"].string != nil {
                return
            }
            // Count extractable document files (PDFs and text files)
            let extractableCount = files.filter { file in
                let ext = file.filename.lowercased().split(separator: ".").last.map(String.init) ?? ""
                return DocumentTypePolicy.isExtractable(ext)
            }.count
            if extractableCount > 0 {
                await startBatch(expectedCount: extractableCount)
            }

        case .processing(.batchUploadStarted(let expectedCount)):
            // Skip if this is our own event echoing back (prevents double-counting)
            if suppressNextBatchStarted {
                suppressNextBatchStarted = false
                break
            }
            // Handle external batch starts (e.g., from promoteArchivedArtifacts)
            await startBatch(expectedCount: expectedCount, emitStartEvent: false)

        case .artifact(.recordProduced(let record)):
            await handleArtifactProduced(record)

        default:
            break
        }
    }

    // MARK: - Batch Management
    private func startBatch(expectedCount: Int, emitStartEvent: Bool = true) async {
        // Cancel any existing batch timeout
        pendingBatch?.timeoutTask?.cancel()

        // If there's an existing batch in progress, MERGE the expected counts
        // This handles the case where user uploads more files while previous batch is processing
        let newExpectedCount: Int
        if let existingBatch = pendingBatch {
            newExpectedCount = existingBatch.expectedCount + expectedCount
            existingBatch.expectedCount = newExpectedCount
            Logger.info("📦 Merging into existing batch: now expecting \(newExpectedCount) document(s) (was \(existingBatch.expectedCount - expectedCount), added \(expectedCount))", category: .ai)
        } else {
            newExpectedCount = expectedCount
            Logger.info("📦 Starting new artifact batch: expecting \(expectedCount) document(s)", category: .ai)
            // Emit batch started event - this prevents validation prompts from interrupting uploads
            // Skip if caller already emitted the event (e.g., when handling .batchUploadStarted)
            if emitStartEvent {
                // Set flag to suppress the echo when we receive our own event back
                suppressNextBatchStarted = true
                await emit(.processing(.batchUploadStarted(expectedCount: expectedCount)))
            }
            pendingBatch = PendingBatch(expectedCount: expectedCount)

            // Send developer message to LLM so it knows to continue interviewing
            // This is the "batched notification" pattern from the interview revitalization plan
            let estimatedSeconds = Int(timeoutPerDocumentSeconds * 0.3 * Double(expectedCount))
            await sendBackgroundStartedMessage(documentCount: expectedCount, estimatedSeconds: estimatedSeconds)
        }

        // Start/restart timeout task (scales with total number of documents)
        let batchTimeout = timeoutPerDocumentSeconds * Double(newExpectedCount)
        Logger.debug("📦 Batch timeout set to \(Int(batchTimeout))s for \(newExpectedCount) document(s)", category: .ai)
        let timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(batchTimeout))
            guard !Task.isCancelled else { return }
            await self?.handleBatchTimeout()
        }
        pendingBatch?.timeoutTask = timeoutTask
    }

    private func handleArtifactProduced(_ record: JSON) async {
        let contentType = record["contentType"].stringValue
        // Handle git repository artifacts directly (no batching)
        if record["sourceType"].stringValue == "git_repository" || record["type"].stringValue == "git_analysis" {
            await sendGitArtifact(record)
            // Track as skipped so batch can complete (git repos bypass batching but still count toward expected)
            if pendingBatch != nil {
                pendingBatch?.skippedCount += 1
                await checkBatchCompletion()
            }
            return
        }

        // Handle image artifacts - send to LLM with context
        if contentType.lowercased().hasPrefix("image/") {
            await sendImageArtifact(record)
            // Track as skipped so batch can complete (images bypass batching but still count toward expected)
            if pendingBatch != nil {
                pendingBatch?.skippedCount += 1
                await checkBatchCompletion()
            }
            return
        }

        // Process extractable document types (PDFs and text files)
        let extractableTypes = ["application/pdf", "text/plain", "text/html", "text/markdown"]
        let isExtractable = extractableTypes.contains { contentType.lowercased().contains($0.lowercased()) } ||
                           contentType.lowercased().contains("pdf") ||
                           contentType.lowercased().hasPrefix("text/")
        guard isExtractable else {
            Logger.debug("📄 Skipping non-extractable artifact: \(contentType)", category: .ai)
            // Track as skipped so batch can complete
            if pendingBatch != nil {
                pendingBatch?.skippedCount += 1
                await checkBatchCompletion()
            }
            return
        }

        let extractedText = record["extractedText"].stringValue
        guard !extractedText.isEmpty else {
            Logger.warning("⚠️ Skipping artifact - no extracted text", category: .ai)
            // Track skipped artifact so batch completion works correctly
            if pendingBatch != nil {
                pendingBatch?.skippedCount += 1
                await checkBatchCompletion()
            }
            return
        }

        let artifactId = record["id"].stringValue
        Logger.info("📄 Artifact received for batching: \(artifactId)", category: .ai)

        // Add to batch
        if pendingBatch != nil {
            pendingBatch?.collectedArtifacts.append(record)
            await checkBatchCompletion()
        } else {
            // No active batch - send immediately (rare edge case)
            await sendSingleArtifact(record)
        }
    }

    private func checkBatchCompletion() async {
        guard let batch = pendingBatch else { return }

        let totalProcessed = batch.totalProcessed
        let expectedCount = batch.expectedCount

        Logger.debug("📊 Batch progress: \(totalProcessed)/\(expectedCount) processed (\(batch.collectedArtifacts.count) collected, \(batch.skippedCount) skipped)", category: .ai)

        // Check if we've processed all expected artifacts (collected + skipped)
        if totalProcessed >= expectedCount {
            await completeBatch()
        }
    }

    private func handleBatchTimeout() async {
        guard let batch = pendingBatch else { return }

        if batch.collectedArtifacts.isEmpty {
            Logger.warning("⚠️ Batch timeout with no artifacts collected", category: .ai)
            batch.timeoutTask?.cancel()
            pendingBatch = nil
            // Still emit batchUploadCompleted to clear the hasBatchUploadInProgress flag
            await emit(.processing(.batchUploadCompleted))
            return
        }

        Logger.info("⏰ Batch timeout reached with \(batch.collectedArtifacts.count) artifact(s)", category: .ai)
        await completeBatch()
    }

    private func completeBatch() async {
        guard let batch = pendingBatch else { return }

        // Cancel timeout task
        batch.timeoutTask?.cancel()

        let artifacts = batch.collectedArtifacts
        pendingBatch = nil

        // Emit batch completed event - allows validation prompts to proceed
        await emit(.processing(.batchUploadCompleted))

        guard !artifacts.isEmpty else {
            Logger.warning("⚠️ Batch complete but no artifacts to send", category: .ai)
            return
        }

        Logger.info("📤 Sending batched artifacts to LLM: \(artifacts.count) document(s)", category: .ai)

        // Build consolidated message content (summaries only to prevent context bloat)
        let messageText = buildExtractedContentMessage(artifacts: artifacts)

        // Build UI action result with extracted content
        var result = JSON()
        result["status"].string = "completed"
        result["message"].string = "Document extraction complete. \(artifacts.count) document(s) processed."
        result["extractedContent"].string = messageText

        let resultString = result.rawString() ?? "{}"

        // Send as ui-action-result user message
        let taggedMessage = "<ui-action-result tool=\"\(OnboardingToolName.getUserUpload.rawValue)\">\n\(resultString)\n</ui-action-result>"
        var payload = JSON()
        payload["text"].string = taggedMessage

        await emit(.llm(.sendUserMessage(payload: payload, isSystemGenerated: true)))
        Logger.info("✅ Batch of \(artifacts.count) artifact(s) sent as ui-action-result", category: .ai)

        // Send developer message to LLM that background processing is complete
        // This tells the LLM to weave acknowledgment naturally into its response
        await sendBackgroundCompletedMessage(documentCount: artifacts.count)
    }

    /// Build the extracted content message for artifacts
    /// Writing samples: sent in full (small, helps model match voice)
    /// Everything else: brief summaries to prevent context bloat - full content via get_artifact()
    private func buildExtractedContentMessage(artifacts: [JSON]) -> String {
        var messageText = "I've uploaded \(artifacts.count == 1 ? "a document" : "\(artifacts.count) documents"):\n\n"

        for (index, artifact) in artifacts.enumerated() {
            let filename = artifact["filename"].stringValue
            let artifactId = artifact["id"].stringValue
            let extractedText = artifact["extractedText"].stringValue
            let summary = artifact["summary"].string ?? "Summary not available"
            let briefDescription = artifact["briefDescription"].string
            let sizeBytes = artifact["sizeBytes"].int ?? 0
            let sizeKB = sizeBytes / 1024

            // Prefer detected type from classification over user-provided metadata
            let docTypeDetected = artifact["documentTypeDetected"].string
                ?? artifact["metadata"]["documentType"].string

            // Check if full content should be sent to LLM (set at ingestion time)
            // True for writing samples and resume uploads - helps with voice matching
            let includeFullContent = artifact["interviewContext"].bool ?? false

            if artifacts.count > 1 {
                messageText += "### Document \(index + 1): \(filename)\n"
            } else {
                messageText += "### \(filename)\n"
            }

            messageText += "- **Artifact ID**: `\(artifactId)`\n"
            if let docType = docTypeDetected, !docType.isEmpty {
                messageText += "- **Detected Type**: \(formatDocType(docType))\n"
            }
            messageText += "- **Size**: \(sizeKB) KB\n\n"

            if includeFullContent && !extractedText.isEmpty {
                // Full content for interview context artifacts (writing samples, resumes)
                messageText += "**Full Text**:\n\(extractedText)\n\n"
            } else {
                // Everything else: brief summary only
                if let brief = briefDescription, !brief.isEmpty {
                    messageText += "**Description**: \(brief)\n\n"
                } else {
                    messageText += "**Summary**:\n\(summary)\n\n"
                }

                // Include inventory stats if available
                messageText += buildInventoryStatsSection(artifact)
            }
        }

        messageText += """
            ---
            Full document text available via `get_artifact(artifact_id)`.
            """

        return messageText
    }

    /// Build inventory stats section from artifact record
    private func buildInventoryStatsSection(_ artifact: JSON) -> String {
        let inventoryStats = artifact["inventoryStats"]
        guard inventoryStats.exists() else { return "" }

        let total = inventoryStats["total"].intValue
        guard total > 0 else { return "" }

        let byType = inventoryStats["byType"].dictionaryValue
        let primaryCount = inventoryStats["primaryCount"].intValue

        var section = "**Card Inventory** (\(total) potential cards):\n"

        // Order: employment, skill, project, achievement, education
        let orderedTypes = ["employment", "skill", "project", "achievement", "education"]
        for cardType in orderedTypes {
            if let count = byType[cardType]?.int, count > 0 {
                section += "- \(count) \(cardType) card\(count == 1 ? "" : "s")\n"
            }
        }

        // Show primary source info
        if primaryCount > 0 {
            section += "- \(primaryCount) as primary source\n"
        }

        section += "\n"
        return section
    }

    /// Format document type for display
    private func formatDocType(_ rawType: String) -> String {
        // Convert snake_case to readable format
        let mappings: [String: String] = [
            "personnel_file": "Personnel File",
            "technical_report": "Technical Report",
            "cover_letter": "Cover Letter",
            "reference_letter": "Reference Letter",
            "grant_proposal": "Grant Proposal",
            "project_documentation": "Project Documentation",
            "git_analysis": "Git Repository Analysis",
            "resume": "Resume",
            "cv": "CV",
            "transcript": "Transcript",
            "dissertation": "Dissertation",
            "thesis": "Thesis",
            "publication": "Publication",
            "presentation": "Presentation"
        ]
        return mappings[rawType] ?? rawType.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func sendSingleArtifact(_ record: JSON) async {
        // Build message content (summaries only to prevent context bloat)
        let messageText = buildExtractedContentMessage(artifacts: [record])
        let artifactId = record["id"].stringValue

        // Build UI action result with extracted content
        var result = JSON()
        result["status"].string = "completed"
        result["message"].string = "Document extraction complete."
        result["extractedContent"].string = messageText

        let resultString = result.rawString() ?? "{}"

        // Send as ui-action-result user message
        let taggedMessage = "<ui-action-result tool=\"\(OnboardingToolName.getUserUpload.rawValue)\">\n\(resultString)\n</ui-action-result>"
        var payload = JSON()
        payload["text"].string = taggedMessage

        await emit(.llm(.sendUserMessage(payload: payload, isSystemGenerated: true)))
        Logger.info("📤 Single document artifact sent as ui-action-result: \(artifactId)", category: .ai)
    }

    /// Send image artifact to LLM with context about current workflow
    private func sendImageArtifact(_ record: JSON) async {
        let artifactId = record["id"].stringValue
        let filename = record["filename"].stringValue
        let storageURLString = record["storageUrl"].stringValue

        guard let storageURL = URL(string: storageURLString),
              FileManager.default.fileExists(atPath: storageURL.path) else {
            Logger.warning("⚠️ Image artifact file not found: \(storageURLString)", category: .ai)
            return
        }

        // Read image data
        guard let imageData = try? Data(contentsOf: storageURL) else {
            Logger.warning("⚠️ Failed to read image data: \(filename)", category: .ai)
            return
        }

        // Build message with image context
        let messageText = """
        I've uploaded an image as supporting evidence: \(filename)

        Artifact ID: \(artifactId)

        Please review this image and incorporate any relevant information into the current knowledge card or interview context.
        """

        // Send as user message with image attachment
        var payload = JSON()
        payload["text"].string = messageText
        payload["imageData"].string = imageData.base64EncodedString()
        payload["imageFilename"].string = filename
        payload["contentType"].string = record["contentType"].stringValue

        await emit(.llm(.sendUserMessage(payload: payload, isSystemGenerated: true)))
        Logger.info("🖼️ Image artifact sent to LLM: \(artifactId)", category: .ai)
    }

    // MARK: - Background Processing Notifications

    /// Send developer message when background processing starts
    /// This tells the LLM to continue interviewing about other topics while waiting
    private func sendBackgroundStartedMessage(documentCount: Int, estimatedSeconds: Int) async {
        let message = """
            BACKGROUND: Processing \(documentCount) document\(documentCount == 1 ? "" : "s") (~\(estimatedSeconds)s).
            Continue the interview while this runs. Use get_user_option for structured dossier questions.
            Topics: work preferences, availability, career narrative, hidden strengths.
            Do NOT acknowledge this message directly—just continue the conversation.
            """
        var payload = JSON()
        payload["text"].string = message
        await emit(.llm(.sendCoordinatorMessage(payload: payload)))
        Logger.info("📤 Background processing started notification sent to LLM", category: .ai)
    }

    /// Send developer message when background processing completes
    /// This tells the LLM that documents are ready for review
    private func sendBackgroundCompletedMessage(documentCount: Int) async {
        let message = """
            BACKGROUND COMPLETE: \(documentCount) document\(documentCount == 1 ? "" : "s") processed and ready.
            Weave acknowledgment naturally into your next response—do not interrupt current topic abruptly.
            Review the extracted content above and continue building the candidate profile.
            """
        var payload = JSON()
        payload["text"].string = message
        await emit(.llm(.sendCoordinatorMessage(payload: payload)))
        Logger.info("📤 Background processing completed notification sent to LLM", category: .ai)
    }

    /// Send git repository analysis artifact to LLM
    /// IMPORTANT: Only sends summary to prevent token accumulation.
    /// Full analysis is preserved in artifact and available via get_artifact.
    private func sendGitArtifact(_ record: JSON) async {
        let artifactId = record["id"].stringValue
        let filename = record["filename"].stringValue
        let analysis = record["analysis"]

        // Build a concise summary message (not full analysis)
        var messageText = "### Git Repository Analysis: \(filename)\n\n"
        messageText += "- **Artifact ID**: `\(artifactId)`\n"

        // Repository summary (brief)
        let repoSummary = analysis["repositorySummary"]
        if repoSummary.exists() {
            messageText += "- **Project**: \(repoSummary["name"].stringValue)\n"
            messageText += "- **Domain**: \(repoSummary["primaryDomain"].stringValue)\n"
            messageText += "- **Type**: \(repoSummary["projectType"].stringValue)\n\n"
            if let description = repoSummary["description"].string, !description.isEmpty {
                messageText += "\(description)\n\n"
            }
        }

        // Key skills (just names, not full details)
        if let skills = analysis["technicalSkills"].array, !skills.isEmpty {
            let skillNames = skills.prefix(10).compactMap { $0["skillName"].string }
            if !skillNames.isEmpty {
                messageText += "**Key Technologies**: \(skillNames.joined(separator: ", "))\n\n"
            }
        }

        // Achievement count
        let achievementCount = analysis["notableAchievements"].arrayValue.count
        let competencyCount = analysis["architecturalCompetencies"].arrayValue.count
        messageText += "**Analysis includes**: \(achievementCount) notable achievements, \(competencyCount) architectural competencies\n\n"

        messageText += """
            ---
            Full analysis (resume bullets, cover letter phrases, detailed skills) is available via \
            `get_artifact("\(artifactId)")` for knowledge card generation.
            """

        // Send as user message
        var payload = JSON()
        payload["text"].string = messageText

        await emit(.llm(.sendUserMessage(payload: payload, isSystemGenerated: true)))

        // Turn off extraction indicator now that analysis is complete
        await emit(.processing(.extractionStateChanged(inProgress: false, statusMessage: nil)))

        Logger.info("📤 Git analysis summary sent to LLM: \(artifactId)", category: .ai)
    }
}
