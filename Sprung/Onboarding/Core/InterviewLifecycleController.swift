import Foundation
import SwiftyJSON
import SwiftOpenAI
/// Manages interview lifecycle: start/end, orchestrator setup, session persistence, and event subscriptions.
/// Combines session management with orchestrator lifecycle.
@MainActor
final class InterviewLifecycleController {
    // MARK: - Dependencies
    private let state: StateCoordinator
    private let eventBus: EventCoordinator
    private let phaseRegistry: PhaseScriptRegistry
    private let chatboxHandler: ChatboxHandler
    private let toolExecutionCoordinator: ToolExecutionCoordinator
    private let toolRouter: ToolHandler
    private var llmFacade: LLMFacade?
    private let toolRegistry: ToolRegistry
    private let dataStore: InterviewDataStore

    // Session dependencies (merged from InterviewSessionCoordinator)
    private let phaseTransitionController: PhaseTransitionController
    private let dataPersistenceService: DataPersistenceService
    private let documentArtifactHandler: DocumentArtifactHandler
    private let documentArtifactMessenger: DocumentArtifactMessenger
    private let ui: OnboardingUIState
    private let sessionPersistenceHandler: SwiftDataSessionPersistenceHandler
    private let chatTranscriptStore: ChatTranscriptStore

    // MARK: - Lifecycle State
    private(set) var orchestrator: InterviewOrchestrator?
    private(set) var workflowEngine: ObjectiveWorkflowEngine?
    private(set) var transcriptPersistenceHandler: TranscriptPersistenceHandler?

    // Event subscription tracking
    private var eventSubscriptionTask: Task<Void, Never>?
    private var stateUpdateTasks: [Task<Void, Never>] = []

    // Callbacks
    private var subscribeToStateUpdates: (() -> Void)?

    // MARK: - Initialization
    init(
        state: StateCoordinator,
        eventBus: EventCoordinator,
        phaseRegistry: PhaseScriptRegistry,
        chatboxHandler: ChatboxHandler,
        toolExecutionCoordinator: ToolExecutionCoordinator,
        toolRouter: ToolHandler,
        llmFacade: LLMFacade?,
        toolRegistry: ToolRegistry,
        dataStore: InterviewDataStore,
        phaseTransitionController: PhaseTransitionController,
        dataPersistenceService: DataPersistenceService,
        documentArtifactHandler: DocumentArtifactHandler,
        documentArtifactMessenger: DocumentArtifactMessenger,
        ui: OnboardingUIState,
        sessionPersistenceHandler: SwiftDataSessionPersistenceHandler,
        chatTranscriptStore: ChatTranscriptStore
    ) {
        self.state = state
        self.eventBus = eventBus
        self.phaseRegistry = phaseRegistry
        self.chatboxHandler = chatboxHandler
        self.toolExecutionCoordinator = toolExecutionCoordinator
        self.toolRouter = toolRouter
        self.llmFacade = llmFacade
        self.toolRegistry = toolRegistry
        self.dataStore = dataStore
        self.phaseTransitionController = phaseTransitionController
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
        Logger.info("🚀 Starting fresh interview", category: .ai)
        await resetForFreshStart()
        _ = sessionPersistenceHandler.startSession(resumeExisting: false)
        await state.setPhase(.phase1VoiceContext)
        await phaseTransitionController.registerObjectivesForCurrentPhase()
        subscribeToStateUpdates?()
        await documentArtifactHandler.start()
        await documentArtifactMessenger.start()

        // Set model ID BEFORE starting interview (so first message uses correct model)
        let modelId = OnboardingModelConfig.currentModelId
        Logger.info("🎯 Setting interview model from settings: \(modelId)", category: .ai)
        await state.setModelId(modelId)

        let success = await startLLM(isResuming: false)
        if success {
            ui.isActive = await state.isActive
            Logger.info("🎛️ Session isActive synced: \(ui.isActive)", category: .ai)
        }
        return success
    }

