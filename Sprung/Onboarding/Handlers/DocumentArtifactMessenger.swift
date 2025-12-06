//
//  DocumentArtifactMessenger.swift
//  Sprung
//
//  Thin handler that sends document artifacts to the LLM as user messages.
//  Implements batching: when multiple files are uploaded together, waits for
//  all processing to complete before sending a single consolidated message.
//
import Foundation
import SwiftyJSON

/// Handles sending document artifacts to the LLM after production
/// Batches multiple artifacts from a single upload into one message
actor DocumentArtifactMessenger: OnboardingEventEmitter {
    // MARK: - Properties
    let eventBus: EventCoordinator

    // MARK: - Lifecycle State
    private var subscriptionTask: Task<Void, Never>?
    private var isActive = false

    // MARK: - Batch State
    /// Tracks expected artifacts from current batch
    private var pendingBatch: PendingBatch?
    /// Timeout for batch completion (seconds)
    private let batchTimeoutSeconds: Double = 30.0

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
    init(eventBus: EventCoordinator) {
        self.eventBus = eventBus
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
            // Count only PDF files since we only process those
            let pdfCount = files.filter { $0.filename.lowercased().hasSuffix(".pdf") }.count
            if pdfCount > 0 {
                await startBatch(expectedCount: pdfCount)
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

        Logger.info("📦 Starting artifact batch: expecting \(expectedCount) PDF(s)", category: .ai)

        pendingBatch = PendingBatch(expectedCount: expectedCount)

        // Start timeout task
        let timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(self?.batchTimeoutSeconds ?? 30.0))
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

        // Only process PDF documents for batching
        guard contentType.lowercased().contains("pdf") else {
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
        guard let batch = pendingBatch, !batch.collectedArtifacts.isEmpty else {
            Logger.warning("⚠️ Batch timeout with no artifacts collected", category: .ai)
            pendingBatch = nil
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

        guard !artifacts.isEmpty else {
            Logger.warning("⚠️ Batch complete but no artifacts to send", category: .ai)
            return
        }

        Logger.info("📤 Sending batched artifacts to LLM: \(artifacts.count) document(s)", category: .ai)

        // Build consolidated message
        var messageText = "I've uploaded \(artifacts.count) document(s). Here are the extracted contents:\n\n"

        var artifactIds: [String] = []
        for (index, artifact) in artifacts.enumerated() {
            let filename = artifact["filename"].stringValue
            let extractedText = artifact["extracted_text"].stringValue
            let artifactId = artifact["id"].stringValue
            artifactIds.append(artifactId)

            messageText += "---\n"
            messageText += "**Document \(index + 1): \(filename)**\n"
            messageText += "Artifact ID: \(artifactId)\n\n"
            messageText += extractedText
            messageText += "\n\n"
        }

        // Create consolidated user message payload (only text is sent to LLM)
        var payload = JSON()
        payload["text"].string = messageText

        // Emit single LLM message event for all artifacts
        await emit(.llmSendUserMessage(payload: payload, isSystemGenerated: true))
        Logger.info("✅ Batch of \(artifacts.count) artifact(s) sent to LLM", category: .ai)
    }

    private func sendSingleArtifact(_ record: JSON) async {
        let artifactId = record["id"].stringValue
        let documentType = record["document_type"].stringValue
        let filename = record["filename"].stringValue
        let extractedText = record["extracted_text"].stringValue

        var messageText = "I've uploaded a document (\(documentType)): \(filename)\n"
        messageText += "Artifact ID: \(artifactId)\n\n"
        messageText += "Here is the extracted content:\n\n"
        messageText += extractedText

        // Only text is sent to LLM - metadata fields are ignored
        var payload = JSON()
        payload["text"].string = messageText

        await emit(.llmSendUserMessage(payload: payload, isSystemGenerated: true))
        Logger.info("📤 Single document artifact sent to LLM: \(artifactId)", category: .ai)
    }

    /// Send git repository analysis artifact to LLM
    private func sendGitArtifact(_ record: JSON) async {
        let artifactId = record["id"].stringValue
        let filename = record["filename"].stringValue
        let analysis = record["analysis"]

        // Build a comprehensive message with the git analysis
        var messageText = "Git repository analysis completed for: \(filename)\n\n"

        // Include summary
        if let summary = analysis["summary"].string, !summary.isEmpty {
            messageText += "**Summary:**\n\(summary)\n\n"
        }

        // Include languages
        if let languages = analysis["languages"].array, !languages.isEmpty {
            messageText += "**Languages:**\n"
            for lang in languages {
                let name = lang["name"].stringValue
                let proficiency = lang["proficiency"].stringValue
                messageText += "- \(name) (\(proficiency))\n"
            }
            messageText += "\n"
        }

        // Include technologies
        if let techs = analysis["technologies"].array, !techs.isEmpty {
            messageText += "**Technologies:** \(techs.compactMap { $0.string }.joined(separator: ", "))\n\n"
        }

        // Include skills with evidence
        if let skills = analysis["skills"].array, !skills.isEmpty {
            messageText += "**Skills with Evidence:**\n"
            for skill in skills.prefix(10) {
                let skillName = skill["skill"].stringValue
                let evidence = skill["evidence"].stringValue
                messageText += "- **\(skillName)**: \(evidence)\n"
            }
            messageText += "\n"
        }

        // Include highlights
        if let highlights = analysis["highlights"].array, !highlights.isEmpty {
            messageText += "**Notable Achievements:**\n"
            for highlight in highlights {
                messageText += "- \(highlight.stringValue)\n"
            }
            messageText += "\n"
        }

        messageText += "Artifact ID: \(artifactId)\n\n"
        messageText += "Use `list_artifacts` to see the full analysis details, or generate knowledge cards based on these findings."

        // Only text is sent to LLM - metadata fields are ignored
        var payload = JSON()
        payload["text"].string = messageText

        await emit(.llmSendUserMessage(payload: payload, isSystemGenerated: true))
        Logger.info("📤 Git analysis artifact sent to LLM: \(artifactId)", category: .ai)
    }
}
