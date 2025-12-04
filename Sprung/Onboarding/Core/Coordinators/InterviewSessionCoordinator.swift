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
    private let sessionPersistenceHandler: SwiftDataSessionPersistenceHandler
    private let chatTranscriptStore: ChatTranscriptStore
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
        ui: OnboardingUIState,
        sessionPersistenceHandler: SwiftDataSessionPersistenceHandler,
        chatTranscriptStore: ChatTranscriptStore
    ) {
        self.lifecycleController = lifecycleController
        self.phaseTransitionController = phaseTransitionController
        self.state = state
        self.dataPersistenceService = dataPersistenceService
        self.documentArtifactHandler = documentArtifactHandler
        self.documentArtifactMessenger = documentArtifactMessenger
        self.ui = ui
        self.sessionPersistenceHandler = sessionPersistenceHandler
        self.chatTranscriptStore = chatTranscriptStore
    }
    // MARK: - Configuration
    /// Set the callback for subscribing to state updates after interview starts.
    func setStateUpdateSubscriber(_ callback: @escaping () -> Void) {
        self.subscribeToStateUpdates = callback
    }
    // MARK: - Interview Lifecycle
    /// Start a new interview or resume an existing one.
    /// - Parameter resumeExisting: If true, attempts to resume from persisted session.
    /// - Returns: True if interview started successfully
    func startInterview(resumeExisting: Bool = false) async -> Bool {
        // Start session persistence handler (listens to events)
        sessionPersistenceHandler.start()

        // Check for existing session to resume
        if resumeExisting, let existingSession = sessionPersistenceHandler.getActiveSession() {
            Logger.info("🔄 Resuming existing interview session: \(existingSession.id)", category: .ai)
            return await resumeSession(existingSession)
        }

        // Start fresh interview
        Logger.info("🚀 Starting fresh interview (session coordinator)", category: .ai)
        await resetForFreshStart()
        _ = sessionPersistenceHandler.startSession(resumeExisting: false)
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

    /// Resume from an existing persisted session
    private func resumeSession(_ session: OnboardingSession) async -> Bool {
        // Restore messages to chat transcript
        await sessionPersistenceHandler.restoreSession(session, to: chatTranscriptStore)

        // Restore UI state
        let phase = InterviewPhase(rawValue: session.phase) ?? .phase1CoreFacts
        ui.phase = phase
        ui.knowledgeCardPlan = sessionPersistenceHandler.getRestoredPlanItems(session)

        // Set phase in state coordinator
        await state.setPhase(phase)
        await phaseTransitionController.registerObjectivesForCurrentPhase()

        // Restore objective statuses
        let objectiveStatuses = sessionPersistenceHandler.getRestoredObjectiveStatuses(session)
        for (objectiveId, status) in objectiveStatuses {
            await state.restoreObjectiveStatus(objectiveId: objectiveId, status: status)
        }

        // Mark session as resumed
        _ = sessionPersistenceHandler.startSession(resumeExisting: true)

        subscribeToStateUpdates?()
        await documentArtifactHandler.start()
        await documentArtifactMessenger.start()

        // Start LLM with resume flag
        let success = await lifecycleController.startInterview(isResuming: true)
        if success {
            ui.isActive = await state.isActive
            Logger.info("🎛️ Resumed session isActive synced: \(ui.isActive)", category: .ai)
        }

        if let orchestrator = lifecycleController.orchestrator {
            let cfg = ModelProvider.forTask(.orchestrator)
            await orchestrator.setModelId(ui.preferences.preferredModelId ?? cfg.id)
        }

        Logger.info("✅ Session resumed: \(session.id), phase=\(phase.rawValue)", category: .ai)
        return true
    }
    /// End the current interview session.
    func endInterview() async {
        sessionPersistenceHandler.endSession(markComplete: false)
        sessionPersistenceHandler.stop()
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
