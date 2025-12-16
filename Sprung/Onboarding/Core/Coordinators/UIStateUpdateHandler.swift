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
        case .processingStateChanged(let isProcessing, let statusMessage):
            ui.updateProcessing(isProcessing: isProcessing, statusMessage: statusMessage)
            Logger.info("🎨 UI Update: Chat glow/spinner \(isProcessing ? "ACTIVATED ✨" : "DEACTIVATED") - isProcessing=\(isProcessing), status: \(ui.currentStatusMessage ?? "none")", category: .ai)
            await syncWizardProgressFromState()
        case .streamingStatusUpdated(_, let statusMessage):
            if let statusMessage = statusMessage {
                ui.currentStatusMessage = statusMessage
            }
        case .waitingStateChanged(_, let statusMessage):
            if let statusMessage = statusMessage {
                ui.currentStatusMessage = statusMessage
            }
        case .toolCallRequested(_, let statusMessage):
            if let statusMessage = statusMessage {
                ui.currentStatusMessage = statusMessage
            }
        case .toolCallCompleted(_, _, let statusMessage):
            if let statusMessage = statusMessage {
                ui.currentStatusMessage = statusMessage
            }
        case .batchUploadStarted(let expectedCount):
            ui.hasBatchUploadInProgress = true
            Logger.info("📦 Batch upload started: \(expectedCount) document(s) expected, blocking validation prompts", category: .ai)
            // Prevent the LLM from thrashing retrieval while the user is still selecting/uploads are still in progress.
            // The upload UI already provides context; retrieval during this window tends to produce spammy tool calls.
            await state.excludeTool(OnboardingToolName.getContextPack.rawValue)
        case .batchUploadCompleted:
            ui.hasBatchUploadInProgress = false
            Logger.info("📦 Batch upload completed, validation prompts can proceed", category: .ai)
            // Restore normal retrieval tools after uploads are complete.
            await state.includeTool(OnboardingToolName.getContextPack.rawValue)
        case .extractionStateChanged(let inProgress, let statusMessage):
            ui.updateExtraction(inProgress: inProgress, statusMessage: statusMessage)
            Logger.info("📄 Extraction state: \(inProgress ? "started" : "completed") - \(statusMessage ?? "no message")", category: .ai)

        // MARK: KC Agent Dispatch Events (categorized as .processing)
        case .kcAgentsDispatchStarted(let count, _):
            ui.isGeneratingCards = true
            Logger.info("🤖 UI: KC agents dispatch started (\(count) agents)", category: .ai)

        case .kcAgentsDispatchCompleted(let successCount, let failureCount):
            ui.isGeneratingCards = false
            Logger.info("✅ UI: KC agents dispatch completed (\(successCount) success, \(failureCount) failed)", category: .ai)

        default:
            break
        }
    }
    // MARK: - Artifact Events
    func handleArtifactEvent(_ event: OnboardingEvent) async {
        switch event {
        case .artifactNewRequested, .artifactAdded, .artifactUpdated, .artifactDeleted,
             .artifactRecordProduced, .artifactRecordsReplaced,
             .knowledgeCardPersisted, .knowledgeCardsReplaced:
            await syncArtifactRecordsFromState()
            await syncWizardProgressFromState()

        // MARK: Multi-Agent Workflow State (categorized as .artifact)
        case .cardAssignmentsProposed(let assignmentCount, let gapCount):
            ui.cardAssignmentsReadyForApproval = true
            ui.proposedAssignmentCount = assignmentCount
            ui.identifiedGapCount = gapCount
            Logger.info("📋 UI: Card assignments ready for approval (\(assignmentCount) assignments, \(gapCount) gaps)", category: .ai)

        case .generateCardsButtonClicked:
            ui.cardAssignmentsReadyForApproval = false
            ui.isGeneratingCards = true
            Logger.info("🚀 UI: Generate Cards initiated - starting KC agents", category: .ai)

        default:
            break
        }
    }

    // MARK: - Artifact Records Sync
    private func syncArtifactRecordsFromState() async {
        let records = await state.artifactRecords
        ui.artifactRecords = records
        Logger.debug("📦 UI artifact records synced: \(records.count) record(s)", category: .ai)
    }
    // MARK: - LLM Events
    func handleLLMEvent(_ event: OnboardingEvent) async {
        switch event {
        case .llmStatus:
            break
        case .chatboxUserMessageAdded:
            ui.messages = await state.messages
        case .streamingMessageBegan(_, _, _, let statusMessage):
            ui.messages = await state.messages
            if let statusMessage = statusMessage {
                ui.currentStatusMessage = statusMessage
            }
        case .streamingMessageUpdated(_, _, let statusMessage):
            ui.messages = await state.messages
            if let statusMessage = statusMessage {
                ui.currentStatusMessage = statusMessage
            }
        case .streamingMessageFinalized(_, _, _, let statusMessage):
            ui.messages = await state.messages
            ui.currentStatusMessage = statusMessage ?? nil
        case .llmUserMessageSent:
            ui.messages = await state.messages
        default:
            break
        }
    }
    // MARK: - State Sync Events
    func handleStateSyncEvent(_ event: OnboardingEvent) async {
        switch event {
        case .stateSnapshot, .stateAllowedToolsUpdated:
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
        case .timelineUIUpdateNeeded(let timeline):
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
        case .phaseTransitionApplied(let phase, _):
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
        await syncArtifactRecordsFromState()
        ui.messages = await state.messages
        Logger.info("📥 Initial state sync: loaded \(ui.messages.count) messages, \(ui.artifactRecords.count) artifacts", category: .ai)
    }
}
