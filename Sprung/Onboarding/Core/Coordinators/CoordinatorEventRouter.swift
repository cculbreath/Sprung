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

    func subscribeToEvents(lifecycle: InterviewLifecycleController) {
        lifecycle.subscribeToEvents { [weak self] event in
            await self?.handleEvent(event)
        }
    }
    private func handleEvent(_ event: OnboardingEvent) async {
        // Log events - use debug level for high-frequency streaming events to reduce console noise
        // Use logDescription to avoid bloating logs with full JSON payloads
        switch event {
        case .llm(.streamingMessageUpdated):
            Logger.debug("📊 CoordinatorEventRouter: \(event.logDescription)", category: .ai)
        default:
            Logger.info("📊 CoordinatorEventRouter: \(event.logDescription)", category: .ai)
        }
        switch event {
        case .objective(.statusChanged(let id, _, let newStatus, _, _, _, _)):
            Logger.debug("📊 CoordinatorEventRouter: objectiveStatusChanged received - id=\(id), newStatus=\(newStatus)", category: .ai)
            // Update UI state for views to track objective progress
            ui.objectiveStatuses[id] = newStatus
            if id == OnboardingObjectiveId.applicantProfileComplete.rawValue && newStatus == "completed" {
                Logger.info("📊 CoordinatorEventRouter: Dismissing profile summary for applicant_profile_complete completion", category: .ai)
                toolRouter.profileHandler.dismissProfileSummary()
            }
        case .timeline(.uiUpdateNeeded):
            // Timeline UI updates are now handled by UIStateUpdateHandler via topic-specific stream
            // This provides immediate updates without waiting in the congested streamAll() queue
            break
        case .processing(.stateChanged):
            break
        case .llm(.streamingMessageBegan), .llm(.streamingMessageUpdated), .llm(.streamingMessageFinalized):
            break
        case .processing(.waitingStateChanged):
            break
        case .processing(.errorOccurred(let error)):
            Logger.error("Interview error: \(error)", category: .ai)
            // Errors are now displayed via spinner status message, not popup alerts
        case .llm(.userMessageFailed(let messageId, let originalText, let error)):
            // Handle failed message: remove from transcript and prepare for input restoration
            ui.handleMessageFailure(messageId: messageId, originalText: originalText, error: error)
        case .state(.applicantProfileStored):
            // Handled by ProfilePersistenceHandler
            break
        case .state(.skeletonTimelineStored), .state(.enabledSectionsUpdated):
            break
        case .artifact(.experienceDefaultsGenerated(let defaults)):
            await onboardingPersistence.handleExperienceDefaultsGenerated(defaults)
        case .tool(.callRequested):
            break
        case .phase(.transitionApplied(let phaseName, _)):
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

        case .phase(.interviewCompleted):
            // Log completion - SGM is triggered via button on completion sheet, not automatically
            Logger.info("🌱 CoordinatorEventRouter: Interview complete - user can launch SGM from completion sheet", category: .ai)

        // MARK: - Card Generation Workflow
        case .artifact(.doneWithUploadsClicked):
            await knowledgeCardWorkflow.handleDoneWithUploadsClicked()

        case .artifact(.generateCardsButtonClicked):
            await knowledgeCardWorkflow.handleGenerateCardsButtonClicked()

        case .artifact(.mergeComplete):
            // Event handled by UI; user clicks Approve & Create to generate
            Logger.info("📋 Merge complete - awaiting user approval via Approve & Create button", category: .ai)

        // MARK: - Dossier Collection Trigger (Parallel-Safe)
        case .processing(.extractionStateChanged(let inProgress, _)):
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

        // MARK: - Document Collection UI
        case .state(.documentCollectionActiveChanged(let isActive)):
            // When document collection mode is activated, dismiss profile summary so DocumentCollectionView can show
            if isActive {
                toolRouter.profileHandler.dismissProfileSummary()
                Logger.info("📋 Profile summary dismissed for document collection mode", category: .ai)
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
        guard currentPhase == .phase2CareerStory else {
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
        await eventBus.publish(.llm(.executeCoordinatorMessage(payload: payload)))
        Logger.info("📋 Triggered dossier collection during extraction", category: .ai)
    }
}
