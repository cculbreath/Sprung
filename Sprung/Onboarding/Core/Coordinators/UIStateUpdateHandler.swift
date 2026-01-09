import Foundation
import SwiftyJSON
/// Handles UI state updates in response to events.
/// Consolidates event handlers that update @Observable UI state.
@MainActor
final class UIStateUpdateHandler {
    // MARK: - Dependencies
    private let ui: OnboardingUIState
    private let state: StateCoordinator
    private let wizardTracker: WizardProgressTracker
    // MARK: - Initialization
    init(
        ui: OnboardingUIState,
        state: StateCoordinator,
        wizardTracker: WizardProgressTracker
    ) {
        self.ui = ui
        self.state = state
        self.wizardTracker = wizardTracker
    }
    // MARK: - State Update Handlers
    /// Build handlers for lifecycle controller subscription.
    func buildStateUpdateHandlers() -> StateUpdateHandlers {
        StateUpdateHandlers(
            handleProcessingEvent: { [weak self] event in
                await self?.handleProcessingEvent(event)
            },
            handleArtifactEvent: { [weak self] event in
                await self?.handleArtifactEvent(event)
            },
            handleLLMEvent: { [weak self] event in
                await self?.handleLLMEvent(event)
            },
            handleStateEvent: { [weak self] event in
                await self?.handleStateSyncEvent(event)
            },
            handleTimelineEvent: { [weak self] event in
                await self?.handleTimelineEvent(event)
            },
            handlePhaseEvent: { [weak self] event in
                await self?.handlePhaseEvent(event)
            },
            performInitialSync: { [weak self] in
                await self?.initialStateSync()
            }
        )
    }
    // MARK: - Processing Events
    func handleProcessingEvent(_ event: OnboardingEvent) async {
        switch event {
        case .processing(.stateChanged(let isProcessing, let statusMessage)):
            ui.updateProcessing(isProcessing: isProcessing, statusMessage: statusMessage)
            Logger.info("🎨 UI Update: Chat glow/spinner \(isProcessing ? "ACTIVATED ✨" : "DEACTIVATED") - isProcessing=\(isProcessing), status: \(ui.currentStatusMessage ?? "none")", category: .ai)
            await syncWizardProgressFromState()
        case .processing(.waitingStateChanged(_, let statusMessage)):
            if let statusMessage = statusMessage {
                ui.currentStatusMessage = statusMessage
            }
        case .tool(.callRequested(_, let statusMessage)):
            if let statusMessage = statusMessage {
                ui.currentStatusMessage = statusMessage
            }
        case .processing(.batchUploadStarted(let expectedCount)):
            ui.hasBatchUploadInProgress = true
            Logger.info("📦 Batch upload started: \(expectedCount) document(s) expected", category: .ai)
        case .processing(.batchUploadCompleted):
            ui.hasBatchUploadInProgress = false
            Logger.info("📦 Batch upload completed", category: .ai)
        case .processing(.extractionStateChanged(let inProgress, let statusMessage)):
            ui.updateExtraction(inProgress: inProgress, statusMessage: statusMessage)
            Logger.info("📄 Extraction state: \(inProgress ? "started" : "completed") - \(statusMessage ?? "no message")", category: .ai)

        default:
            break
        }
    }
    // MARK: - Artifact Events
    func handleArtifactEvent(_ event: OnboardingEvent) async {
        switch event {
        case .artifact(.recordProduced), .artifact(.knowledgeCardPersisted):
            // Typed artifacts are accessed via coordinator.sessionArtifacts (no UI sync needed)
            await syncWizardProgressFromState()

        // MARK: Multi-Agent Workflow State (categorized as .artifact)
        case .artifact(.mergeComplete(let cardCount, let gapCount)):
            ui.cardAssignmentsReadyForApproval = true
            ui.proposedAssignmentCount = cardCount
            ui.identifiedGapCount = gapCount
            Logger.info("📋 UI: Merge complete - \(cardCount) cards ready for approval (\(gapCount) gaps)", category: .ai)

        case .artifact(.generateCardsButtonClicked):
            ui.cardAssignmentsReadyForApproval = false
            ui.isGeneratingCards = true
            Logger.info("🚀 UI: Generate Cards initiated", category: .ai)

        default:
            break
        }
    }

