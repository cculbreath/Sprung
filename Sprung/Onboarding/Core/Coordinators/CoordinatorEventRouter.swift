import Foundation
import SwiftyJSON
/// Router responsible for subscribing to and routing coordinator-level events.
/// This component centralizes the event handling logic that was previously in `OnboardingInterviewCoordinator`.
@MainActor
final class CoordinatorEventRouter {
    private let ui: OnboardingUIState
    private let state: StateCoordinator
    private let sessionUIState: SessionUIState
    private let phaseTransitionController: PhaseTransitionController
    private let toolRouter: ToolHandler
    private let applicantProfileStore: ApplicantProfileStore
    private let resRefStore: ResRefStore
    private let coverRefStore: CoverRefStore
    private let experienceDefaultsStore: ExperienceDefaultsStore
    private let eventBus: EventCoordinator
    private let dataStore: InterviewDataStore

    // Pending knowledge card for auto-persist after user confirmation
    private var pendingKnowledgeCard: JSON?

    // Track failed KC agent generations so the coordinator LLM can fall back to manual card creation.
    private var failedKCCards: [(cardId: String, title: String, error: String)] = []

    // Track active extractions to avoid dossier spam during parallel doc ingestion
    // Only trigger dossier when first extraction starts (count goes 0→1)
    // Never reset mid-batch - only when ALL extractions complete
    private var activeExtractionCount: Int = 0
    private var hasDossierTriggeredThisBatch: Bool = false

    init(
        ui: OnboardingUIState,
        state: StateCoordinator,
        sessionUIState: SessionUIState,
        phaseTransitionController: PhaseTransitionController,
        toolRouter: ToolHandler,
        applicantProfileStore: ApplicantProfileStore,
        resRefStore: ResRefStore,
        coverRefStore: CoverRefStore,
        experienceDefaultsStore: ExperienceDefaultsStore,
        eventBus: EventCoordinator,
        dataStore: InterviewDataStore
    ) {
        self.ui = ui
        self.state = state
        self.sessionUIState = sessionUIState
        self.phaseTransitionController = phaseTransitionController
        self.toolRouter = toolRouter
        self.applicantProfileStore = applicantProfileStore
        self.resRefStore = resRefStore
        self.coverRefStore = coverRefStore
        self.experienceDefaultsStore = experienceDefaultsStore
        self.eventBus = eventBus
        self.dataStore = dataStore
    }

