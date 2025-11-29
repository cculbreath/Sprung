import Foundation
import SwiftyJSON
/// Router responsible for subscribing to and routing coordinator-level events.
/// This component centralizes the event handling logic that was previously in `OnboardingInterviewCoordinator`.
@MainActor
final class CoordinatorEventRouter {
    private let ui: OnboardingUIState
    private let state: StateCoordinator
    private let checkpointManager: CheckpointManager
    private let phaseTransitionController: PhaseTransitionController
    private let toolRouter: ToolHandler
    private let applicantProfileStore: ApplicantProfileStore
    private let eventBus: EventCoordinator
    // Weak reference to the parent coordinator to delegate specific actions back if needed
    // In a pure event architecture, this should be minimized, but useful for transition
    private weak var coordinator: OnboardingInterviewCoordinator?
    init(
        ui: OnboardingUIState,
        state: StateCoordinator,
        checkpointManager: CheckpointManager,
        phaseTransitionController: PhaseTransitionController,
        toolRouter: ToolHandler,
        applicantProfileStore: ApplicantProfileStore,
        eventBus: EventCoordinator,
        coordinator: OnboardingInterviewCoordinator
    ) {
        self.ui = ui
        self.state = state
        self.checkpointManager = checkpointManager
        self.phaseTransitionController = phaseTransitionController
        self.toolRouter = toolRouter
        self.applicantProfileStore = applicantProfileStore
        self.eventBus = eventBus
        self.coordinator = coordinator
    }
    func subscribeToEvents(lifecycle: InterviewLifecycleController) {
        lifecycle.subscribeToEvents { [weak self] event in
            await self?.handleEvent(event)
        }
    }
    private func handleEvent(_ event: OnboardingEvent) async {
        switch event {
        case .objectiveStatusChanged(let id, _, let newStatus, _, _, _, _):
            checkpointManager.scheduleCheckpoint()
            if id == "applicant_profile" && newStatus == "completed" {
                toolRouter.profileHandler.dismissProfileSummary()
            }
        case .timelineCardCreated, .timelineCardUpdated,
             .timelineCardDeleted, .timelineCardsReordered, .skeletonTimelineReplaced:
            let timeline = await state.artifacts.skeletonTimeline
            ui.updateTimeline(timeline)
            checkpointManager.scheduleCheckpoint()
        case .artifactRecordPersisted:
            checkpointManager.scheduleCheckpoint()
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
        // MARK: - Evidence & Draft Events (Phase 2)
        case .evidenceRequirementAdded(let req):
            ui.evidenceRequirements.append(req)
        case .evidenceRequirementUpdated(let req):
            if let index = ui.evidenceRequirements.firstIndex(where: { $0.id == req.id }) {
                ui.evidenceRequirements[index] = req
            }
        case .evidenceRequirementRemoved(let id):
            ui.evidenceRequirements.removeAll { $0.id == id }
        case .draftKnowledgeCardProduced(let draft):
            ui.drafts.append(draft)
        case .draftKnowledgeCardUpdated(let draft):
            if let index = ui.drafts.firstIndex(where: { $0.id == draft.id }) {
                ui.drafts[index] = draft
            }
        case .draftKnowledgeCardRemoved(let id):
            ui.drafts.removeAll { $0.id == id }
        case .applicantProfileStored:
            // Handled by ProfilePersistenceHandler
            break
        case .skeletonTimelineStored, .enabledSectionsUpdated:
            await checkpointManager.saveCheckpoint()
        case .checkpointRequested:
            await checkpointManager.saveCheckpoint()
        case .toolCallRequested:
            break
        case .toolCallCompleted:
            break
        case .objectiveStatusRequested(let id, let response):
            let status = await state.getObjectiveStatus(id)?.rawValue
            response(status)
        case .phaseTransitionApplied(let phaseName, _):
            checkpointManager.scheduleCheckpoint()
            await phaseTransitionController.handlePhaseTransition(phaseName)
            if let phase = InterviewPhase(rawValue: phaseName) {
                ui.phase = phase
            }
        // All other events are handled elsewhere or don't need handling here
        default:
            break
        }
    }
}
