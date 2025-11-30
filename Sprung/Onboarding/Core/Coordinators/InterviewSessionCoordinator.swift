import Foundation
import SwiftyJSON
/// Manages interview session lifecycle: start/end and data persistence.
/// Consolidates session-related operations from OnboardingInterviewCoordinator.
@MainActor
final class InterviewSessionCoordinator {
    // MARK: - Dependencies
    private let lifecycleController: InterviewLifecycleController
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
        phaseTransitionController: PhaseTransitionController,
        state: StateCoordinator,
        dataPersistenceService: DataPersistenceService,
        documentArtifactHandler: DocumentArtifactHandler,
        documentArtifactMessenger: DocumentArtifactMessenger,
        ui: OnboardingUIState
    ) {
        self.lifecycleController = lifecycleController
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
    /// Start a new interview.
    /// - Parameter resumeExisting: Ignored; always starts fresh.
    /// - Returns: True if interview started successfully
    func startInterview(resumeExisting: Bool = false) async -> Bool {
        Logger.info("🚀 Starting fresh interview (session coordinator)", category: .ai)
        await resetForFreshStart()
        await state.setPhase(.phase1CoreFacts)
        await phaseTransitionController.registerObjectivesForCurrentPhase()
        subscribeToStateUpdates?()
        await documentArtifactHandler.start()
        await documentArtifactMessenger.start()
        let success = await lifecycleController.startInterview(isResuming: false)
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
        clearArtifacts()
        await resetStore()
    }
}