    // MARK: - Pending Card Management
    func hasPendingKnowledgeCard() -> Bool {
        pendingKnowledgeCard != nil
    }
    func subscribeToEvents(lifecycle: InterviewLifecycleController) {
        lifecycle.subscribeToEvents { [weak self] event in
            await self?.handleEvent(event)
        }
    }
    private func handleEvent(_ event: OnboardingEvent) async {
        // Log events - use debug level for high-frequency streaming events to reduce console noise
        switch event {
        case .streamingMessageUpdated, .llmReasoningSummaryDelta:
            Logger.debug("📊 CoordinatorEventRouter: Processing event: \(String(describing: event))", category: .ai)
        default:
            Logger.info("📊 CoordinatorEventRouter: Processing event: \(String(describing: event))", category: .ai)
        }
        switch event {
        case .objectiveStatusChanged(let id, _, let newStatus, _, _, _, _):
            Logger.debug("📊 CoordinatorEventRouter: objectiveStatusChanged received - id=\(id), newStatus=\(newStatus)", category: .ai)
            // Update UI state for views to track objective progress
            ui.objectiveStatuses[id] = newStatus
            if id == "applicant_profile" && newStatus == "completed" {
                Logger.info("📊 CoordinatorEventRouter: Dismissing profile summary for applicant_profile completion", category: .ai)
                toolRouter.profileHandler.dismissProfileSummary()
            }
        case .timelineUIUpdateNeeded:
            // Timeline UI updates are now handled by UIStateUpdateHandler via topic-specific stream
            // This provides immediate updates without waiting in the congested streamAll() queue
            break
        case .processingStateChanged:
            break
        case .streamingMessageBegan, .streamingMessageUpdated, .streamingMessageFinalized:
            break
        case .llmReasoningSummaryDelta, .llmReasoningSummaryComplete:
            break
        case .streamingStatusUpdated:
            break
        case .waitingStateChanged:
            break
        case .errorOccurred(let error):
            Logger.error("Interview error: \(error)", category: .ai)
            // Errors are now displayed via spinner status message, not popup alerts
        case .llmUserMessageFailed(let messageId, let originalText, let error):
            // Handle failed message: remove from transcript and prepare for input restoration
            ui.handleMessageFailure(messageId: messageId, originalText: originalText, error: error)
        // MARK: - Evidence & Draft Events (Phase 2)
        case .evidenceRequirementAdded(let req):
            ui.evidenceRequirements.append(req)
        case .evidenceRequirementUpdated(let req):
            if let index = ui.evidenceRequirements.firstIndex(where: { $0.id == req.id }) {
                ui.evidenceRequirements[index] = req
            }
        case .evidenceRequirementRemoved(let id):
            ui.evidenceRequirements.removeAll { $0.id == id }
        case .applicantProfileStored:
            // Handled by ProfilePersistenceHandler
            break
        case .skeletonTimelineStored, .enabledSectionsUpdated:
            break
        case .experienceDefaultsGenerated(let defaults):
            await handleExperienceDefaultsGenerated(defaults)
        case .toolCallRequested:
            break
        case .toolCallCompleted:
            break
        case .objectiveStatusRequested(let id, let response):
            Logger.info("📊 CoordinatorEventRouter: objectiveStatusRequested - awaiting status for \(id)", category: .ai)
            let status = await state.getObjectiveStatus(id)?.rawValue
            response(status)
            Logger.info("📊 CoordinatorEventRouter: objectiveStatusRequested - completed for \(id)", category: .ai)
        case .phaseTransitionApplied(let phaseName, _):
            await phaseTransitionController.handlePhaseTransition(phaseName)
            if let phase = InterviewPhase(rawValue: phaseName) {
                ui.phase = phase
                Logger.info("📊 CoordinatorEventRouter: UI phase updated to \(phase.rawValue)", category: .ai)
                // Persist data when transitioning to complete
                if phase == .complete {
                    Logger.info("🏁 CoordinatorEventRouter: Phase is COMPLETE - calling persistWritingCorpusOnComplete()", category: .ai)
                    await persistWritingCorpusOnComplete()
                    Logger.info("🏁 CoordinatorEventRouter: persistWritingCorpusOnComplete() finished, calling propagateExperienceDefaults()", category: .ai)
                    await propagateExperienceDefaults()
                    Logger.info("🏁 CoordinatorEventRouter: propagateExperienceDefaults() finished", category: .ai)
                }
            } else {
                Logger.warning("📊 CoordinatorEventRouter: Could not convert phaseName '\(phaseName)' to InterviewPhase", category: .ai)
            }

        // MARK: - Knowledge Card Workflow Events
        case .knowledgeCardDoneButtonClicked(let itemId):
            await handleDoneButtonClicked(itemId: itemId)

        case .knowledgeCardSubmissionPending(let card):
            pendingKnowledgeCard = card
            Logger.info("📝 Pending knowledge card stored: \(card["title"].stringValue)", category: .ai)

        case .knowledgeCardAutoPersistRequested:
            await handleAutoPersistRequested()

        case .planItemStatusChangeRequested(let itemId, let status):
            await handlePlanItemStatusChange(itemId: itemId, status: status)

        // MARK: - Multi-Agent KC Generation Workflow
        case .generateCardsButtonClicked:
            await handleGenerateCardsButtonClicked()

        case .cardAssignmentsProposed:
            // Event handled by UI for awareness; gating done in tool
            Logger.info("📋 Card assignments proposed - dispatch_kc_agents gated until user approval", category: .ai)

        // MARK: - KC Auto-Validation (from Agent Completion)
        case .kcAgentCompleted(let agentId, let cardId, let cardTitle):
            await handleKCAgentCompleted(agentId: agentId, cardId: cardId, cardTitle: cardTitle)

        case .kcAgentFailed(let agentId, let cardId, let error):
            await handleKCAgentFailed(agentId: agentId, cardId: cardId, error: error)

        case .kcAgentsDispatchCompleted(let successCount, let failureCount):
            await handleKCAgentsDispatchCompleted(successCount: successCount, failureCount: failureCount)

        case .kcAutoValidationApproved:
            await handleKCAutoValidationApproved()

        case .kcAutoValidationRejected(let reason):
            await handleKCAutoValidationRejected(reason: reason)

        // MARK: - Dossier Collection Trigger (Parallel-Safe)
        case .extractionStateChanged(let inProgress, _):
            if inProgress {
                // Increment active count
                activeExtractionCount += 1
                // Only trigger dossier when FIRST extraction starts (0→1 transition)
                if activeExtractionCount == 1 && !hasDossierTriggeredThisBatch {
                    hasDossierTriggeredThisBatch = true
                    await triggerDossierCollection()
                }
            } else {
                // Decrement active count
                activeExtractionCount = max(0, activeExtractionCount - 1)
                // Only reset the batch flag when ALL extractions are complete
                if activeExtractionCount == 0 {
                    hasDossierTriggeredThisBatch = false
                }
            }

        // All other events are handled elsewhere or don't need handling here
        default:
            break
        }
    }

    // MARK: - Dossier Collection

    /// Trigger opportunistic dossier question when extraction starts
    private func triggerDossierCollection() async {
        // Only trigger opportunistic dossier questions in Phase 2
        let currentPhase = await state.phase
        guard currentPhase == .phase2DeepDive else {
            Logger.debug("📋 Skipping dossier trigger - not in Phase 2", category: .ai)
            return
        }

        // Build a dossier prompt for the current phase
        guard let prompt = await state.buildDossierPrompt() else {
            Logger.debug("📋 No uncollected dossier fields for current phase", category: .ai)
            return
        }

        // Send as developer message (bypasses queue) so LLM treats it as instruction, not user input
        // This prevents the LLM from directly acknowledging the instruction text
        var payload = JSON()
        payload["text"].string = prompt
        await eventBus.publish(.llmExecuteDeveloperMessage(payload: payload))
        Logger.info("📋 Triggered dossier collection during extraction", category: .ai)
    }

