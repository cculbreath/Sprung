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

    private struct PendingBatch {
        let expectedCount: Int
        var collectedArtifacts: [JSON] = []
        var skippedCount: Int = 0
        var startTime: Date = Date()
        var timeoutTask: Task<Void, Never>?

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
            let extractableExtensions = Set(["pdf", "txt", "docx", "html", "htm", "md", "rtf"])
            let extractableCount = files.filter { file in
                let ext = file.filename.lowercased().split(separator: ".").last.map(String.init) ?? ""
                return extractableExtensions.contains(ext)
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

        Logger.info("📦 Starting artifact batch: expecting \(expectedCount) document(s)", category: .ai)

        // Emit batch started event - this prevents validation prompts from interrupting uploads
        await emit(.batchUploadStarted(expectedCount: expectedCount))

        pendingBatch = PendingBatch(expectedCount: expectedCount)

        // Start timeout task (scales with number of documents)
        let batchTimeout = timeoutPerDocumentSeconds * Double(expectedCount)
        Logger.debug("📦 Batch timeout set to \(Int(batchTimeout))s for \(expectedCount) document(s)", category: .ai)
        let timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(batchTimeout))
            guard !Task.isCancelled else { return }
            await self?.handleBatchTimeout()
        }
        pendingBatch?.timeoutTask = timeoutTask
    }

    private func handleArtifactProduced(_ record: JSON) async {
        let contentType = record["content_type"].stringValue
        let sourceType = record["source"].stringValue

        // Handle git repository artifacts directly (no batching)
        if sourceType == "git_repository" || record["type"].stringValue == "git_analysis" {
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

        // Build consolidated message content
        let messageText = buildExtractedContentMessage(artifacts: artifacts)

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
    private func buildExtractedContentMessage(artifacts: [JSON]) -> String {
        var messageText = "I've uploaded \(artifacts.count == 1 ? "a document" : "\(artifacts.count) document(s)") (resume): "

        for (index, artifact) in artifacts.enumerated() {
            let filename = artifact["filename"].stringValue
            let extractedText = artifact["extracted_text"].stringValue
            let artifactId = artifact["id"].stringValue

            if artifacts.count > 1 {
                messageText += "\n---\n"
                messageText += "**Document \(index + 1): \(filename)**\n"
            } else {
                messageText += "\(filename)\n"
            }
            messageText += "Artifact ID: \(artifactId)\n\n"
            messageText += "Here is the extracted content:\n\n"
            messageText += extractedText
            messageText += "\n\n"
        }

        return messageText
    }

    private func sendSingleArtifact(_ record: JSON) async {
        // Use the batch helper with a single artifact
        let messageText = buildExtractedContentMessage(artifacts: [record])
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
    private func sendGitArtifact(_ record: JSON) async {
        let artifactId = record["id"].stringValue
        let filename = record["filename"].stringValue
        let analysis = record["analysis"]

        // Build a comprehensive message with the git analysis (new schema)
        var messageText = "Git repository analysis completed for: \(filename)\n\n"

        // Repository summary
        let repoSummary = analysis["repository_summary"]
        if repoSummary.exists() {
            messageText += "**Project:** \(repoSummary["name"].stringValue)\n"
            messageText += "\(repoSummary["description"].stringValue)\n"
            messageText += "Domain: \(repoSummary["primary_domain"].stringValue) | "
            messageText += "Type: \(repoSummary["project_type"].stringValue)\n\n"
        }

        // Technical skills with resume bullets
        if let skills = analysis["technical_skills"].array, !skills.isEmpty {
            // Group by category for cleaner display
            let languages = skills.filter { $0["category"].stringValue == "language" }
            let frameworks = skills.filter { $0["category"].stringValue == "framework" }
            let tools = skills.filter { ["tool", "platform", "database"].contains($0["category"].stringValue) }

            if !languages.isEmpty {
                messageText += "**Languages:**\n"
                for lang in languages {
                    messageText += "- \(lang["skill_name"].stringValue) (\(lang["proficiency_level"].stringValue))\n"
                }
                messageText += "\n"
            }

            if !frameworks.isEmpty {
                messageText += "**Frameworks:**\n"
                for fw in frameworks {
                    messageText += "- \(fw["skill_name"].stringValue) (\(fw["proficiency_level"].stringValue))\n"
                }
                messageText += "\n"
            }

            if !tools.isEmpty {
                messageText += "**Tools & Platforms:**\n"
                for tool in tools {
                    messageText += "- \(tool["skill_name"].stringValue) (\(tool["proficiency_level"].stringValue))\n"
                }
                messageText += "\n"
            }

            // Show some resume bullets
            messageText += "**Sample Resume Bullets:**\n"
            for skill in skills.prefix(5) {
                if let bullets = skill["resume_bullets"].array, let firstBullet = bullets.first?.string {
                    messageText += "- \(firstBullet)\n"
                }
            }
            messageText += "\n"
        }

        // AI Collaboration Profile
        let aiProfile = analysis["ai_collaboration_profile"]
        if aiProfile.exists() {
            let detected = aiProfile["detected_ai_usage"].boolValue
            let rating = aiProfile["collaboration_quality_rating"].stringValue
            messageText += "**AI Collaboration:** "
            if detected {
                messageText += "\(rating.replacingOccurrences(of: "_", with: " ").capitalized)\n"
                if let positioning = aiProfile["resume_positioning"]["framing_recommendation"].string {
                    messageText += "Resume positioning: \(positioning)\n"
                }
            } else {
                messageText += "No AI usage detected\n"
            }
            messageText += "\n"
        }

        // Architectural competencies
        if let competencies = analysis["architectural_competencies"].array, !competencies.isEmpty {
            messageText += "**Architectural Competencies:**\n"
            for comp in competencies.prefix(5) {
                messageText += "- \(comp["competency"].stringValue) (\(comp["proficiency_level"].stringValue))\n"
            }
            messageText += "\n"
        }

        // Professional attributes with cover letter phrases
        if let attrs = analysis["professional_attributes"].array, !attrs.isEmpty {
            messageText += "**Professional Attributes:**\n"
            for attr in attrs.prefix(5) {
                messageText += "- \(attr["attribute"].stringValue) (\(attr["strength_level"].stringValue))\n"
            }
            messageText += "\n"
        }

        // Notable achievements
        if let achievements = analysis["notable_achievements"].array, !achievements.isEmpty {
            messageText += "**Notable Achievements:**\n"
            for achievement in achievements.prefix(8) {
                messageText += "- \(achievement["resume_bullet"].stringValue)\n"
            }
            messageText += "\n"
        }

        // Keyword cloud for ATS
        let keywords = analysis["keyword_cloud"]
        if keywords.exists() {
            if let primary = keywords["primary"].array, !primary.isEmpty {
                messageText += "**Primary Keywords (ATS):** \(primary.compactMap { $0.string }.joined(separator: ", "))\n\n"
            }
        }

        messageText += "Artifact ID: \(artifactId)\n\n"
        messageText += "This artifact is now available via `list_artifacts` and `get_artifact`. "
        messageText += "The full analysis includes resume_bullets and cover_letter_phrases ready for use. "
        messageText += "Please acknowledge receipt and briefly summarize what you learned about my skills and experience from this repository."

        // Send as user message so the LLM acknowledges receipt
        var payload = JSON()
        payload["text"].string = messageText

        await emit(.llmSendUserMessage(payload: payload, isSystemGenerated: true))
        Logger.info("📤 Git analysis artifact sent to LLM (user message): \(artifactId)", category: .ai)
    }
}
