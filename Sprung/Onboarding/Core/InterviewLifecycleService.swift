import Foundation
import SwiftyJSON
import SwiftOpenAI
/// Manages interview lifecycle: start/end, orchestrator setup, session persistence, and event subscriptions.
/// Combines session management with orchestrator lifecycle.
@MainActor
final class InterviewLifecycleService {
    // MARK: - Dependencies
    private let state: StateCoordinator
    private let eventBus: EventBus
    private let phaseRegistry: PhaseScriptRegistry
    private let toolExecutionCoordinator: ToolExecutionCoordinator
    private let toolRouter: ToolInteractionRouter
    private var llmFacade: LLMFacade?
    private let toolRegistry: ToolRegistry
    private let dataStore: InterviewDataStore

    // Session dependencies (merged from InterviewSessionCoordinator)
    private let phaseTransitionController: PhaseTransitionService
    private let dataPersistenceService: DataPersistenceService
    private let documentArtifactHandler: DocumentArtifactHandler
    private let documentArtifactMessenger: DocumentArtifactMessenger
    private let ui: OnboardingUIState
    private let sessionPersistenceHandler: SessionPersistenceService
    private let knowledgeCardStore: KnowledgeCardStore
    private let skillStore: SkillStore
    private let todoStore: InterviewTodoStore
    private let budgetPauseGate: BudgetPauseGate

    // MARK: - Lifecycle State
    private(set) var orchestrator: InterviewOrchestrator?
    private(set) var workflowEngine: ObjectiveWorkflowEngine?
    private(set) var transcriptPersistenceHandler: TranscriptPersistenceService?

    // Event subscription tracking
    private var eventSubscriptionTask: Task<Void, Never>?
    private var stateUpdateTasks: [Task<Void, Never>] = []

    // Tape recording (dev-only; off by default)
    static let recordingEnabledKey = "onboardingTapeRecordingEnabled"
    private var tapeRecorder: SessionTapeRecorder?
    /// Set by the replay controller so a fresh interview started FOR a restore does
    /// not install the recording decorator over the replay service (which would
    /// stack Recording-over-Replay and corrupt the go-live swap). The restored
    /// session is not re-recorded.
    var suppressTapeRecording = false
    /// The real, un-decorated Anthropic service, saved while a recording decorator
    /// is installed so it can be restored when recording stops.
    private var savedAnthropicService: AnthropicService?

    // Callbacks
    private var subscribeToStateUpdates: (() -> Void)?

    // MARK: - Initialization
    init(
        state: StateCoordinator,
        eventBus: EventBus,
        phaseRegistry: PhaseScriptRegistry,
        toolExecutionCoordinator: ToolExecutionCoordinator,
        toolRouter: ToolInteractionRouter,
        llmFacade: LLMFacade?,
        toolRegistry: ToolRegistry,
        dataStore: InterviewDataStore,
        phaseTransitionController: PhaseTransitionService,
        dataPersistenceService: DataPersistenceService,
        documentArtifactHandler: DocumentArtifactHandler,
        documentArtifactMessenger: DocumentArtifactMessenger,
        ui: OnboardingUIState,
        sessionPersistenceHandler: SessionPersistenceService,
        knowledgeCardStore: KnowledgeCardStore,
        skillStore: SkillStore,
        todoStore: InterviewTodoStore,
        budgetPauseGate: BudgetPauseGate
    ) {
        self.state = state
        self.eventBus = eventBus
        self.phaseRegistry = phaseRegistry
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
        self.knowledgeCardStore = knowledgeCardStore
        self.skillStore = skillStore
        self.todoStore = todoStore
        self.budgetPauseGate = budgetPauseGate
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
        let session = sessionPersistenceHandler.startSession(resumeExisting: false)
        await state.setPhase(.phase1VoiceContext)
        await phaseTransitionController.registerObjectivesForCurrentPhase()
        // Note: Todo list for Phase 1 is populated by AgentReadyTool.execute()
        subscribeToStateUpdates?()
        await documentArtifactHandler.start()
        await documentArtifactMessenger.start()

        // Set model ID BEFORE starting interview (so first message uses correct model)
        let modelId: String
        do {
            modelId = try OnboardingModelConfig.currentModelId()
        } catch let configError as ModelConfigurationError {
            Logger.error("❌ Model not configured: \(configError.localizedDescription)", category: .ai)
            NotificationCenter.default.post(
                name: .showModelSettings,
                object: nil,
                userInfo: ["settingKey": configError.settingKey]
            )
            return false
        } catch {
            Logger.error("❌ Failed to get interview model: \(error.localizedDescription)", category: .ai)
            return false
        }
        Logger.info("🎯 Setting interview model from settings: \(modelId)", category: .ai)
        await state.setModelId(modelId)

        // Install tape recording (if enabled) AFTER the model is set and BEFORE the
        // first LLM turn, so the very first model stream is captured.
        await beginTapeRecordingIfEnabled(sessionId: "\(session.id)", modelId: modelId)

        let success = await startLLM(isResuming: false)
        if success {
            ui.isActive = await state.isActive
            Logger.info("🎛️ Session isActive synced: \(ui.isActive)", category: .ai)
        }
        return success
    }