    // MARK: - Knowledge Card Event Handlers

    /// Handle "Done with this card" button click
    private func handleDoneButtonClicked(itemId: String?) async {
        // Clear batch upload flag - user clicking "Done" means they're done with uploads
        // This is a safety measure in case batch completion didn't fire properly
        if ui.hasBatchUploadInProgress {
            ui.hasBatchUploadInProgress = false
            Logger.info("📦 Cleared batch upload flag on 'Done' button click", category: .ai)
        }

        // Ungate submit_knowledge_card tool
        await state.includeTool(OnboardingToolName.submitKnowledgeCard.rawValue)

        // Send system-generated user message to trigger LLM response
        // Using user message instead of developer message ensures the LLM responds immediately
        // Force toolChoice to ensure the LLM calls submit_knowledge_card
        let itemInfo = itemId ?? "unknown"
        var userMessage = JSON()
        userMessage["role"].string = "user"
        userMessage["content"].string = """
            I'm done with the "\(itemInfo)" card. \
            Please generate and submit the knowledge card now.
            """
        await eventBus.publish(.llmEnqueueUserMessage(
            payload: userMessage,
            isSystemGenerated: true,
            toolChoice: OnboardingToolName.submitKnowledgeCard.rawValue
        ))

        Logger.info("✅ Done button handled: tool ungated, user message sent with forced toolChoice for item '\(itemInfo)'", category: .ai)
    }

    /// Handle auto-persist request after user confirms
    private func handleAutoPersistRequested() async {
        guard let card = pendingKnowledgeCard else {
            Logger.warning("⚠️ Auto-persist requested but no pending card", category: .ai)
            return
        }

        let cardTitle = card["title"].stringValue
        Logger.info("💾 Persisting knowledge card to SwiftData: \(cardTitle)", category: .ai)

        // Persist to SwiftData (ResRef) - single source of truth for knowledge cards
        persistToResRef(card: card)

        // Emit persisted event (for UI updates)
        await eventBus.publish(.knowledgeCardPersisted(card: card))

        // Update plan item status if linked
        if let planItemId = card["plan_item_id"].string {
            await handlePlanItemStatusChange(itemId: planItemId, status: "completed")
        }

        // Clear pending card
        pendingKnowledgeCard = nil

        // Emit success event
        await eventBus.publish(.knowledgeCardAutoPersisted(title: cardTitle))

        // Send LLM message about successful persistence
        var userMessage = JSON()
        userMessage["role"].string = "user"
        userMessage["content"].string = """
            Knowledge card confirmed and persisted: "\(cardTitle)".
            The plan item has been marked complete.
            Proceed to the next pending plan item, or call display_knowledge_card_plan to see progress.
            """
        await eventBus.publish(.llmEnqueueUserMessage(payload: userMessage, isSystemGenerated: true))

        Logger.info("✅ Knowledge card persisted: \(cardTitle)", category: .ai)
    }

    /// Handle "Generate Cards" button click - ungates dispatch_kc_agents and mandates its use
    private func handleGenerateCardsButtonClicked() async {
        Logger.info("🚀 Generate Cards button clicked - ungating dispatch_kc_agents", category: .ai)

        // Ungate dispatch_kc_agents tool
        await state.includeTool(OnboardingToolName.dispatchKCAgents.rawValue)

        // Send system-generated user message with forced toolChoice
        var userMessage = JSON()
        userMessage["role"].string = "user"
        userMessage["content"].string = """
            I've reviewed the card assignments and I'm ready to generate the knowledge cards. \
            Please proceed with generating the cards now.
            """
        await eventBus.publish(.llmEnqueueUserMessage(
            payload: userMessage,
            isSystemGenerated: true,
            toolChoice: OnboardingToolName.dispatchKCAgents.rawValue
        ))

        Logger.info("✅ Generate Cards: tool ungated, user message sent with forced toolChoice for dispatch_kc_agents", category: .ai)
    }

    // MARK: - KC Auto-Validation Handler

    /// Handle KC agent failure - surface error to user
    private func handleKCAgentFailed(agentId: String, cardId: String, error: String) async {
        Logger.error("❌ KC agent failed: cardId=\(cardId.prefix(8)), error=\(error)", category: .ai)

        // Ensure manual fallback tool is available (subphase bundling must also include it).
        await state.includeTool(OnboardingToolName.submitKnowledgeCard.rawValue)

        // Capture failure details for a single summary message after dispatch completes.
        let planItems = await MainActor.run { ui.knowledgeCardPlan }
        let title = planItems.first(where: { $0.id == cardId })?.title ?? "Unknown card"
        failedKCCards.append((cardId: cardId, title: title, error: error))

        // Surface error to user via the error event (displayed in chat/UI)
        let failureMessage = "Knowledge card generation failed: \(error)"
        await eventBus.publish(.errorOccurred(failureMessage))
    }

