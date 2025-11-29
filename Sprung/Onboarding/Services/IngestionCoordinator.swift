import Foundation
import SwiftyJSON

/// Coordinator that handles evidence uploads during Phase 2.
/// Documents are processed and stored as artifacts. The LLM retrieves them
/// via `list_artifacts` when ready - no interrupting notifications needed.
actor IngestionCoordinator: OnboardingEventHandler {
    private let eventBus: EventCoordinator
    private let documentProcessingService: DocumentProcessingService
    private var subscriptionTask: Task<Void, Never>?

    init(
        eventBus: EventCoordinator,
        state: StateCoordinator,
        documentProcessingService: DocumentProcessingService
    ) {
        self.eventBus = eventBus
        self.documentProcessingService = documentProcessingService
        Logger.info("⚙️ IngestionCoordinator initialized", category: .ai)
    }

    func start() async {
        Logger.info("📡 IngestionCoordinator started", category: .ai)
    }

    func stop() {
        subscriptionTask?.cancel()
        subscriptionTask = nil
        Logger.info("🛑 IngestionCoordinator stopped", category: .ai)
    }

    /// Process an evidence upload and store as artifact
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
            Logger.info("✅ Evidence processed and artifact stored (ID: \(record["id"].stringValue))", category: .ai)
        } catch {
            Logger.error("❌ Evidence upload failed: \(error.localizedDescription)", category: .ai)
            await eventBus.publish(.errorOccurred("Failed to process evidence: \(error.localizedDescription)"))
        }

        await eventBus.publish(.processingStateChanged(false))
    }

    func handleEvent(_ event: OnboardingEvent) async {
        // No longer handling individual artifact events - LLM uses list_artifacts when ready
    }
}
