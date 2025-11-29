import Foundation
import SwiftyJSON
/// Coordinator that listens for file uploads linked to evidence requests
/// and triggers background knowledge card generation.
actor IngestionCoordinator: OnboardingEventHandler {
    private let eventBus: EventCoordinator
    private let state: StateCoordinator
    private var agentProvider: () -> KnowledgeCardAgent?
    private let documentProcessingService: DocumentProcessingService
    private var subscriptionTask: Task<Void, Never>?
    init(
        eventBus: EventCoordinator,
        state: StateCoordinator,
        documentProcessingService: DocumentProcessingService,
        agentProvider: @escaping () -> KnowledgeCardAgent?
    ) {
        self.eventBus = eventBus
        self.state = state
        self.documentProcessingService = documentProcessingService
        self.agentProvider = agentProvider
        Logger.info("⚙️ IngestionCoordinator initialized", category: .ai)
    }
    func updateAgentProvider(_ provider: @escaping () -> KnowledgeCardAgent?) {
        self.agentProvider = provider
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
            await processArtifact(record)
        default:
            break
        }
    }
    private func processArtifact(_ record: JSON) async {
        // Check if this artifact is linked to an evidence requirement
        // We assume the metadata contains the requirement ID or timeline entry ID
        let metadata = record["metadata"]
        // Check for direct linkage to an evidence requirement
        guard let requirementId = metadata["evidence_requirement_id"].string else {
            // If not explicitly linked, we might check if it's linked to a timeline entry
            // and infer the requirement, but for now we require explicit linkage.
            return
        }
        Logger.info("⚙️ IngestionCoordinator: Processing artifact for requirement \(requirementId)", category: .ai)
        // Fetch the requirement to get context
        let requirements = await state.evidenceRequirements
        guard let requirement = requirements.first(where: { $0.id == requirementId }) else {
            Logger.warning("⚠️ Evidence requirement not found: \(requirementId)", category: .ai)
            return
        }
        // Fetch the timeline entry
        guard let timeline = await state.artifacts.skeletonTimeline,
              let experiences = timeline["experiences"].array,
              let experience = experiences.first(where: { $0["id"].stringValue == requirement.timelineEntryId }) else {
            Logger.warning("⚠️ Timeline entry not found for requirement: \(requirementId)", category: .ai)
            return
        }
        // Trigger KnowledgeCardAgent
        guard let agent = agentProvider() else {
            Logger.error("❌ KnowledgeCardAgent not available for ingestion", category: .ai)
            return
        }
        // Notify that processing started
        await eventBus.publish(.processingStateChanged(true, statusMessage: "Analyzing evidence for \(experience["role"].stringValue)..."))
        do {
            // Prepare context
            let context = ExperienceContext(
                timelineEntry: experience,
                artifacts: [ArtifactRecord(json: record)],
                transcript: "" // We might want to fetch related transcript segments here
            )
            // Generate draft
            let draft = try await agent.generateCard(for: context)
            // Publish draft
            await eventBus.publish(.draftKnowledgeCardProduced(draft))
            // Update requirement status
            var updatedReq = requirement
            updatedReq.status = .fulfilled
            updatedReq.linkedArtifactId = record["id"].stringValue
            await eventBus.publish(.evidenceRequirementUpdated(updatedReq))
            Logger.info("✅ IngestionCoordinator: Draft generated for \(requirementId)", category: .ai)
        } catch {
            Logger.error("❌ IngestionCoordinator error: \(error.localizedDescription)", category: .ai)
            await eventBus.publish(.errorOccurred("Failed to analyze evidence: \(error.localizedDescription)"))
        }
        await eventBus.publish(.processingStateChanged(false))
    }
}