    /// After all agents finish, instruct the coordinator LLM to fill gaps manually if needed.
    private func handleKCAgentsDispatchCompleted(successCount: Int, failureCount: Int) async {
        guard failureCount > 0 else {
            failedKCCards.removeAll()
            return
        }

        await state.includeTool(OnboardingToolName.submitKnowledgeCard.rawValue)

        let failures = failedKCCards
        failedKCCards.removeAll()

        var lines: [String] = []
        lines.append("Some knowledge card agents failed (\(failureCount) failed, \(successCount) succeeded).")
        if !failures.isEmpty {
            lines.append("")
            lines.append("Failed cards to create manually:")
            for item in failures.prefix(10) {
                lines.append("- \(item.title) (card_id: \(item.cardId))")
            }
        }
        lines.append("")
        lines.append("Please create replacement cards manually using `submit_knowledge_card` (full card object + summary).")
        lines.append("Use `get_context_pack` (optionally with `card_id`) and `list_artifacts/get_artifact` to pull the needed evidence first.")

        var userMessage = JSON()
        userMessage["role"].string = "user"
        userMessage["content"].string = lines.joined(separator: "\n")
        await eventBus.publish(.llmEnqueueUserMessage(payload: userMessage, isSystemGenerated: true))

        Logger.info("🛟 Manual KC fallback activated: submit_knowledge_card ungated after agent failures", category: .ai)
    }

    /// Handle KC agent completion - auto-present validation UI without LLM tool call
    /// Cards are queued and presented immediately as they complete
    private func handleKCAgentCompleted(agentId: String, cardId: String, cardTitle: String) async {
        Logger.info("🎉 KC agent completed: '\(cardTitle)' (cardId: \(cardId.prefix(8)), agentId: \(agentId.prefix(8)))", category: .ai)

        // Enqueue this card for validation
        await sessionUIState.enqueueKCValidation(cardId)

        // Check if validation UI is already showing
        let currentValidation = await sessionUIState.pendingValidationPrompt
        if currentValidation != nil {
            // Another validation is in progress - card is already queued
            Logger.info("📋 KC validation queued (another validation in progress): \(cardTitle)", category: .ai)
            return
        }

        // No active validation - present this card immediately
        await presentNextKCValidation()
    }

    /// Present the next card from the KC validation queue
    private func presentNextKCValidation() async {
        // Dequeue the next card ID
        guard let cardId = await sessionUIState.dequeueNextKCValidation() else {
            Logger.debug("📋 No KC validations in queue", category: .ai)
            return
        }

        // Retrieve the pending card from state
        guard let card = await state.getPendingCard(id: cardId) else {
            Logger.warning("⚠️ KC auto-validation: pending card not found for ID \(cardId.prefix(8))", category: .ai)
            // Try the next card in queue
            if await sessionUIState.hasQueuedKCValidations() {
                await presentNextKCValidation()
            }
            return
        }

        let cardTitle = card["card"]["title"].stringValue

        // Mark as auto-validation (not tool-initiated)
        await sessionUIState.setAutoValidation(true)

        // Store as pending knowledge card for auto-persist
        pendingKnowledgeCard = card

        // Build summary for validation UI
        let wordCount = card["card"]["content"].stringValue.components(separatedBy: .whitespacesAndNewlines).count
        let summary = "Knowledge card for \(cardTitle) (\(wordCount) words)"

        // Create validation prompt
        let prompt = OnboardingValidationPrompt(
            dataType: "knowledge_card",
            payload: card["card"],
            message: summary
        )

        // Emit validation prompt request (will show UI)
        await eventBus.publish(.validationPromptRequested(prompt: prompt))
        Logger.info("🎯 KC auto-validation presented: \(cardTitle)", category: .ai)
    }

    /// Present next KC validation after user completes one (called from UIResponseCoordinator)
    func presentNextKCValidationIfQueued() async {
        if await sessionUIState.hasQueuedKCValidations() {
            await presentNextKCValidation()
        } else {
            // Clear auto-validation flag when queue is empty
            await sessionUIState.setAutoValidation(false)
        }
    }

    /// Handle KC auto-validation approval - persist card and send developer message
    private func handleKCAutoValidationApproved() async {
        guard let card = pendingKnowledgeCard else {
            Logger.warning("⚠️ KC auto-validation approved but no pending card", category: .ai)
            await presentNextKCValidationIfQueued()
            return
        }

        let cardData = card["card"]
        let cardTitle = cardData["title"].stringValue
        let cardId = cardData["id"].stringValue

        // Persist to ResRef
        persistToResRef(card: cardData)

        // Clear pending card
        pendingKnowledgeCard = nil

        // Remove from pending storage
        await state.removePendingCard(id: cardId)

        // Clear validation prompt
        toolRouter.clearValidationPrompt()
        await eventBus.publish(.validationPromptCleared)

        // Send developer message to LLM
        let message = """
        Knowledge card "\(cardTitle)" has been approved and persisted.
        Card ID: \(cardId)
        """
        await eventBus.publish(.llmSendDeveloperMessage(payload: JSON(["text": message])))

        Logger.info("✅ KC auto-validation approved and persisted: \(cardTitle)", category: .ai)

        // Present next card from queue (if any)
        await presentNextKCValidationIfQueued()
    }

