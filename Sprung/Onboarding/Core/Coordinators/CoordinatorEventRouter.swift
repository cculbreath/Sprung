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
        case .artifactRecordPersisted, .phaseTransitionApplied:
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
        case .phaseAdvanceRequested:
            break
        case .phaseAdvanceDismissed:
            break
        case .phaseAdvanceApproved, .phaseAdvanceDenied:
            break
        case .choicePromptRequested, .choicePromptCleared,
             .uploadRequestPresented, .uploadRequestCancelled,
             .validationPromptRequested, .validationPromptCleared,
             .applicantProfileIntakeRequested, .applicantProfileIntakeCleared,
             .toolPaneCardRestored,
             .timelineCardCreated, .timelineCardDeleted, .timelineCardsReordered,
             .artifactGetRequested, .artifactNewRequested, .artifactAdded, .artifactUpdated, .artifactDeleted,
             .artifactRecordProduced, .artifactRecordPersisted, .artifactRecordsReplaced,
             .knowledgeCardPersisted, .knowledgeCardsReplaced,
             .uploadCompleted,
             .objectiveStatusChanged, .objectiveStatusUpdateRequested,
             .stateSnapshot, .stateAllowedToolsUpdated,
             .llmUserMessageSent, .llmDeveloperMessageSent, .llmSentToolResponseMessage,
             .llmSendUserMessage, .llmSendDeveloperMessage, .llmToolResponseMessage, .llmStatus,
             .phaseTransitionRequested, .timelineCardUpdated:
            break
        case .phaseTransitionApplied(let phaseName, _):
            await phaseTransitionController.handlePhaseTransition(phaseName)
            if let phase = InterviewPhase(rawValue: phaseName) {
                ui.phase = phase
            }
        case .profileSummaryUpdateRequested, .profileSummaryDismissRequested,
             .sectionToggleRequested, .sectionToggleCleared,
             .artifactMetadataUpdated,
             .llmReasoningItemsForToolCalls,
             .pendingExtractionUpdated,
             .llmEnqueueUserMessage, .llmEnqueueToolResponse,
             .llmExecuteUserMessage, .llmExecuteToolResponse,
             .llmCancelRequested,
             .chatboxUserMessageAdded,
             .skeletonTimelineReplaced:
            break
        @unknown default:
            break
        }
    }
}
