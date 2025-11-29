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
        let metadata = record["metadata"]
        let requirementId = metadata["evidence_requirement_id"].string

        // Check if this is during Phase 2 (where we want to auto-generate knowledge cards)
        let currentPhase = await state.phase
        guard currentPhase == .phase2DeepDive else {
            Logger.debug("⏭️ IngestionCoordinator: Skipping artifact processing (not in Phase 2)", category: .ai)
            return
        }

        // Check if we have a KnowledgeCardAgent available
        guard let agent = agentProvider() else {
            Logger.error("❌ KnowledgeCardAgent not available for ingestion", category: .ai)
            return
        }

        // Get timeline for context
        guard let timeline = await state.artifacts.skeletonTimeline,
              let experiences = timeline["experiences"].array,
              !experiences.isEmpty else {
            Logger.warning("⚠️ No timeline experiences available for knowledge card generation", category: .ai)
            return
        }

        // If linked to a requirement, use that context; otherwise, infer from document content
        if let requirementId = requirementId {
            await processLinkedArtifact(record, requirementId: requirementId, agent: agent, experiences: experiences)
        } else {
            await processUnlinkedArtifact(record, agent: agent, experiences: experiences)
        }
    }

    /// Process an artifact that is linked to a specific evidence requirement
    private func processLinkedArtifact(_ record: JSON, requirementId: String, agent: KnowledgeCardAgent, experiences: [JSON]) async {
        Logger.info("⚙️ IngestionCoordinator: Processing linked artifact for requirement \(requirementId)", category: .ai)

        // Fetch the requirement to get context
        let requirements = await state.evidenceRequirements
        guard let requirement = requirements.first(where: { $0.id == requirementId }) else {
            Logger.warning("⚠️ Evidence requirement not found: \(requirementId)", category: .ai)
            return
        }

        // Fetch the timeline entry
        guard let experience = experiences.first(where: { $0["id"].stringValue == requirement.timelineEntryId }) else {
            Logger.warning("⚠️ Timeline entry not found for requirement: \(requirementId)", category: .ai)
            return
        }

        await generateKnowledgeCardDraft(
            record: record,
            experience: experience,
            agent: agent,
            requirementId: requirementId,
            requirement: requirement
        )
    }

    /// Process an artifact uploaded without explicit evidence linkage
    /// Attempts to match the document to relevant timeline experiences
    private func processUnlinkedArtifact(_ record: JSON, agent: KnowledgeCardAgent, experiences: [JSON]) async {
        Logger.info("⚙️ IngestionCoordinator: Processing unlinked artifact - will analyze for relevant experiences", category: .ai)

        // For unlinked documents, we analyze the content and try to match to timeline experiences
        // For now, we'll use the document's extracted text and the most recent experience
        // A more sophisticated approach would use semantic matching

        let documentTitle = record["title"].stringValue
        let extractedText = record["text_content"].string ?? record["extracted_text"].string ?? ""

        // Try to find a relevant experience based on document content keywords
        var matchedExperience: JSON?
        for experience in experiences {
            let role = experience["role"].stringValue.lowercased()
            let company = experience["company"].stringValue.lowercased()

            // Simple keyword matching - check if document mentions company or role
            let searchText = (documentTitle + " " + extractedText).lowercased()
            if !company.isEmpty && searchText.contains(company) {
                matchedExperience = experience
                break
            }
            if !role.isEmpty && searchText.contains(role) {
                matchedExperience = experience
                break
            }
        }

        // If no match found, use the most recent experience (first in list)
        let targetExperience = matchedExperience ?? experiences.first!

        await generateKnowledgeCardDraft(
            record: record,
            experience: targetExperience,
            agent: agent,
            requirementId: nil,
            requirement: nil
        )
    }

    /// Generate a knowledge card draft from an artifact and experience context
    private func generateKnowledgeCardDraft(
        record: JSON,
        experience: JSON,
        agent: KnowledgeCardAgent,
        requirementId: String?,
        requirement: EvidenceRequirement?
    ) async {
        let roleName = experience["role"].stringValue

        // Notify that processing started
        await eventBus.publish(.processingStateChanged(true, statusMessage: "Analyzing document for \(roleName)..."))

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

            // If linked to a requirement, update its status
            if let requirementId = requirementId, var requirement = requirement {
                requirement.status = .fulfilled
                requirement.linkedArtifactId = record["id"].stringValue
                await eventBus.publish(.evidenceRequirementUpdated(requirement))
                Logger.info("✅ IngestionCoordinator: Draft generated for requirement \(requirementId)", category: .ai)
            } else {
                Logger.info("✅ IngestionCoordinator: Draft generated from unlinked document", category: .ai)
            }
        } catch {
            Logger.error("❌ IngestionCoordinator error: \(error.localizedDescription)", category: .ai)
            await eventBus.publish(.errorOccurred("Failed to analyze document: \(error.localizedDescription)"))
        }

        await eventBus.publish(.processingStateChanged(false))
    }
}