    /// Handle KC auto-validation rejection - send developer message with reason
    private func handleKCAutoValidationRejected(reason: String) async {
        guard let card = pendingKnowledgeCard else {
            Logger.warning("⚠️ KC auto-validation rejected but no pending card", category: .ai)
            await presentNextKCValidationIfQueued()
            return
        }

        let cardData = card["card"]
        let cardTitle = cardData["title"].stringValue
        let cardId = cardData["id"].stringValue

        // Clear pending card (not persisted)
        pendingKnowledgeCard = nil

        // Remove from pending storage (rejected, won't be resubmitted automatically)
        await state.removePendingCard(id: cardId)

        // Clear validation prompt
        toolRouter.clearValidationPrompt()
        await eventBus.publish(.validationPromptCleared)

        // Send developer message to LLM
        let message = """
        Knowledge card "\(cardTitle)" was rejected by the user.
        Card ID: \(cardId)
        Reason: \(reason)
        You may dispatch another KC agent to regenerate this card if needed.
        """
        await eventBus.publish(.llmSendDeveloperMessage(payload: JSON(["text": message])))

        Logger.info("❌ KC auto-validation rejected: \(cardTitle) - \(reason)", category: .ai)

        // Present next card from queue (if any)
        await presentNextKCValidationIfQueued()
    }

    /// Persist knowledge card to SwiftData as a ResRef for use in resume generation
    private func persistToResRef(card: JSON) {
        let title = card["title"].stringValue
        let content = card["content"].stringValue
        let cardType = card["type"].string
        let timePeriod = card["time_period"].string
        let organization = card["organization"].string
        let location = card["location"].string

        // Encode sources array as JSON string
        var sourcesJSON: String?
        if let sourcesArray = card["sources"].array, !sourcesArray.isEmpty {
            if let data = try? JSON(sourcesArray).rawData(),
               let jsonString = String(data: data, encoding: .utf8) {
                sourcesJSON = jsonString
            }
        }

        let resRef = ResRef(
            name: title,
            content: content,
            enabledByDefault: true,  // Knowledge cards default to enabled
            cardType: cardType,
            timePeriod: timePeriod,
            organization: organization,
            location: location,
            sourcesJSON: sourcesJSON,
            isFromOnboarding: true
        )

        resRefStore.addResRef(resRef)
        Logger.info("✅ Knowledge card persisted to ResRef (SwiftData): \(title)", category: .ai)
    }

    /// Handle plan item status change request - updates UI state directly
    private func handlePlanItemStatusChange(itemId: String, status: String) async {
        // Convert status string to enum
        let planStatus: KnowledgeCardPlanItem.Status
        switch status.lowercased() {
        case "completed":
            planStatus = .completed
        case "in_progress":
            planStatus = .inProgress
        case "skipped":
            planStatus = .skipped
        default:
            planStatus = .pending
        }

        // Update UI state directly (no coordinator needed)
        guard let index = ui.knowledgeCardPlan.firstIndex(where: { $0.id == itemId }) else {
            Logger.warning("⚠️ Could not find plan item \(itemId) to update status", category: .ai)
            return
        }
        let item = ui.knowledgeCardPlan[index]
        ui.knowledgeCardPlan[index] = KnowledgeCardPlanItem(
            id: item.id,
            title: item.title,
            type: item.type,
            description: item.description,
            status: planStatus,
            timelineEntryId: item.timelineEntryId
        )
        Logger.info("📋 Plan item status updated: \(itemId) → \(status)", category: .ai)
    }

    // MARK: - Writing Corpus Persistence

    /// Persist writing samples to CoverRefStore and candidate dossier to ResRefStore when interview completes
    private func persistWritingCorpusOnComplete() async {
        Logger.info("💾 [persistWritingCorpus] START - Persisting writing corpus and dossier on interview completion", category: .ai)

        // Get artifact records from UI state (synced from StateCoordinator)
        let artifacts = ui.artifactRecords
        Logger.info("💾 [persistWritingCorpus] Found \(artifacts.count) total artifact records in UI state", category: .ai)

        // Debug: Log all artifact source_type and document_type fields
        for (index, artifact) in artifacts.enumerated() {
            let sourceType = artifact["source_type"].stringValue
            let docType = artifact["document_type"].stringValue
            let hasWritingType = artifact["metadata"]["writing_type"].exists()
            let filename = artifact["filename"].stringValue
            Logger.debug("💾 [persistWritingCorpus] Artifact[\(index)]: filename='\(filename)' source_type='\(sourceType)' document_type='\(docType)' has_writing_type=\(hasWritingType)", category: .ai)
        }

        // Persist writing samples to CoverRefStore
        // Check multiple fields since writing samples can come from different sources:
        // - IngestWritingSampleTool: sets source_type = "writing_sample"
        // - File uploads via get_user_upload (Phase 3 writing sample flow): sets document_type = "writing_sample"
        let writingSamples = artifacts.filter { artifact in
            artifact["source_type"].stringValue == "writing_sample" ||
            artifact["document_type"].stringValue == "writing_sample" ||
            artifact["document_type"].stringValue == "writingSample" || // legacy
            artifact["metadata"]["writing_type"].exists()
        }
        Logger.info("💾 [persistWritingCorpus] Filtered to \(writingSamples.count) writing samples", category: .ai)

        for sample in writingSamples {
            persistWritingSampleToCoverRef(sample: sample)
        }

        Logger.info("✅ [persistWritingCorpus] Persisted \(writingSamples.count) writing samples to CoverRefStore", category: .ai)

        // Persist candidate dossier if present (to CoverRefStore for cover letter generation)
        // Fetch from InterviewDataStore where SubmitCandidateDossierTool persists it
        Logger.info("💾 [persistWritingCorpus] Checking InterviewDataStore for candidate_dossier...", category: .ai)
        let dossiers = await dataStore.list(dataType: "candidate_dossier")
        Logger.info("💾 [persistWritingCorpus] Found \(dossiers.count) dossier(s) in data store", category: .ai)

        if let dossier = dossiers.first {
            Logger.info("💾 [persistWritingCorpus] Dossier found with keys: \(dossier.dictionaryValue.keys.sorted())", category: .ai)
            persistDossierToCoverRef(dossier: dossier)
            Logger.info("✅ [persistWritingCorpus] Persisted candidate dossier to CoverRefStore", category: .ai)
        } else {
            Logger.warning("⚠️ [persistWritingCorpus] No candidate dossier found in data store - was submit_candidate_dossier tool called?", category: .ai)
        }

        // Emit events for persistence completion
        await eventBus.publish(.writingSamplePersisted(sample: JSON(["count": writingSamples.count])))
        Logger.info("💾 [persistWritingCorpus] END - Persistence complete", category: .ai)
    }

