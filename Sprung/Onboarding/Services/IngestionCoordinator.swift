import Foundation
import SwiftyJSON

/// Coordinator that listens for document uploads during Phase 2
/// and notifies the main LLM to generate knowledge cards.
actor IngestionCoordinator: OnboardingEventHandler {
    private let eventBus: EventCoordinator
    private let state: StateCoordinator
    private let documentProcessingService: DocumentProcessingService
    private var subscriptionTask: Task<Void, Never>?

    init(
        eventBus: EventCoordinator,
        state: StateCoordinator,
        documentProcessingService: DocumentProcessingService
    ) {
        self.eventBus = eventBus
        self.state = state
        self.documentProcessingService = documentProcessingService
        Logger.info("⚙️ IngestionCoordinator initialized", category: .ai)
    }

    func start() async {
        // Cancel any existing subscription
        subscriptionTask?.cancel()

        // Subscribe to artifact events
        subscriptionTask = Task { [weak self] in
            guard let self else { return }
            for await event in await self.eventBus.stream(topic: .artifact) {
                if Task.isCancelled { break }
                await self.handleEvent(event)
            }
        }
        Logger.info("📡 IngestionCoordinator subscribed to artifact events", category: .ai)
    }

    func stop() {
        subscriptionTask?.cancel()
        subscriptionTask = nil
        Logger.info("🛑 IngestionCoordinator stopped", category: .ai)
    }

    func handleEvidenceUpload(url: URL, requirementId: String) async {
        Logger.info("📎 Handling evidence upload for requirement: \(requirementId)", category: .ai)
        await eventBus.publish(.processingStateChanged(true, statusMessage: "Processing evidence..."))

        do {
            var metadata = JSON()
            metadata["evidence_requirement_id"].string = requirementId

            let record = try await documentProcessingService.processDocument(
                fileURL: url,
                documentType: "evidence",
                callId: nil,
                metadata: metadata
            )
            await eventBus.publish(.artifactRecordProduced(record: record))
            Logger.info("✅ Evidence processed and artifact produced", category: .ai)
        } catch {
            Logger.error("❌ Evidence upload failed: \(error.localizedDescription)", category: .ai)
            await eventBus.publish(.errorOccurred("Failed to process evidence: \(error.localizedDescription)"))
        }

        await eventBus.publish(.processingStateChanged(false))
    }

    func handleEvent(_ event: OnboardingEvent) async {
        switch event {
        case .artifactRecordProduced(let record):
            await notifyLLMOfArtifact(record)
        default:
            break
        }
    }

    /// Notify the main LLM that a document has been processed and is ready for knowledge card generation
    private func notifyLLMOfArtifact(_ record: JSON) async {
        // Only notify during Phase 2
        let currentPhase = await state.phase
        guard currentPhase == .phase2DeepDive else {
            Logger.debug("⏭️ IngestionCoordinator: Skipping LLM notification (not in Phase 2)", category: .ai)
            return
        }

        let filename = record["filename"].stringValue
        let artifactId = record["id"].stringValue
        let extractedContent = record["extracted_content"].stringValue
        let contentPreview = String(extractedContent.prefix(500))
        let requirementId = record["metadata"]["evidence_requirement_id"].string

        // Build notification message
        var notificationPayload = JSON()

        if let requirementId = requirementId {
            notificationPayload["text"].string = """
                **DOCUMENT PROCESSED - EVIDENCE UPLOADED**

                A document has been uploaded in response to evidence requirement: \(requirementId)

                **Filename**: \(filename)
                **Artifact ID**: \(artifactId)

                **Content Preview**:
                \(contentPreview)...

                **ACTION**: Use `get_artifact` with id "\(artifactId)" to read the full content, then call `generate_knowledge_card` for the relevant timeline entry.
                """
        } else {
            notificationPayload["text"].string = """
                **DOCUMENT PROCESSED - NEW UPLOAD**

                A document has been uploaded and processed.

                **Filename**: \(filename)
                **Artifact ID**: \(artifactId)

                **Content Preview**:
                \(contentPreview)...

                **ACTION**:
                1. Use `get_artifact` with id "\(artifactId)" to read the full content
                2. Determine which timeline entry this document relates to
                3. Call `generate_knowledge_card` with the timeline entry and this artifact
                """
        }

        notificationPayload["artifact_id"].string = artifactId
        notificationPayload["filename"].string = filename

        await eventBus.publish(.llmSendDeveloperMessage(payload: notificationPayload))
        Logger.info("📨 IngestionCoordinator: Notified LLM of processed document: \(filename)", category: .ai)
    }
}
