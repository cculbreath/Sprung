import Foundation
import SwiftyJSON
/// Router responsible for subscribing to and routing coordinator-level events.
/// This component centralizes the event handling logic that was previously in `OnboardingInterviewCoordinator`.
@MainActor
final class CoordinatorEventRouter {
    private let ui: OnboardingUIState
    private let state: StateCoordinator
    private let phaseTransitionController: PhaseTransitionController
    private let toolRouter: ToolHandler
    private let eventBus: EventCoordinator

    // Domain services (extracted from this class for better separation of concerns)
    private let knowledgeCardWorkflow: KnowledgeCardWorkflowService
    private let onboardingPersistence: OnboardingPersistenceService

    // Track active extractions to avoid dossier spam during parallel doc ingestion
    // Only trigger dossier when first extraction starts (count goes 0→1)
    // Never reset mid-batch - only when ALL extractions complete
    private var activeExtractionCount: Int = 0
    private var hasDossierTriggeredThisBatch: Bool = false

    init(
        ui: OnboardingUIState,
        state: StateCoordinator,
        phaseTransitionController: PhaseTransitionController,
        toolRouter: ToolHandler,
        eventBus: EventCoordinator,
        knowledgeCardWorkflow: KnowledgeCardWorkflowService,
        onboardingPersistence: OnboardingPersistenceService
    ) {
        self.ui = ui
        self.state = state
        self.phaseTransitionController = phaseTransitionController
        self.toolRouter = toolRouter
        self.eventBus = eventBus
        self.knowledgeCardWorkflow = knowledgeCardWorkflow
        self.onboardingPersistence = onboardingPersistence
    }

    // MARK: - Pending Card Management
    func hasPendingKnowledgeCard() -> Bool {
        knowledgeCardWorkflow.hasPendingKnowledgeCard()
    }
    func subscribeToEvents(lifecycle: InterviewLifecycleController) {
        lifecycle.subscribeToEvents { [weak self] event in
            await self?.handleEvent(event)
        }
    }
    private func handleEvent(_ event: OnboardingEvent) async {
        // Log events - use debug level for high-frequency streaming events to reduce console noise
        // Use logDescription to avoid bloating logs with full JSON payloads
        switch event {
        case .streamingMessageUpdated, .llmReasoningSummaryDelta:
            Logger.debug("📊 CoordinatorEventRouter: \(event.logDescription)", category: .ai)
        default:
            Logger.info("📊 CoordinatorEventRouter: \(event.logDescription)", category: .ai)
        }
        switch event {
        case .objectiveStatusChanged(let id, _, let newStatus, _, _, _, _):
            Logger.debug("📊 CoordinatorEventRouter: objectiveStatusChanged received - id=\(id), newStatus=\(newStatus)", category: .ai)
            // Update UI state for views to track objective progress
            ui.objectiveStatuses[id] = newStatus
            if id == OnboardingObjectiveId.applicantProfile.rawValue && newStatus == "completed" {
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
            await onboardingPersistence.handleExperienceDefaultsGenerated(defaults)
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
                    Logger.info("🏁 CoordinatorEventRouter: Phase is COMPLETE - calling persistence service", category: .ai)
                    await onboardingPersistence.persistWritingCorpusOnComplete()
                    Logger.info("🏁 CoordinatorEventRouter: persistWritingCorpusOnComplete() finished, calling propagateExperienceDefaults()", category: .ai)
                    await onboardingPersistence.propagateExperienceDefaults()
                    Logger.info("🏁 CoordinatorEventRouter: propagateExperienceDefaults() finished", category: .ai)
                }
            } else {
                Logger.warning("📊 CoordinatorEventRouter: Could not convert phaseName '\(phaseName)' to InterviewPhase", category: .ai)
            }

        // MARK: - Knowledge Card Workflow Events (delegated to KnowledgeCardWorkflowService)
        case .knowledgeCardDoneButtonClicked(let itemId):
            await knowledgeCardWorkflow.handleDoneButtonClicked(itemId: itemId)

        case .knowledgeCardSubmissionPending(let card):
            knowledgeCardWorkflow.handleSubmissionPending(card: card)

        case .knowledgeCardAutoPersistRequested:
            await knowledgeCardWorkflow.handleAutoPersistRequested()

        case .planItemStatusChangeRequested(let itemId, let status):
            await knowledgeCardWorkflow.handlePlanItemStatusChange(itemId: itemId, status: status)

        // MARK: - Multi-Agent KC Generation Workflow
        case .generateCardsButtonClicked:
            await knowledgeCardWorkflow.handleGenerateCardsButtonClicked()

        case .cardAssignmentsProposed:
            // Event handled by UI for awareness; gating done in tool
            Logger.info("📋 Card assignments proposed - dispatch_kc_agents gated until user approval", category: .ai)

        // MARK: - KC Auto-Validation (from Agent Completion)
        case .kcAgentCompleted(let agentId, let cardId, let cardTitle):
            await knowledgeCardWorkflow.handleKCAgentCompleted(agentId: agentId, cardId: cardId, cardTitle: cardTitle)

        case .kcAgentFailed(let agentId, let cardId, let error):
            await knowledgeCardWorkflow.handleKCAgentFailed(agentId: agentId, cardId: cardId, error: error)

        case .kcAgentsDispatchCompleted(let successCount, let failureCount):
            await knowledgeCardWorkflow.handleKCAgentsDispatchCompleted(successCount: successCount, failureCount: failureCount)

        case .kcAutoValidationApproved:
            await knowledgeCardWorkflow.handleKCAutoValidationApproved()

        case .kcAutoValidationRejected(let reason):
            await knowledgeCardWorkflow.handleKCAutoValidationRejected(reason: reason)

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

    /// Present next KC validation after user completes one
    func presentNextKCValidationIfQueued() async {
        await knowledgeCardWorkflow.presentNextKCValidationIfQueued()
    }
}