    // MARK: - LLM Events
    func handleLLMEvent(_ event: OnboardingEvent) async {
        switch event {
        case .llm(.status):
            break
        case .llm(.chatboxUserMessageAdded):
            ui.messages = await state.messages
        case .llm(.streamingMessageBegan(_, _, let statusMessage)):
            ui.messages = await state.messages
            if let statusMessage = statusMessage {
                ui.currentStatusMessage = statusMessage
            }
        case .llm(.streamingMessageUpdated(_, _, let statusMessage)):
            ui.messages = await state.messages
            if let statusMessage = statusMessage {
                ui.currentStatusMessage = statusMessage
            }
        case .llm(.streamingMessageFinalized(_, _, _, let statusMessage)):
            ui.messages = await state.messages
            ui.currentStatusMessage = statusMessage ?? nil
        case .llm(.userMessageSent):
            ui.messages = await state.messages
        default:
            break
        }
    }
    // MARK: - State Sync Events
    func handleStateSyncEvent(_ event: OnboardingEvent) async {
        switch event {
        case .state(.allowedToolsUpdated):
            await syncWizardProgressFromState()
        default:
            break
        }
    }

    // MARK: - Timeline Events
    /// Handle timeline events directly to avoid queuing delays from streamAll()
    /// This provides immediate UI updates when timeline cards are created/updated/deleted
    func handleTimelineEvent(_ event: OnboardingEvent) async {
        switch event {
        case .timeline(.uiUpdateNeeded(let timeline)):
            let cardCount = timeline["experiences"].array?.count ?? 0
            Logger.info("📊 UIStateUpdateHandler: Received timelineUIUpdateNeeded with \(cardCount) cards", category: .ai)
            ui.updateTimeline(timeline)
            Logger.info("📊 UIStateUpdateHandler: ui.updateTimeline called, new token=\(ui.timelineUIChangeToken)", category: .ai)
        default:
            break
        }
    }

    // MARK: - Phase Events
    /// Handle phase transition events - closes window when interview completes
    func handlePhaseEvent(_ event: OnboardingEvent) async {
        switch event {
        case .phase(.transitionApplied(let phase, _)):
            if phase == InterviewPhase.phase4StrategicSynthesis.rawValue {
                let customFields = await state.getCustomFieldDefinitions()
                ui.shouldGenerateTitleSets = customFields.contains { $0.key.lowercased() == "custom.jobtitles" }
                Logger.info(
                    "🏷️ Phase 4 entry: title set curation \(ui.shouldGenerateTitleSets ? "enabled" : "disabled")",
                    category: .ai
                )
            }
            if phase == InterviewPhase.complete.rawValue {
                Logger.info("🏁 Interview complete - triggering window close", category: .ai)
                ui.interviewJustCompleted = true
            }
        default:
            break
        }
    }
    // MARK: - Wizard Progress Synchronization
    func syncWizardProgressFromState() async {
        let step = await state.currentWizardStep
        let completed = await state.completedWizardSteps
        ui.updateWizardProgress(step: step, completed: completed)
        // Sync WizardTracker for View binding
        if let trackerStep = OnboardingWizardStep(rawValue: step.rawValue) {
            let trackerCompleted = Set(completed.compactMap { OnboardingWizardStep(rawValue: $0.rawValue) })
            await MainActor.run {
                wizardTracker.synchronize(currentStep: trackerStep, completedSteps: trackerCompleted)
            }
        }
    }
    // MARK: - Initial State Sync
    func initialStateSync() async {
        await syncWizardProgressFromState()
        // Typed artifacts are accessed via coordinator.sessionArtifacts (no UI sync needed)
        ui.messages = await state.messages
        Logger.info("📥 Initial state sync: loaded \(ui.messages.count) messages", category: .ai)
    }
}