    /// Convert a writing sample artifact to CoverRef and persist
    private func persistWritingSampleToCoverRef(sample: JSON) {
        let name = sample["metadata"]["name"].string ??
                   sample["filename"].stringValue.replacingOccurrences(of: ".txt", with: "")
        let content = sample["extracted_text"].stringValue

        // Skip if no content
        guard !content.isEmpty else {
            Logger.warning("⚠️ Skipping writing sample with empty content: \(name)", category: .ai)
            return
        }

        let coverRef = CoverRef(
            name: name,
            content: content,
            enabledByDefault: true,
            type: .writingSample
        )

        coverRefStore.addCoverRef(coverRef)
        Logger.info("💾 Writing sample persisted to CoverRef: \(name)", category: .ai)
    }

    /// Convert candidate dossier to CoverRef and persist (for cover letter generation)
    private func persistDossierToCoverRef(dossier: JSON) {
        let name = "Candidate Dossier"

        // Build content from dossier fields
        var contentParts: [String] = []

        if let jobContext = dossier["job_search_context"].string, !jobContext.isEmpty {
            contentParts.append("Job Search Context:\n\(jobContext)")
        }
        if let workPrefs = dossier["work_arrangement_preferences"].string, !workPrefs.isEmpty {
            contentParts.append("Work Arrangement Preferences:\n\(workPrefs)")
        }
        if let availability = dossier["availability"].string, !availability.isEmpty {
            contentParts.append("Availability:\n\(availability)")
        }
        if let circumstances = dossier["unique_circumstances"].string, !circumstances.isEmpty {
            contentParts.append("Unique Circumstances:\n\(circumstances)")
        }
        if let strengths = dossier["strengths_to_emphasize"].string, !strengths.isEmpty {
            contentParts.append("Strengths to Emphasize:\n\(strengths)")
        }
        if let pitfalls = dossier["pitfalls_to_avoid"].string, !pitfalls.isEmpty {
            contentParts.append("Pitfalls to Avoid:\n\(pitfalls)")
        }
        if let notes = dossier["notes"].string, !notes.isEmpty {
            contentParts.append("Notes:\n\(notes)")
        }

        let content = contentParts.joined(separator: "\n\n")

        // Skip if no content
        guard !content.isEmpty else {
            Logger.warning("⚠️ Skipping dossier with empty content", category: .ai)
            return
        }

        // Use backgroundFact type for dossier - it provides candidate background context
        let coverRef = CoverRef(
            name: name,
            content: content,
            enabledByDefault: true,
            type: .backgroundFact,
            isDossier: true
        )

        coverRefStore.addCoverRef(coverRef)
        Logger.info("💾 Candidate dossier persisted to CoverRef: \(name)", category: .ai)
    }

    // MARK: - Experience Defaults Propagation

    /// Propagate timeline cards to ExperienceDefaults when interview completes
    private func propagateExperienceDefaults() async {
        Logger.info("📋 Propagating timeline cards to ExperienceDefaults", category: .ai)

        guard let timeline = ui.skeletonTimeline,
              let experiences = timeline["experiences"].array else {
            Logger.warning("⚠️ No timeline experiences to propagate", category: .ai)
            return
        }

        // Load current draft
        var draft = experienceDefaultsStore.loadDraft()

        // Process each timeline card based on experience_type
        for card in experiences {
            let experienceType = card["experience_type"].string ?? "work"

            switch experienceType {
            case "work":
                let workDraft = createWorkExperienceDraft(from: card)
                draft.work.append(workDraft)
                draft.isWorkEnabled = true

            case "education":
                let eduDraft = createEducationDraft(from: card)
                draft.education.append(eduDraft)
                draft.isEducationEnabled = true

            case "volunteer":
                let volDraft = createVolunteerDraft(from: card)
                draft.volunteer.append(volDraft)
                draft.isVolunteerEnabled = true

            case "project":
                let projDraft = createProjectDraft(from: card)
                draft.projects.append(projDraft)
                draft.isProjectsEnabled = true

            default:
                // Default to work experience
                let workDraft = createWorkExperienceDraft(from: card)
                draft.work.append(workDraft)
                draft.isWorkEnabled = true
            }
        }

        // Save the draft
        experienceDefaultsStore.save(draft: draft)
        Logger.info("✅ Propagated \(experiences.count) timeline cards to ExperienceDefaults", category: .ai)
    }