    /// Resume from an existing persisted session
    private func resumeSession(_ session: OnboardingSession) async -> Bool {
        // Restore messages to chat transcript store
        await sessionPersistenceHandler.restoreSession(session, to: chatTranscriptStore)

        // Sync UI messages from restored chat transcript
        ui.messages = await chatTranscriptStore.getAllMessages()
        Logger.info("📥 Synced \(ui.messages.count) messages to UI", category: .ai)

        // Restore UI state
        let phase = InterviewPhase(rawValue: session.phase) ?? .phase1VoiceContext
        ui.phase = phase

        // Restore aggregated cards and excluded card IDs
        let restoredExcludedIds = sessionPersistenceHandler.getRestoredExcludedCardIds(session)
        ui.excludedCardIds = restoredExcludedIds

        let restoredCards = sessionPersistenceHandler.getRestoredAggregatedNarrativeCards(session)
        if !restoredCards.isEmpty {
            ui.aggregatedNarrativeCards = restoredCards
            ui.proposedAssignmentCount = restoredCards.count
            ui.identifiedGapCount = 0  // Gaps are no longer tracked in new model
            ui.cardAssignmentsReadyForApproval = true

            Logger.info("📥 Restored aggregated narrative cards: \(restoredCards.count) cards (excluding \(restoredExcludedIds.count) excluded)", category: .ai)
        }

        // Restore phase in state coordinator - registers objectives for ALL phases up to current
        // This ensures Phase 1/2 objectives are registered when resuming a Phase 3+ session
        await state.restorePhase(phase)

        // Restore objective statuses
        let objectiveStatuses = sessionPersistenceHandler.getRestoredObjectiveStatuses(session)
        for (objectiveId, status) in objectiveStatuses {
            await state.restoreObjectiveStatus(objectiveId: objectiveId, status: status)
        }

        // Restore artifacts to state coordinator
        await restoreArtifacts(from: session)

        // Restore streaming state (must be done after messages are restored)
        // This ensures tool_choice is set to .auto instead of .none for resumed sessions
        let hasMessages = !ui.messages.isEmpty
        await state.restoreStreamingState(hasMessages: hasMessages)

        // Restore timeline, profile, and sections
        await restoreTimelineAndProfile(from: session)

        // Restore UI states (document collection, timeline editor)
        await restoreUIStates(from: session)

        // Mark session as resumed
        _ = sessionPersistenceHandler.startSession(resumeExisting: true)

        subscribeToStateUpdates?()
        await documentArtifactHandler.start()
        await documentArtifactMessenger.start()

        // Re-publish tool permissions now that event subscriptions are active
        // (setPhase was called before subscriptions, so the event was missed)
        await state.publishAllowedToolsNow()

        // Set model ID BEFORE starting interview (so first message uses correct model)
        let modelId = OnboardingModelConfig.currentModelId
        Logger.info("🎯 Setting interview model from settings (resume): \(modelId)", category: .ai)
        await state.setModelId(modelId)

        // Start LLM with resume flag
        let success = await startLLM(isResuming: true)
        if success {
            ui.isActive = await state.isActive
            Logger.info("🎛️ Resumed session isActive synced: \(ui.isActive)", category: .ai)
        }

        Logger.info("✅ Session resumed: \(session.id), phase=\(phase.rawValue)", category: .ai)
        return success
    }

    /// Restore artifacts from persisted session to state coordinator
    private func restoreArtifacts(from session: OnboardingSession) async {
        let artifacts = sessionPersistenceHandler.getRestoredArtifacts(session)
        await state.restoreArtifacts(artifacts)
        Logger.info("📥 Restored \(artifacts.count) artifacts to state", category: .ai)
    }

    /// Restore timeline, profile, and enabled sections from persisted session
    private func restoreTimelineAndProfile(from session: OnboardingSession) async {
        // Restore skeleton timeline
        if let timeline = sessionPersistenceHandler.getRestoredSkeletonTimeline(session) {
            await state.restoreSkeletonTimeline(timeline)
            // Also sync to UI state for immediate display
            ui.updateTimeline(timeline)
            let cardCount = timeline["experiences"].array?.count ?? 0
            Logger.info("📥 Restored skeleton timeline (\(cardCount) cards)", category: .ai)
        }

        // Restore applicant profile
        if let profile = sessionPersistenceHandler.getRestoredApplicantProfile(session) {
            await state.restoreApplicantProfile(profile)
            Logger.info("📥 Restored applicant profile", category: .ai)
        }

        // Restore enabled sections
        let sections = sessionPersistenceHandler.getRestoredEnabledSections(session)
        if !sections.isEmpty {
            await state.restoreEnabledSections(sections)
            Logger.info("📥 Restored \(sections.count) enabled sections", category: .ai)
        }
    }

