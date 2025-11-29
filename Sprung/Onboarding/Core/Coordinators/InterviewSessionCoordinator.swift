import Foundation
import SwiftyJSON

/// Manages interview session lifecycle: start/end/restore and data persistence.
/// Consolidates session-related operations from OnboardingInterviewCoordinator.
@MainActor
final class InterviewSessionCoordinator {
    // MARK: - Dependencies
    private let lifecycleController: InterviewLifecycleController
    private let checkpointManager: CheckpointManager
    private let phaseTransitionController: PhaseTransitionController
    private let state: StateCoordinator
    private let dataPersistenceService: DataPersistenceService
    private let documentArtifactHandler: DocumentArtifactHandler
    private let documentArtifactMessenger: DocumentArtifactMessenger
    private let ui: OnboardingUIState

    // MARK: - Callbacks
    private var subscribeToStateUpdates: (() -> Void)?

    // MARK: - Initialization
    init(
        lifecycleController: InterviewLifecycleController,
        checkpointManager: CheckpointManager,
        phaseTransitionController: PhaseTransitionController,
        state: StateCoordinator,
        dataPersistenceService: DataPersistenceService,
        documentArtifactHandler: DocumentArtifactHandler,
        documentArtifactMessenger: DocumentArtifactMessenger,
        ui: OnboardingUIState
    ) {
        self.lifecycleController = lifecycleController
        self.checkpointManager = checkpointManager
        self.phaseTransitionController = phaseTransitionController
        self.state = state
        self.dataPersistenceService = dataPersistenceService
        self.documentArtifactHandler = documentArtifactHandler
        self.documentArtifactMessenger = documentArtifactMessenger
        self.ui = ui
    }

    // MARK: - Configuration

    /// Set the callback for subscribing to state updates after interview starts.
    func setStateUpdateSubscriber(_ callback: @escaping () -> Void) {
        self.subscribeToStateUpdates = callback
    }

    // MARK: - Interview Lifecycle

    /// Start a new interview or resume an existing one.
    /// - Parameter resumeExisting: Whether to attempt restoring from a checkpoint
    /// - Returns: True if interview started successfully
    func startInterview(resumeExisting: Bool = false) async -> Bool {
        Logger.info("🚀 Starting interview (session coordinator, resume: \(resumeExisting))", category: .ai)

        var isActuallyResuming = false

        if resumeExisting {
            await loadPersistedArtifacts()
            let didRestore = await checkpointManager.restoreFromCheckpointIfAvailable()
            if didRestore {
                isActuallyResuming = true
                let hasPreviousResponseId = await state.getPreviousResponseId() != nil
                if hasPreviousResponseId {
                    Logger.info("✅ Found previousResponseId - will resume conversation context", category: .ai)
                } else {
                    Logger.info("⚠️ No previousResponseId - will start fresh conversation", category: .ai)
                    isActuallyResuming = false
                }
            } else {
                await resetForFreshStart()
            }
        } else {
            await resetForFreshStart()
        }

        if !isActuallyResuming {
            await state.setPhase(.phase1CoreFacts)
        }

        await phaseTransitionController.registerObjectivesForCurrentPhase()
        subscribeToStateUpdates?()
        await documentArtifactHandler.start()
        await documentArtifactMessenger.start()

        let success = await lifecycleController.startInterview(isResuming: isActuallyResuming)

        if success {
            ui.isActive = await state.isActive
            Logger.info("🎛️ Session isActive synced: \(ui.isActive)", category: .ai)
        }

        if let orchestrator = lifecycleController.orchestrator {
            let cfg = ModelProvider.forTask(.orchestrator)
            await orchestrator.setModelId(ui.preferences.preferredModelId ?? cfg.id)
        }

        return true
    }

    /// End the current interview session.
    func endInterview() async {
        await lifecycleController.endInterview()
        ui.isActive = await state.isActive
        Logger.info("🎛️ Session isActive synced: \(ui.isActive)", category: .ai)
    }

    /// Restore from a specific checkpoint.
    /// - Parameter checkpoint: The checkpoint to restore from
    func restoreFromCheckpoint(_ checkpoint: OnboardingCheckpoint) async {
        await loadPersistedArtifacts()
        let didRestore = await checkpointManager.restoreFromSpecificCheckpoint(checkpoint)
        if didRestore {
            Logger.info("✅ Restored from specific checkpoint", category: .ai)
        } else {
            Logger.warning("⚠️ Failed to restore from specific checkpoint", category: .ai)
        }
    }

    // MARK: - Data Persistence

    /// Load artifacts persisted from a previous session.
    func loadPersistedArtifacts() async {
        await dataPersistenceService.loadPersistedArtifacts()
    }

    /// Clear all artifacts from the current session.
    func clearArtifacts() {
        Task {
            await dataPersistenceService.clearArtifacts()
        }
    }

    /// Reset the data store to initial state.
    func resetStore() async {
        await dataPersistenceService.resetStore()
    }

    // MARK: - Private Helpers

    private func resetForFreshStart() async {
        await state.reset()
        checkpointManager.clearCheckpoints()
        clearArtifacts()
        await resetStore()
    }
}