    private func createWorkExperienceDraft(from card: JSON) -> WorkExperienceDraft {
        var draft = WorkExperienceDraft()
        draft.name = card["organization"].stringValue
        draft.position = card["title"].stringValue
        draft.location = card["location"].stringValue
        draft.url = card["url"].stringValue
        draft.startDate = card["start"].stringValue
        draft.endDate = card["end"].stringValue
        draft.summary = card["summary"].stringValue
        draft.highlights = card["highlights"].arrayValue.map { highlight in
            var h = HighlightDraft()
            h.text = highlight.stringValue
            return h
        }
        return draft
    }

    private func createEducationDraft(from card: JSON) -> EducationExperienceDraft {
        var draft = EducationExperienceDraft()
        draft.institution = card["organization"].stringValue
        draft.url = card["url"].stringValue
        draft.area = card["title"].stringValue
        draft.startDate = card["start"].stringValue
        draft.endDate = card["end"].stringValue
        return draft
    }

    private func createVolunteerDraft(from card: JSON) -> VolunteerExperienceDraft {
        var draft = VolunteerExperienceDraft()
        draft.organization = card["organization"].stringValue
        draft.position = card["title"].stringValue
        draft.url = card["url"].stringValue
        draft.startDate = card["start"].stringValue
        draft.endDate = card["end"].stringValue
        draft.summary = card["summary"].stringValue
        draft.highlights = card["highlights"].arrayValue.map { highlight in
            var h = VolunteerHighlightDraft()
            h.text = highlight.stringValue
            return h
        }
        return draft
    }

    private func createProjectDraft(from card: JSON) -> ProjectExperienceDraft {
        var draft = ProjectExperienceDraft()
        draft.name = card["title"].stringValue
        draft.description = card["summary"].stringValue
        draft.startDate = card["start"].stringValue
        draft.endDate = card["end"].stringValue
        draft.url = card["url"].stringValue
        draft.organization = card["organization"].stringValue
        draft.highlights = card["highlights"].arrayValue.map { highlight in
            var h = ProjectHighlightDraft()
            h.text = highlight.stringValue
            return h
        }
        return draft
    }

    // MARK: - LLM-Generated Experience Defaults

    /// Handle experience defaults generated by LLM from knowledge cards
    private func handleExperienceDefaultsGenerated(_ defaults: JSON) async {
        Logger.info("📋 Processing LLM-generated experience defaults", category: .ai)

        var draft = ExperienceDefaultsDraft()

        // Process work experiences
        if let workArray = defaults["work"].array, !workArray.isEmpty {
            draft.isWorkEnabled = true
            draft.work = workArray.map { createWorkDraftFromLLM($0) }
            Logger.info("📋 Added \(workArray.count) work experiences", category: .ai)
        }

        // Process education
        if let eduArray = defaults["education"].array, !eduArray.isEmpty {
            draft.isEducationEnabled = true
            draft.education = eduArray.map { createEducationDraftFromLLM($0) }
            Logger.info("📋 Added \(eduArray.count) education entries", category: .ai)
        }

        // Process projects
        if let projArray = defaults["projects"].array, !projArray.isEmpty {
            draft.isProjectsEnabled = true
            draft.projects = projArray.map { createProjectDraftFromLLM($0) }
            Logger.info("📋 Added \(projArray.count) projects", category: .ai)
        }

        // Process skills
        if let skillsArray = defaults["skills"].array, !skillsArray.isEmpty {
            draft.isSkillsEnabled = true
            draft.skills = skillsArray.map { createSkillDraftFromLLM($0) }
            Logger.info("📋 Added \(skillsArray.count) skill categories", category: .ai)
        }

        // Process languages
        if let langArray = defaults["languages"].array, !langArray.isEmpty {
            draft.isLanguagesEnabled = true
            draft.languages = langArray.map { createLanguageDraftFromLLM($0) }
            Logger.info("📋 Added \(langArray.count) languages", category: .ai)
        }

        // Process volunteer experiences
        if let volArray = defaults["volunteer"].array, !volArray.isEmpty {
            draft.isVolunteerEnabled = true
            draft.volunteer = volArray.map { createVolunteerDraftFromLLM($0) }
            Logger.info("📋 Added \(volArray.count) volunteer experiences", category: .ai)
        }

        // Process awards
        if let awardsArray = defaults["awards"].array, !awardsArray.isEmpty {
            draft.isAwardsEnabled = true
            draft.awards = awardsArray.map { createAwardDraftFromLLM($0) }
            Logger.info("📋 Added \(awardsArray.count) awards", category: .ai)
        }

        // Process certificates
        if let certsArray = defaults["certificates"].array, !certsArray.isEmpty {
            draft.isCertificatesEnabled = true
            draft.certificates = certsArray.map { createCertificateDraftFromLLM($0) }
            Logger.info("📋 Added \(certsArray.count) certificates", category: .ai)
        }

        // Process publications
        if let pubsArray = defaults["publications"].array, !pubsArray.isEmpty {
            draft.isPublicationsEnabled = true
            draft.publications = pubsArray.map { createPublicationDraftFromLLM($0) }
            Logger.info("📋 Added \(pubsArray.count) publications", category: .ai)
        }

        // Process professional summary
        if let summary = defaults["professional_summary"].string,
           !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
            Logger.info("📋 Added professional summary", category: .ai)
        }