    /// Restore UI states (document collection, timeline editor) from persisted session
    private func restoreUIStates(from session: OnboardingSession) async {
        // Restore document collection active state
        let isDocCollectionActive = sessionPersistenceHandler.getRestoredDocumentCollectionActive(session)
        if isDocCollectionActive {
            ui.isDocumentCollectionActive = true
            // Also set the waiting state in SessionUIState for tool gating
            // Note: We don't call setDocumentCollectionActive to avoid re-emitting the event
            Logger.info("📥 Restored document collection active state", category: .ai)
        }

        // Restore timeline editor active state
        let isTimelineEditorActive = sessionPersistenceHandler.getRestoredTimelineEditorActive(session)
        if isTimelineEditorActive {
            ui.isTimelineEditorActive = true
            Logger.info("📥 Restored timeline editor active state", category: .ai)
        }
    }

    /// Internal method to start the LLM orchestrator and related infrastructure
    private func startLLM(isResuming: Bool) async -> Bool {
        Logger.info("🚀 Starting LLM orchestrator (resuming: \(isResuming))", category: .ai)

        // Verify we have LLMFacade configured
        guard let facade = llmFacade else {
            await state.setActiveState(false)
            return false
        }

        // Set interview as active
        await state.setActiveState(true)

        // Apply user settings from AppStorage
        let flexProcessingEnabled = UserDefaults.standard.bool(forKey: "onboardingInterviewFlexProcessing")
        // Default to true if key doesn't exist (first launch)
        let flexDefault = UserDefaults.standard.object(forKey: "onboardingInterviewFlexProcessing") == nil
        await state.setUseFlexProcessing(flexDefault ? true : flexProcessingEnabled)
        let reasoningEffort = UserDefaults.standard.string(forKey: "onboardingInterviewReasoningEffort") ?? "medium"
        await state.setDefaultReasoningEffort(reasoningEffort)
        Logger.info("⚙️ Applied settings: flexProcessing=\(flexDefault ? true : flexProcessingEnabled), reasoning=\(reasoningEffort)", category: .ai)

        // Start event subscriptions BEFORE orchestrator sends initial message
        // StateCoordinator must be listening for .llmEnqueueUserMessage events
        // to process the queue and emit .llmExecuteUserMessage for LLMMessenger
        await state.startEventSubscriptions()
        await chatboxHandler.startEventSubscriptions()
        await toolExecutionCoordinator.startEventSubscriptions()
        await toolRouter.startEventSubscriptions()

        // Build orchestrator
        let phase = await state.phase
        let baseDeveloperMessage = phaseRegistry.buildSystemPrompt(for: phase)
        let orchestrator = makeOrchestrator(llmFacade: facade, baseDeveloperMessage: baseDeveloperMessage)
        self.orchestrator = orchestrator

        // Publish phase transition BEFORE orchestrator sends initial message
        // This ensures the phase intro (with toolChoice=agent_ready) is queued
        // and can be bundled with the initial "I'm ready to begin" user message
        if !isResuming {
            await eventBus.publish(.phaseTransitionApplied(phase: phase.rawValue, timestamp: Date()))
        }

        // Initialize orchestrator with resume flag
        // Now safe to send initial message - StateCoordinator is already subscribed
        // and phase intro is already queued for bundling
        do {
            try await orchestrator.startInterview(isResuming: isResuming)
        } catch {
            Logger.error("Failed to start orchestrator: \(error)", category: .ai)
            await state.setActiveState(false)
            return false
        }

        // NOW publish allowed tools - LLMMessenger is already subscribed
        await state.publishAllowedToolsNow()

        // Start workflow engine
        let engine = ObjectiveWorkflowEngine(
            eventBus: eventBus,
            phaseRegistry: phaseRegistry,
            state: state
        )
        workflowEngine = engine
        await engine.start()

        // Start transcript persistence handler
        let transcriptHandler = TranscriptPersistenceHandler(
            eventBus: eventBus,
            dataStore: dataStore
        )
        transcriptPersistenceHandler = transcriptHandler
        await transcriptHandler.start()

        return true
    }

