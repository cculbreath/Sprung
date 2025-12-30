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
    private var subscriptionTask: Task<Void, Never>?
    private var isActive = false

    // MARK: - Batch State
    /// Tracks expected artifacts from current batch
    private var pendingBatch: PendingBatch?
    /// Timeout per document in batch (seconds)
    /// Large PDFs (20+ MB) can take 2+ minutes to extract via Google Files API
    private let timeoutPerDocumentSeconds: Double = 120.0

    private class PendingBatch {
        var expectedCount: Int
        var collectedArtifacts: [JSON] = []
        var skippedCount: Int = 0
        var startTime: Date = Date()
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
        subscriptionTask = Task { [weak self] in
            guard let self else { return }
            for await event in await self.eventBus.stream(topic: .artifact) {
                if Task.isCancelled { break }
                await self.handleEvent(event)
            }
        }
        Logger.info("▶️ DocumentArtifactMessenger started", category: .ai)
    }

    func stop() {
        guard isActive else { return }
        isActive = false
        subscriptionTask?.cancel()
        subscriptionTask = nil
        pendingBatch?.timeoutTask?.cancel()
        pendingBatch = nil
        Logger.info("⏹️ DocumentArtifactMessenger stopped", category: .ai)
    }

    // MARK: - Event Handling
    private func handleEvent(_ event: OnboardingEvent) async {
        switch event {
        case .uploadCompleted(let files, _, _, let metadata):
            // Skip targeted uploads (e.g., profile photos)
            if metadata["target_key"].string != nil {
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

        case .artifactRecordProduced(let record):
            await handleArtifactProduced(record)

        default:
            break
        }
    }

    // MARK: - Batch Management
    private func startBatch(expectedCount: Int) async {
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
            await emit(.batchUploadStarted(expectedCount: expectedCount))
            pendingBatch = PendingBatch(expectedCount: expectedCount)
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
        let contentType = record["content_type"].stringValue
        // Handle git repository artifacts directly (no batching)
        if record["source_type"].stringValue == "git_repository" || record["type"].stringValue == "git_analysis" {
            await sendGitArtifact(record)
            return
        }

        // Handle image artifacts - send to LLM with context
        if contentType.lowercased().hasPrefix("image/") {
            await sendImageArtifact(record)
            return
        }

        // Process extractable document types (PDFs and text files)
        let extractableTypes = ["application/pdf", "text/plain", "text/html", "text/markdown"]
        let isExtractable = extractableTypes.contains { contentType.lowercased().contains($0.lowercased()) } ||
                           contentType.lowercased().contains("pdf") ||
                           contentType.lowercased().hasPrefix("text/")
        guard isExtractable else {
            Logger.debug("📄 Skipping non-extractable artifact: \(contentType)", category: .ai)
            return
        }

        let extractedText = record["extracted_text"].stringValue
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
            await emit(.batchUploadCompleted)
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
        await emit(.batchUploadCompleted)

        guard !artifacts.isEmpty else {
            Logger.warning("⚠️ Batch complete but no artifacts to send", category: .ai)
            return
        }

        Logger.info("📤 Sending batched artifacts to LLM: \(artifacts.count) document(s)", category: .ai)

        // Build consolidated message content (phase-aware: full content in Phase 1/3, summaries in Phase 2)
        let currentPhase = await stateCoordinator.phase
        let messageText = buildExtractedContentMessage(artifacts: artifacts, phase: currentPhase)

        // Check if there's a pending UI tool call (from get_user_upload)
        // If so, complete it with extracted content instead of sending a separate user message
        // This eliminates an unnecessary LLM round trip
        if let pendingCall = await stateCoordinator.getPendingUIToolCall() {
            Logger.info("📤 Completing pending tool call with extracted content (call: \(pendingCall.callId.prefix(8))...)", category: .ai)

            // Build tool output with extracted content
            var output = JSON()
            output["status"].string = "completed"
            output["message"].string = "Document extraction complete. \(artifacts.count) document(s) processed."
            output["extracted_content"].string = messageText

            // Build tool response payload
            var payload = JSON()
            payload["callId"].string = pendingCall.callId
            payload["output"] = output

            // Emit tool response (this completes the pending tool call)
            await emit(.llmToolResponseMessage(payload: payload))

            // Clear the pending tool call
            await stateCoordinator.clearPendingUIToolCall()

            Logger.info("✅ Batch of \(artifacts.count) artifact(s) sent via tool response (eliminated extra LLM turn)", category: .ai)
        } else {
            // No pending tool call - send as user message (fallback for direct uploads)
            var payload = JSON()
            payload["text"].string = messageText

            await emit(.llmSendUserMessage(payload: payload, isSystemGenerated: true))
            Logger.info("✅ Batch of \(artifacts.count) artifact(s) sent as user message", category: .ai)
        }
    }

    /// Build the extracted content message for artifacts
    /// Phase 1 & 3: Include full extracted text (needed for skeleton timeline, finalization)
    /// Phase 2: Summaries + inventory stats (token-efficient)
    private func buildExtractedContentMessage(artifacts: [JSON], phase: InterviewPhase) -> String {
        let sendFullContent = phase != .phase2DeepDive
        var messageText = "I've uploaded \(artifacts.count == 1 ? "a document" : "\(artifacts.count) documents"):\n\n"

        for (index, artifact) in artifacts.enumerated() {
            let filename = artifact["filename"].stringValue
            let artifactId = artifact["id"].stringValue
            let extractedText = artifact["extracted_text"].stringValue
            let summary = artifact["summary"].string ?? "Summary not available"
            let sizeBytes = artifact["size_bytes"].int ?? 0
            let sizeKB = sizeBytes / 1024

            // Prefer detected type from classification over user-provided metadata
            let docTypeDetected = artifact["document_type_detected"].string
                ?? artifact["metadata"]["document_type"].string

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

            if sendFullContent && !extractedText.isEmpty {
                // Phase 1 & 3: Include full extracted text
                messageText += "**Extracted Content**:\n\(extractedText)\n\n"
            } else {
                // Phase 2: Summary + inventory stats
                messageText += "**Summary**:\n\(summary)\n\n"

                // Include inventory stats if available
                messageText += buildInventoryStatsSection(artifact)
            }
        }

        if !sendFullContent {
            messageText += """
                ---
                Full document text available via `get_artifact(artifact_id)`.
                Card inventories will be merged when user clicks "Done with Uploads".
                """
        }

        return messageText
    }

    /// Build inventory stats section from artifact record
    private func buildInventoryStatsSection(_ artifact: JSON) -> String {
        let inventoryStats = artifact["inventory_stats"]
        guard inventoryStats.exists() else { return "" }

        let total = inventoryStats["total"].intValue
        guard total > 0 else { return "" }

        let byType = inventoryStats["by_type"].dictionaryValue
        let primaryCount = inventoryStats["primary_count"].intValue

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
        // Use the batch helper with a single artifact (phase-aware)
        let currentPhase = await stateCoordinator.phase
        let messageText = buildExtractedContentMessage(artifacts: [record], phase: currentPhase)
        let artifactId = record["id"].stringValue

        // Check if there's a pending UI tool call (from get_user_upload)
        // If so, complete it with extracted content instead of sending a separate user message
        if let pendingCall = await stateCoordinator.getPendingUIToolCall() {
            Logger.info("📤 Completing pending tool call with extracted content (call: \(pendingCall.callId.prefix(8))...)", category: .ai)

            // Build tool output with extracted content
            var output = JSON()
            output["status"].string = "completed"
            output["message"].string = "Document extraction complete."
            output["extracted_content"].string = messageText

            // Build tool response payload
            var payload = JSON()
            payload["callId"].string = pendingCall.callId
            payload["output"] = output

            // Emit tool response (this completes the pending tool call)
            await emit(.llmToolResponseMessage(payload: payload))

            // Clear the pending tool call
            await stateCoordinator.clearPendingUIToolCall()

            Logger.info("✅ Single artifact sent via tool response (eliminated extra LLM turn): \(artifactId)", category: .ai)
        } else {
            // No pending tool call - send as user message (fallback for direct uploads)
            var payload = JSON()
            payload["text"].string = messageText

            await emit(.llmSendUserMessage(payload: payload, isSystemGenerated: true))
            Logger.info("📤 Single document artifact sent as user message: \(artifactId)", category: .ai)
        }
    }

    /// Send image artifact to LLM with context about current workflow
    private func sendImageArtifact(_ record: JSON) async {
        let artifactId = record["id"].stringValue
        let filename = record["filename"].stringValue
        let storageURLString = record["storage_url"].stringValue

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
        payload["image_data"].string = imageData.base64EncodedString()
        payload["image_filename"].string = filename
        payload["content_type"].string = record["content_type"].stringValue

        await emit(.llmSendUserMessage(payload: payload, isSystemGenerated: true))
        Logger.info("🖼️ Image artifact sent to LLM: \(artifactId)", category: .ai)
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
        let repoSummary = analysis["repository_summary"]
        if repoSummary.exists() {
            messageText += "- **Project**: \(repoSummary["name"].stringValue)\n"
            messageText += "- **Domain**: \(repoSummary["primary_domain"].stringValue)\n"
            messageText += "- **Type**: \(repoSummary["project_type"].stringValue)\n\n"
            if let description = repoSummary["description"].string, !description.isEmpty {
                messageText += "\(description)\n\n"
            }
        }

        // Key skills (just names, not full details)
        if let skills = analysis["technical_skills"].array, !skills.isEmpty {
            let skillNames = skills.prefix(10).compactMap { $0["skill_name"].string }
            if !skillNames.isEmpty {
                messageText += "**Key Technologies**: \(skillNames.joined(separator: ", "))\n\n"
            }
        }

        // Achievement count
        let achievementCount = analysis["notable_achievements"].arrayValue.count
        let competencyCount = analysis["architectural_competencies"].arrayValue.count
        messageText += "**Analysis includes**: \(achievementCount) notable achievements, \(competencyCount) architectural competencies\n\n"

        messageText += """
            ---
            Full analysis (resume bullets, cover letter phrases, detailed skills) is available via \
            `get_artifact("\(artifactId)")` for knowledge card generation.
            """

        // Send as user message
        var payload = JSON()
        payload["text"].string = messageText

        await emit(.llmSendUserMessage(payload: payload, isSystemGenerated: true))

        // Turn off extraction indicator now that analysis is complete
        await emit(.extractionStateChanged(false, statusMessage: nil))

        Logger.info("📤 Git analysis summary sent to LLM: \(artifactId)", category: .ai)
    }
}