    /// Resume from an existing persisted session
    private func resumeSession(_ session: OnboardingSession) async -> Bool {
        // Restore ConversationLog (single source of truth)
        let conversationLog = await state.getConversationLog()
        await sessionPersistenceHandler.restoreConversationLog(session, to: conversationLog)

        // Sync UI messages from ConversationLog
        ui.messages = await conversationLog.getMessagesForUI()
        Logger.info("📥 Synced \(ui.messages.count) messages to UI from ConversationLog", category: .ai)

        // Restore UI state
        let phase = InterviewPhase(rawValue: session.phase) ?? .phase1VoiceContext
        ui.phase = phase

        // Check for pending cards/skills in SwiftData stores (persisted via isPending=true)
        // No need to restore from session - data lives in SwiftData
        let pendingCardCount = knowledgeCardStore.pendingCards.count
        let pendingSkillCount = skillStore.pendingSkills.count

        if pendingCardCount > 0 {
            ui.proposedAssignmentCount = pendingCardCount
            ui.identifiedGapCount = 0
            ui.cardAssignmentsReadyForApproval = true
            Logger.info("📥 Found \(pendingCardCount) pending cards, \(pendingSkillCount) pending skills in stores", category: .ai)
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

        // Restore todo list
        await restoreTodoList(from: session)

        // Restore dossier WIP notes (LLM scratchpad)
        await restoreDossierNotes(from: session)

        // Mark session as resumed
        _ = sessionPersistenceHandler.startSession(resumeExisting: true)

        subscribeToStateUpdates?()
        await documentArtifactHandler.start()
        await documentArtifactMessenger.start()

        // Re-publish tool permissions now that event subscriptions are active
        // (setPhase was called before subscriptions, so the event was missed)
        await state.publishAllowedToolsNow()

        // Set model ID BEFORE starting interview (so first message uses correct model)
        let modelId: String
        do {
            modelId = try OnboardingModelConfig.currentModelId()
        } catch let configError as ModelConfigurationError {
            Logger.error("❌ Model not configured: \(configError.localizedDescription)", category: .ai)
            NotificationCenter.default.post(
                name: .showModelSettings,
                object: nil,
                userInfo: ["settingKey": configError.settingKey]
            )
            return false
        } catch {
            Logger.error("❌ Failed to get interview model: \(error.localizedDescription)", category: .ai)
            return false
        }
        Logger.info("🎯 Setting interview model from settings (resume): \(modelId)", category: .ai)
        await state.setModelId(modelId)

        // Start LLM with resume flag
        let success = await startLLM(isResuming: true)
        if success {
            ui.isActive = await state.isActive
            Logger.info("🎛️ Resumed session isActive synced: \(ui.isActive)", category: .ai)

            // Re-surface a multiple-choice prompt that was awaiting the user when the
            // session was last closed. Its tool_use was stripped from history on restore
            // (Anthropic invariant), so we rebuild the card from the persisted arguments
            // and re-publish the same event the live tool does. The user's answer returns
            // as a normal user turn (UIResponseCoordinator handles the missing continuation).
            // Published after startLLM so ToolInteractionRouter's subscription is active.
            if let pendingPrompt = sessionPersistenceHandler.findUnresolvedChoicePrompt(in: session) {
                await eventBus.publish(.toolpane(.choicePromptRequested(prompt: pendingPrompt)))
                Logger.info("📥 Re-surfaced pending choice prompt on resume (id: \(pendingPrompt.id))", category: .ai)
            }
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

        // Restore title set curation flag for Phase 4
        // Check customFieldDefinitions first, fall back to enabled sections containing "custom"
        let phase = InterviewPhase(rawValue: session.phase) ?? .phase1VoiceContext
        if phase == .phase4StrategicSynthesis {
            let customFields = await state.getCustomFieldDefinitions()
            if customFields.contains(where: { $0.key.lowercased() == "custom.jobtitles" }) {
                ui.shouldGenerateTitleSets = true
                Logger.info("📥 Restored title set curation: enabled (from customFieldDefinitions)", category: .ai)
            } else {
                // Fallback: if "custom" section is enabled, assume job titles were configured
                let enabledSections = await state.getEnabledSections()
                ui.shouldGenerateTitleSets = enabledSections.contains("custom")
                Logger.info(
                    "📥 Restored title set curation: \(ui.shouldGenerateTitleSets ? "enabled" : "disabled") (from enabledSections fallback)",
                    category: .ai
                )
            }
        }
    }

    /// Restore todo list from persisted session
    private func restoreTodoList(from session: OnboardingSession) async {
        guard let todoListJSON = sessionPersistenceHandler.getRestoredTodoList(session),
              let data = todoListJSON.data(using: .utf8),
              let items = try? JSONDecoder().decode([InterviewTodoItem].self, from: data) else {
            return
        }

        await todoStore.restoreItems(items)
        Logger.info("📥 Restored \(items.count) todo item(s)", category: .ai)
    }

    /// Restore dossier WIP notes from persisted session
    private func restoreDossierNotes(from session: OnboardingSession) async {
        guard let notes = sessionPersistenceHandler.getRestoredDossierNotes(session), !notes.isEmpty else {
            return
        }

        await state.setDossierNotes(notes)
        Logger.info("📥 Restored dossier notes (\(notes.count) chars)", category: .ai)
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
        await toolExecutionCoordinator.startEventSubscriptions()
        await toolRouter.startEventSubscriptions()

        // Build orchestrator
        let phase = await state.phase
        let baseSystemPrompt = phaseRegistry.buildSystemPrompt(for: phase)
        let orchestrator = makeOrchestrator(llmFacade: facade, baseSystemPrompt: baseSystemPrompt)
        self.orchestrator = orchestrator

        // Publish phase transition BEFORE orchestrator sends initial message
        // This ensures the phase intro is queued and can be bundled with
        // the initial "I'm ready to begin" user message
        if !isResuming {
            await eventBus.publish(.phase(.transitionApplied(phase: phase.rawValue, timestamp: Date())))
        }

        // Initialize orchestrator with resume flag
        // Now safe to send initial message - StateCoordinator is already subscribed
        // and phase intro is already queued for bundling
        do {
            try await orchestrator.startInterview(isResuming: isResuming)
        } catch {
            Logger.error("Failed to start orchestrator: \(error)", category: .ai)
            await state.setActiveState(false)
            ToastCenter.shared.show(.error("Couldn't start the interview — \(error.localizedDescription)"))
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
        let transcriptHandler = TranscriptPersistenceService(
            eventBus: eventBus,
            dataStore: dataStore
        )
        transcriptPersistenceHandler = transcriptHandler
        await transcriptHandler.start()

        return true
    }

    private func resetForFreshStart() async {
        await endTapeRecording()
        await state.reset()
        clearArtifacts()
        await resetStore()
    }

    // MARK: - Tape Recording

    /// Install the recording decorator + session recorder when the dev toggle is on.
    /// No-op (and zero overhead) otherwise. Best-effort: a recording-setup failure
    /// never blocks the interview.
    private func beginTapeRecordingIfEnabled(sessionId: String, modelId: String) async {
        // Never record while replaying — the replay service is already installed,
        // and wrapping it in a recording decorator stacks the two and breaks the
        // go-live swap (see SessionReplayService).
        guard !suppressTapeRecording else {
            Logger.info("🎙️ Tape recording suppressed (replay in progress)", category: .ai)
            return
        }
        guard UserDefaults.standard.bool(forKey: Self.recordingEnabledKey) else { return }
        guard let facade = llmFacade, let realService = facade.currentAnthropicService() else {
            Logger.warning("🎙️ Tape recording enabled but no Anthropic service to wrap — skipping", category: .ai)
            return
        }
        let recorder = SessionTapeRecorder()
        await recorder.start(sessionId: sessionId, modelId: modelId)
        savedAnthropicService = realService
        facade.registerAnthropicService(RecordingAnthropicService(wrapping: realService, recorder: recorder))
        await state.setTapeRecorder(recorder)
        tapeRecorder = recorder
        Logger.info("🎙️ Tape recording started for session \(sessionId)", category: .ai)
    }

    /// Stop recording (if active) and restore the real, un-decorated service.
    private func endTapeRecording() async {
        guard let recorder = tapeRecorder else { return }
        await recorder.stop()
        if let real = savedAnthropicService {
            llmFacade?.registerAnthropicService(real)
        }
        savedAnthropicService = nil
        await state.setTapeRecorder(nil)
        tapeRecorder = nil
        Logger.info("🎙️ Tape recording stopped", category: .ai)
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
        // Section card topic - for non-chronological section cards (awards, languages, references)
        let sectionCardTask = Task { [weak self] in
            guard let self else { return }
            for await event in await self.eventBus.stream(topic: .sectionCard) {
                if Task.isCancelled { break }
                await handlers.handleSectionCardEvent(event)
            }
        }
        stateUpdateTasks.append(sectionCardTask)
        // Publication card topic - for publication cards
        let publicationCardTask = Task { [weak self] in
            guard let self else { return }
            for await event in await self.eventBus.stream(topic: .publicationCard) {
                if Task.isCancelled { break }
                await handlers.handlePublicationCardEvent(event)
            }
        }
        stateUpdateTasks.append(publicationCardTask)
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
        baseSystemPrompt: String
    ) -> InterviewOrchestrator {
        return InterviewOrchestrator(
            llmFacade: llmFacade,
            baseSystemPrompt: baseSystemPrompt,
            eventBus: eventBus,
            toolRegistry: toolRegistry,
            state: state,
            todoStore: todoStore,
            budgetPauseGate: budgetPauseGate
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
    let handleSectionCardEvent: (OnboardingEvent) async -> Void
    let handlePublicationCardEvent: (OnboardingEvent) async -> Void
    let handlePhaseEvent: (OnboardingEvent) async -> Void
    let performInitialSync: () async -> Void
}