    private func resetForFreshStart() async {
        await state.reset()
        clearArtifacts()
        await resetStore()
    }

    // MARK: - Data Persistence

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
    // MARK: - Event Subscriptions
    func subscribeToEvents(_ handler: @escaping (OnboardingEvent) async -> Void) {
        // Cancel any existing subscription
        eventSubscriptionTask?.cancel()
        // Subscribe to all events
        eventSubscriptionTask = Task { [weak self] in
            guard let self else { return }
            for await event in await eventBus.streamAll() {
                await handler(event)
            }
        }
    }
    func subscribeToStateUpdates(_ handlers: StateUpdateHandlers) {
        stateUpdateTasks.forEach { $0.cancel() }
        stateUpdateTasks.removeAll()
        let processingTask = Task { [weak self] in
            guard let self else { return }
            for await event in await self.eventBus.stream(topic: .processing) {
                if Task.isCancelled { break }
                await handlers.handleProcessingEvent(event)
            }
        }
        stateUpdateTasks.append(processingTask)
        let artifactTask = Task { [weak self] in
            guard let self else { return }
            for await event in await self.eventBus.stream(topic: .artifact) {
                if Task.isCancelled { break }
                await handlers.handleArtifactEvent(event)
            }
        }
        stateUpdateTasks.append(artifactTask)
        let llmTask = Task { [weak self] in
            guard let self else { return }
            for await event in await self.eventBus.stream(topic: .llm) {
                if Task.isCancelled { break }
                await handlers.handleLLMEvent(event)
            }
        }
        stateUpdateTasks.append(llmTask)
        let stateTask = Task { [weak self] in
            guard let self else { return }
            for await event in await self.eventBus.stream(topic: .state) {
                if Task.isCancelled { break }
                await handlers.handleStateEvent(event)
            }
        }
        stateUpdateTasks.append(stateTask)
        // Timeline topic - separate stream for immediate UI updates
        // This avoids the congested streamAll() queue
        let timelineTask = Task { [weak self] in
            guard let self else { return }
            for await event in await self.eventBus.stream(topic: .timeline) {
                if Task.isCancelled { break }
                await handlers.handleTimelineEvent(event)
            }
        }
        stateUpdateTasks.append(timelineTask)
        // Phase topic - for interview completion handling
        let phaseTask = Task { [weak self] in
            guard let self else { return }
            for await event in await self.eventBus.stream(topic: .phase) {
                if Task.isCancelled { break }
                await handlers.handlePhaseEvent(event)
            }
        }
        stateUpdateTasks.append(phaseTask)
        Task {
            await handlers.performInitialSync()
        }
    }
    // MARK: - Factory Methods
    private func makeOrchestrator(
        llmFacade: LLMFacade,
        baseDeveloperMessage: String
    ) -> InterviewOrchestrator {
        return InterviewOrchestrator(
            llmFacade: llmFacade,
            baseDeveloperMessage: baseDeveloperMessage,
            eventBus: eventBus,
            toolRegistry: toolRegistry,
            state: state
        )
    }
}
// MARK: - State Update Handlers Protocol
struct StateUpdateHandlers {
    let handleProcessingEvent: (OnboardingEvent) async -> Void
    let handleArtifactEvent: (OnboardingEvent) async -> Void
    let handleLLMEvent: (OnboardingEvent) async -> Void
    let handleStateEvent: (OnboardingEvent) async -> Void
    let handleTimelineEvent: (OnboardingEvent) async -> Void
    let handlePhaseEvent: (OnboardingEvent) async -> Void
    let performInitialSync: () async -> Void
}