        // Save the draft
        experienceDefaultsStore.save(draft: draft)
        Logger.info("✅ Saved LLM-generated experience defaults to store", category: .ai)
    }

    // MARK: - LLM JSON to Draft Converters

    private func createWorkDraftFromLLM(_ json: JSON) -> WorkExperienceDraft {
        var draft = WorkExperienceDraft()
        draft.name = json["name"].stringValue
        draft.position = json["position"].stringValue
        draft.location = json["location"].stringValue
        draft.url = json["url"].stringValue
        draft.startDate = json["startDate"].stringValue
        draft.endDate = json["endDate"].stringValue
        draft.summary = json["summary"].stringValue
        draft.highlights = json["highlights"].arrayValue.map { highlight in
            var h = HighlightDraft()
            h.text = highlight.stringValue
            return h
        }
        return draft
    }

    private func createEducationDraftFromLLM(_ json: JSON) -> EducationExperienceDraft {
        var draft = EducationExperienceDraft()
        draft.institution = json["institution"].stringValue
        draft.url = json["url"].stringValue
        draft.area = json["area"].stringValue
        draft.studyType = json["studyType"].stringValue
        draft.startDate = json["startDate"].stringValue
        draft.endDate = json["endDate"].stringValue
        draft.score = json["score"].stringValue
        draft.courses = json["courses"].arrayValue.map { course in
            var c = CourseDraft()
            c.name = course.stringValue
            return c
        }
        return draft
    }

    private func createProjectDraftFromLLM(_ json: JSON) -> ProjectExperienceDraft {
        var draft = ProjectExperienceDraft()
        draft.name = json["name"].stringValue
        draft.description = json["description"].stringValue
        draft.startDate = json["startDate"].stringValue
        draft.endDate = json["endDate"].stringValue
        draft.url = json["url"].stringValue
        draft.organization = json["organization"].stringValue
        draft.type = json["type"].stringValue
        draft.highlights = json["highlights"].arrayValue.map { highlight in
            var h = ProjectHighlightDraft()
            h.text = highlight.stringValue
            return h
        }
        draft.keywords = json["keywords"].arrayValue.map { kw in
            KeywordDraft(keyword: kw.stringValue)
        }
        draft.roles = json["roles"].arrayValue.map { role in
            RoleDraft(role: role.stringValue)
        }
        return draft
    }

    private func createSkillDraftFromLLM(_ json: JSON) -> SkillExperienceDraft {
        var draft = SkillExperienceDraft()
        draft.name = json["name"].stringValue
        draft.level = json["level"].stringValue
        draft.keywords = json["keywords"].arrayValue.map { kw in
            KeywordDraft(keyword: kw.stringValue)
        }
        return draft
    }

    private func createLanguageDraftFromLLM(_ json: JSON) -> LanguageExperienceDraft {
        var draft = LanguageExperienceDraft()
        draft.language = json["language"].stringValue
        draft.fluency = json["fluency"].stringValue
        return draft
    }

    private func createVolunteerDraftFromLLM(_ json: JSON) -> VolunteerExperienceDraft {
        var draft = VolunteerExperienceDraft()
        draft.organization = json["organization"].stringValue
        draft.position = json["position"].stringValue
        draft.url = json["url"].stringValue
        draft.startDate = json["startDate"].stringValue
        draft.endDate = json["endDate"].stringValue
        draft.summary = json["summary"].stringValue
        draft.highlights = json["highlights"].arrayValue.map { highlight in
            var h = VolunteerHighlightDraft()
            h.text = highlight.stringValue
            return h
        }
        return draft
    }

    private func createAwardDraftFromLLM(_ json: JSON) -> AwardExperienceDraft {
        var draft = AwardExperienceDraft()
        draft.title = json["title"].stringValue
        draft.date = json["date"].stringValue
        draft.awarder = json["awarder"].stringValue
        draft.summary = json["summary"].stringValue
        return draft
    }

    private func createCertificateDraftFromLLM(_ json: JSON) -> CertificateExperienceDraft {
        var draft = CertificateExperienceDraft()
        draft.name = json["name"].stringValue
        draft.date = json["date"].stringValue
        draft.issuer = json["issuer"].stringValue
        draft.url = json["url"].stringValue
        return draft
    }

    private func createPublicationDraftFromLLM(_ json: JSON) -> PublicationExperienceDraft {
        var draft = PublicationExperienceDraft()
        draft.name = json["name"].stringValue
        draft.publisher = json["publisher"].stringValue
        draft.releaseDate = json["releaseDate"].stringValue
        draft.url = json["url"].stringValue
        draft.summary = json["summary"].stringValue
        return draft
    }
}
