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
    private let checkpointManager: CheckpointManager

    // MARK: - Initialization
    init(
        ui: OnboardingUIState,
        state: StateCoordinator,
        wizardTracker: WizardProgressTracker,
        checkpointManager: CheckpointManager
    ) {
        self.ui = ui
        self.state = state
        self.wizardTracker = wizardTracker
        self.checkpointManager = checkpointManager
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
        default:
            break
        }
    }

    // MARK: - Artifact Events

    func handleArtifactEvent(_ event: OnboardingEvent) async {
        switch event {
        case .artifactNewRequested, .artifactAdded, .artifactUpdated, .artifactDeleted,
             .artifactRecordProduced, .artifactRecordPersisted, .artifactRecordsReplaced,
             .knowledgeCardPersisted, .knowledgeCardsReplaced:
            await syncWizardProgressFromState()
        default:
            break
        }
    }

    // MARK: - LLM Events

    func handleLLMEvent(_ event: OnboardingEvent) async {
        switch event {
        case .llmStatus:
            break
        case .chatboxUserMessageAdded:
            ui.messages = await state.messages
            checkpointManager.scheduleCheckpoint()
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
            checkpointManager.scheduleCheckpoint()
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
        case .phaseAdvanceRequested:
            break
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
        ui.messages = await state.messages
        Logger.info("📥 Initial state sync: loaded \(ui.messages.count) messages", category: .ai)
    }
}
