import Foundation
import Observation
import SwiftyJSON
import SwiftOpenAI
import UniformTypeIdentifiers

/// Coordinator that orchestrates the onboarding interview flow.
/// All state is managed by StateCoordinator actor - this is just the orchestration layer.
@MainActor
@Observable
final class OnboardingInterviewCoordinator {
    // MARK: - Core Dependencies

    private let state: StateCoordinator
    private let eventBus: EventCoordinator
    private let chatTranscriptStore: ChatTranscriptStore
    private let chatboxHandler: ChatboxHandler
    private let toolExecutionCoordinator: ToolExecutionCoordinator
    let toolRouter: ToolHandler
    let wizardTracker: WizardProgressTracker
    let phaseRegistry: PhaseScriptRegistry
    let toolRegistry: ToolRegistry
    private let toolExecutor: ToolExecutor
    private let openAIService: OpenAIService?
    private let documentExtractionService: DocumentExtractionService
    private let knowledgeCardAgent: KnowledgeCardAgent?

    // Event subscription tracking
    private var eventSubscriptionTask: Task<Void, Never>?
    private var stateUpdateTasks: [Task<Void, Never>] = []

    // Phase 3: Workflow engine
    private var workflowEngine: ObjectiveWorkflowEngine?

    // Phase 3: Artifact persistence handler
    private var artifactPersistenceHandler: ArtifactPersistenceHandler?

    // Phase 3: Debounced checkpointing
    private var checkpointDebounce: Task<Void, Never>?

    // MARK: - Data Store Dependencies

    private let applicantProfileStore: ApplicantProfileStore
    private let dataStore: InterviewDataStore
    let checkpoints: Checkpoints

    // MARK: - Orchestration State (minimal, not business state)

    private var orchestrator: InterviewOrchestrator?
    private var phaseAdvanceContinuationId: UUID?
    // Phase advance cache removed - no longer needed with centralized state
    private var toolQueueEntries: [UUID: ToolQueueEntry] = [:]
    private var pendingExtractionProgressBuffer: [ExtractionProgressUpdate] = []
    private var reasoningSummaryClearTask: Task<Void, Never>?
    var onModelAvailabilityIssue: ((String) -> Void)?
    private(set) var preferences: OnboardingPreferences
    private(set) var modelAvailabilityMessage: String?

    private struct ToolQueueEntry {
        let tokenId: UUID
        let callId: String
        let toolName: String
        let status: String
        let requestedInput: String
        let enqueuedAt: Date
    }

    // MARK: - Computed Properties (Read from StateCoordinator)

    var isProcessing: Bool {
        get async { await state.isProcessing }
    }

    var isActive: Bool {
        get async { await state.isActive }
    }

    var pendingExtraction: OnboardingPendingExtraction? {
        get async { await state.pendingExtraction }
    }

    var pendingStreamingStatus: String? {
        get async { await state.pendingStreamingStatus }
    }

    var latestReasoningSummary: String? {
        get async { await state.latestReasoningSummary }
    }

    var currentPhase: InterviewPhase {
        get async { await state.phase }
    }

    var wizardStep: StateCoordinator.WizardStep {
        get async { await state.currentWizardStep }
    }

    var applicantProfileJSON: JSON? {
        get async { await state.artifacts.applicantProfile }
    }

    var skeletonTimelineJSON: JSON? {
        get async { await state.artifacts.skeletonTimeline }
    }

    var artifacts: StateCoordinator.OnboardingArtifacts {
        get async { await state.artifacts }
    }

    // MARK: - Chat Messages

    var messages: [OnboardingMessage] {
        chatTranscriptStore.messages
    }

    func sendChatMessage(_ text: String) async {
        await chatboxHandler.sendUserMessage(text)
    }

    // Properties that need synchronous access for SwiftUI
    // These will be updated via observation when state changes
    @ObservationIgnored
    private var _isProcessingSync = false
    var isProcessingSync: Bool { _isProcessingSync }

    @ObservationIgnored
    private var _pendingExtractionSync: OnboardingPendingExtraction?
    var pendingExtractionSync: OnboardingPendingExtraction? { _pendingExtractionSync }

    @ObservationIgnored
    private var _pendingStreamingStatusSync: String?
    var pendingStreamingStatusSync: String? { _pendingStreamingStatusSync }

    // MARK: - UI State Properties (from ToolRouter)

    var pendingUploadRequests: [OnboardingUploadRequest] {
        toolRouter.pendingUploadRequests
    }

    var pendingChoicePrompt: OnboardingChoicePrompt? {
        toolRouter.pendingChoicePrompt
    }

    var pendingValidationPrompt: OnboardingValidationPrompt? {
        toolRouter.pendingValidationPrompt
    }

    var pendingApplicantProfileRequest: OnboardingApplicantProfileRequest? {
        toolRouter.pendingApplicantProfileRequest
    }

    var pendingApplicantProfileIntake: OnboardingApplicantProfileIntakeState? {
        toolRouter.pendingApplicantProfileIntake
    }

    var pendingSectionToggleRequest: OnboardingSectionToggleRequest? {
        toolRouter.pendingSectionToggleRequest
    }

    var pendingPhaseAdvanceRequest: OnboardingPhaseAdvanceRequest? {
        get async {
            await state.pendingPhaseAdvanceRequest
        }
    }

    func eventStream(for topic: EventTopic) async -> AsyncStream<OnboardingEvent> {
        await eventBus.stream(topic: topic)
    }

    // MARK: - Initialization

    init(
        openAIService: OpenAIService?,
        documentExtractionService: DocumentExtractionService,
        applicantProfileStore: ApplicantProfileStore,
        dataStore: InterviewDataStore,
        checkpoints: Checkpoints,
        preferences: OnboardingPreferences
    ) {
        let eventBus = EventCoordinator()
        self.eventBus = eventBus

        // Build phase policy from PhaseScriptRegistry
        let registry = PhaseScriptRegistry()
        self.phaseRegistry = registry
        let phasePolicy = PhasePolicy(
            requiredObjectives: Dictionary(uniqueKeysWithValues: InterviewPhase.allCases.map {
                ($0, registry.script(for: $0)?.requiredObjectives ?? [])
            }),
            allowedTools: Dictionary(uniqueKeysWithValues: InterviewPhase.allCases.map {
                ($0, Set(registry.script(for: $0)?.allowedTools ?? []))
            })
        )

        self.state = StateCoordinator(eventBus: eventBus, phasePolicy: phasePolicy)
        self.openAIService = openAIService
        self.documentExtractionService = documentExtractionService
        self.knowledgeCardAgent = openAIService.map { KnowledgeCardAgent(client: $0) }
        self.applicantProfileStore = applicantProfileStore
        self.dataStore = dataStore
        self.checkpoints = checkpoints
        self.preferences = preferences

        self.chatTranscriptStore = ChatTranscriptStore()
        self.chatboxHandler = ChatboxHandler(
            eventBus: eventBus,
            transcriptStore: chatTranscriptStore
        )

        self.toolRegistry = ToolRegistry()
        self.toolExecutor = ToolExecutor(registry: toolRegistry)
        self.toolExecutionCoordinator = ToolExecutionCoordinator(
            eventBus: eventBus,
            toolExecutor: toolExecutor,
            stateCoordinator: state
        )

        // Create handlers for tool router
        let promptHandler = PromptInteractionHandler()

        let uploadStorage = OnboardingUploadStorage()
        let uploadFileService = UploadFileService()
        let uploadHandler = UploadInteractionHandler(
            uploadFileService: uploadFileService,
            uploadStorage: uploadStorage,
            applicantProfileStore: applicantProfileStore,
            dataStore: dataStore,
            extractionProgressHandler: nil
        )

        let contactsImportService = ContactsImportService()
        let profileHandler = ProfileInteractionHandler(contactsImportService: contactsImportService)

        let sectionHandler = SectionToggleHandler()

        self.toolRouter = ToolHandler(
            promptHandler: promptHandler,
            uploadHandler: uploadHandler,
            profileHandler: profileHandler,
            sectionHandler: sectionHandler,
            eventBus: eventBus
        )
        self.wizardTracker = WizardProgressTracker()

        toolRouter.uploadHandler.updateExtractionProgressHandler { [weak self] update in
            Task { @MainActor in
                guard let self else { return }
                self.updateExtractionProgress(with: update)
            }
        }

        // Register all tools
        registerTools()

        Logger.info("🎯 OnboardingInterviewCoordinator initialized with event-driven architecture", category: .ai)

        // Subscribe to events from the orchestrator
        Task { await subscribeToEvents() }
    }

    // MARK: - Tool Registration

    private func registerTools() {
        // Set up extraction progress handler
        Task {
            await documentExtractionService.setInvalidModelHandler { [weak self] modelId in
                Task { @MainActor in
                    guard let self else { return }
                    self.notifyInvalidModel(id: modelId)
                    self.onModelAvailabilityIssue?("Your selected model (\(modelId)) is not available. Choose another model in Settings.")
                }
            }
        }

        // Register all tools with coordinator reference
        toolRegistry.register(GetUserOptionTool(coordinator: self))
        toolRegistry.register(GetUserUploadTool(coordinator: self))
        toolRegistry.register(CancelUserUploadTool(coordinator: self))
        toolRegistry.register(GetApplicantProfileTool(coordinator: self))
        toolRegistry.register(GetMacOSContactCardTool())
        toolRegistry.register(ExtractDocumentTool(
            extractionService: documentExtractionService,
            progressHandler: { [weak self] update in
                await MainActor.run {
                    guard let self else { return }
                    self.updateExtractionProgress(with: update)
                }
            }
        ))
        toolRegistry.register(CreateTimelineCardTool(coordinator: self))
        toolRegistry.register(UpdateTimelineCardTool(coordinator: self))
        toolRegistry.register(DeleteTimelineCardTool(coordinator: self))
        toolRegistry.register(ReorderTimelineCardsTool(coordinator: self))
        toolRegistry.register(SubmitForValidationTool(coordinator: self))
        toolRegistry.register(ListArtifactsTool(coordinator: self))
        toolRegistry.register(GetArtifactRecordTool(coordinator: self))
        toolRegistry.register(RequestRawArtifactFileTool(coordinator: self))
        toolRegistry.register(PersistDataTool(dataStore: dataStore))
        toolRegistry.register(SetObjectiveStatusTool(coordinator: self))
        toolRegistry.register(NextPhaseTool(coordinator: self))
        toolRegistry.register(ValidateApplicantProfileTool(coordinator: self))

        if let agent = knowledgeCardAgent {
            toolRegistry.register(GenerateKnowledgeCardTool(agentProvider: { agent }))
        }

        Logger.info("✅ Registered \(toolRegistry.allToolNames.count) tools", category: .ai)
    }

    // MARK: - Event Subscription

    private func subscribeToEvents() async {
        // Cancel any existing subscription
        eventSubscriptionTask?.cancel()

        // Subscribe to all events (for now, until we refactor to topic-specific handling)
        eventSubscriptionTask = Task { [weak self] in
            guard let self else { return }

            for await event in await eventBus.streamAll() {
                await self.handleEvent(event)
            }
        }
    }

    private func handleEvent(_ event: OnboardingEvent) async {
        // Phase 3: Schedule checkpoint for significant events
        switch event {
        case .objectiveStatusChanged, .timelineCardCreated, .timelineCardUpdated,
             .timelineCardDeleted, .timelineCardsReordered, .skeletonTimelineReplaced,
             .artifactRecordPersisted, .phaseTransitionApplied:
            scheduleCheckpoint()
        default:
            break
        }

        switch event {
        case .processingStateChanged(let processing):
            await state.setProcessingState(processing)

        case .streamingMessageBegan(_, let text, let reasoningExpected):
            // StateCoordinator only - ChatboxHandler mirrors to transcript
            _ = await state.beginStreamingMessage(initialText: text, reasoningExpected: reasoningExpected)

        case .streamingMessageUpdated(let id, let delta):
            // StateCoordinator only - ChatboxHandler mirrors to transcript
            await state.updateStreamingMessage(id: id, delta: delta)

        case .streamingMessageFinalized(let id, let finalText):
            // StateCoordinator only - ChatboxHandler mirrors to transcript
            _ = await state.finalizeStreamingMessage(id: id, finalText: finalText)

        case .llmReasoningSummary(let messageId, let summary, let isFinal):
            // StateCoordinator only - ChatboxHandler mirrors to transcript
            await state.setReasoningSummary(summary, for: messageId)

        case .streamingStatusUpdated(let status):
            await setStreamingStatus(status)

        case .waitingStateChanged(let waiting):
            await MainActor.run {
                self.updateWaitingState(waiting)
            }

        case .errorOccurred(let error):
            Logger.error("Interview error: \(error)", category: .ai)

        case .applicantProfileStored(let json):
            await MainActor.run {
                self.storeApplicantProfile(json)
            }

        case .skeletonTimelineStored(let json):
            await MainActor.run {
                self.storeSkeletonTimeline(json)
            }

        case .enabledSectionsUpdated(let sections):
            await MainActor.run {
                self.updateEnabledSections(sections)
            }

        case .checkpointRequested:
            await saveCheckpoint()

        case .toolCallRequested:
            // Tool execution now handled by ToolExecutionCoordinator
            break

        case .toolCallCompleted:
            // Tool completion is handled by toolContinuationNeeded
            break

        case .toolContinuationNeeded(let continuationId, let toolName):
            // Track continuation for UI resume methods
            // Note: callId is not available here, stored by ToolExecutionCoordinator
            toolQueueEntries[continuationId] = ToolQueueEntry(
                tokenId: continuationId,
                callId: "", // CallId managed by ToolExecutionCoordinator
                toolName: toolName,
                status: "waiting",
                requestedInput: "{}",
                enqueuedAt: Date()
            )

        case .objectiveStatusRequested(let id, let response):
            let status = await state.getObjectiveStatus(id)?.rawValue
            response(status)

        // Tool UI events - handled by ToolHandler
        case .choicePromptRequested, .choicePromptCleared,
             .uploadRequestPresented, .uploadRequestCancelled,
             .validationPromptRequested, .validationPromptCleared,
             .applicantProfileIntakeRequested, .applicantProfileIntakeCleared,
             .phaseAdvanceRequested,
             .timelineCardCreated, .timelineCardDeleted, .timelineCardsReordered,
             .artifactGetRequested, .artifactNewRequested, .artifactAdded, .artifactUpdated, .artifactDeleted,
             .artifactRecordProduced, .artifactRecordPersisted,
             // New spec-aligned events that StateCoordinator handles
             .objectiveStatusChanged, .objectiveStatusUpdateRequested,
             .stateSnapshot, .stateAllowedToolsUpdated,
             .llmUserMessageSent, .llmDeveloperMessageSent, .llmSentToolResponseMessage,
             .llmSendUserMessage, .llmSendDeveloperMessage, .llmToolResponseMessage, .llmStatus,
             .llmReasoningStatus,
             .phaseTransitionRequested, .timelineCardUpdated:
            // These events are handled by StateCoordinator/handlers, not the coordinator
            break

        case .phaseTransitionApplied(let phaseName, _):
            // Update the system prompt when phase transitions (Phase 3)
            await handlePhaseTransition(phaseName)
        }
    }

    // MARK: - State Updates

    private func subscribeToStateUpdates() {
        stateUpdateTasks.forEach { $0.cancel() }
        stateUpdateTasks.removeAll()

        let processingTask = Task { [weak self] in
            guard let self else { return }

            for await event in await self.eventBus.stream(topic: .processing) {
                if Task.isCancelled { break }
                await self.handleProcessingEvent(event)
            }
        }
        stateUpdateTasks.append(processingTask)

        let artifactTask = Task { [weak self] in
            guard let self else { return }

            for await event in await self.eventBus.stream(topic: .artifact) {
                if Task.isCancelled { break }
                await self.handleArtifactEvent(event)
            }
        }
        stateUpdateTasks.append(artifactTask)

        let llmTask = Task { [weak self] in
            guard let self else { return }

            for await event in await self.eventBus.stream(topic: .llm) {
                if Task.isCancelled { break }
                await self.handleLLMEvent(event)
            }
        }
        stateUpdateTasks.append(llmTask)

        let stateTask = Task { [weak self] in
            guard let self else { return }

            for await event in await self.eventBus.stream(topic: .state) {
                if Task.isCancelled { break }
                await self.handleStateSyncEvent(event)
            }
        }
        stateUpdateTasks.append(stateTask)

        Task { [weak self] in
            guard let self else { return }
            await self.initialStateSync()
        }
    }

    private func handleProcessingEvent(_ event: OnboardingEvent) async {
        switch event {
        case .processingStateChanged(let processing):
            _isProcessingSync = processing
            await syncWizardProgressFromState()

        case .streamingStatusUpdated(let status):
            _pendingStreamingStatusSync = status

        case .waitingStateChanged:
            await syncPendingExtractionFromState()

        default:
            break
        }
    }

    private func handleArtifactEvent(_ event: OnboardingEvent) async {
        switch event {
        case .artifactNewRequested, .artifactAdded, .artifactUpdated, .artifactDeleted:
            await syncPendingExtractionFromState()
            await syncWizardProgressFromState()

        default:
            break
        }
    }

    private func handleLLMEvent(_ event: OnboardingEvent) async {
        switch event {
        case .llmReasoningStatus(let status):
            _pendingStreamingStatusSync = status == "none" ? nil : status

        case .llmStatus(let status):
            if status == .idle || status == .error {
                _pendingStreamingStatusSync = nil
            }

        default:
            break
        }
    }

    private func handleStateSyncEvent(_ event: OnboardingEvent) async {
        switch event {
        case .stateSnapshot, .stateAllowedToolsUpdated:
            await syncWizardProgressFromState()
            await syncPendingExtractionFromState()

        default:
            break
        }
    }

    private func syncPendingExtractionFromState() async {
        _pendingExtractionSync = await state.pendingExtraction
    }

    private func syncWizardProgressFromState() async {
        let step = await state.currentWizardStep
        let completed = await state.completedWizardSteps
        synchronizeWizardTracker(currentStep: step, completedSteps: completed)
    }

    private func initialStateSync() async {
        _isProcessingSync = await state.isProcessing
        await syncPendingExtractionFromState()
        _pendingStreamingStatusSync = await state.pendingStreamingStatus
        await syncWizardProgressFromState()
    }

    // MARK: - Interview Lifecycle

    func startInterview(resumeExisting: Bool = false) async -> Bool {
        Logger.info("🚀 Starting interview (resume: \(resumeExisting))", category: .ai)

        // Reset or restore state
        if resumeExisting {
            await loadPersistedArtifacts()
            let didRestore = await restoreFromCheckpointIfAvailable()
            if !didRestore {
                await state.reset()
                await clearCheckpoints()
                clearArtifacts()
                await resetStore()
            }
        } else {
            await state.reset()
            await clearCheckpoints()
            clearArtifacts()
            await resetStore()
        }

        await state.setActiveState(true)
        await registerObjectivesForCurrentPhase()

        // Build and start orchestrator
        let phase = await state.phase
        let systemPrompt = phaseRegistry.buildSystemPrompt(for: phase)
        guard let service = openAIService else {
            await state.setActiveState(false)
            return false
        }

        let orchestrator = makeOrchestrator(service: service, systemPrompt: systemPrompt)
        self.orchestrator = orchestrator

        // Start event subscriptions for handlers
        await chatboxHandler.startEventSubscriptions()
        await toolExecutionCoordinator.startEventSubscriptions()
        await state.startEventSubscriptions()
        subscribeToStateUpdates()
        await MainActor.run {
            toolRouter.startEventSubscriptions()
        }
        await state.publishAllowedToolsNow()

        // Phase 3: Start workflow engine
        let engine = ObjectiveWorkflowEngine(
            eventBus: eventBus,
            phaseRegistry: phaseRegistry,
            state: state
        )
        workflowEngine = engine
        await engine.start()

        // Phase 3: Start artifact persistence handler
        let persistenceHandler = ArtifactPersistenceHandler(
            eventBus: eventBus,
            dataStore: dataStore
        )
        artifactPersistenceHandler = persistenceHandler
        await persistenceHandler.start()

        Task {
            do {
                try await orchestrator.startInterview()
            } catch {
                Logger.error("Interview failed: \(error)", category: .ai)
                await endInterview()
            }
        }

        return true
    }

    func endInterview() async {
        Logger.info("🛑 Ending interview", category: .ai)
        await orchestrator?.endInterview()
        orchestrator = nil
        await workflowEngine?.stop()
        workflowEngine = nil
        await artifactPersistenceHandler?.stop()
        artifactPersistenceHandler = nil
        await state.setActiveState(false)
        await state.setProcessingState(false)
        stateUpdateTasks.forEach { $0.cancel() }
        stateUpdateTasks.removeAll()
    }

    // MARK: - Phase Management

    private func handlePhaseTransition(_ phaseName: String) async {
        guard let phase = InterviewPhase(rawValue: phaseName) else {
            Logger.warning("Invalid phase name: \(phaseName)", category: .ai)
            return
        }

        // Rebuild system prompt for new phase
        let newPrompt = phaseRegistry.buildSystemPrompt(for: phase)

        // Update orchestrator's system prompt (Phase 3)
        await orchestrator?.updateSystemPrompt(newPrompt)

        Logger.info("🔄 System prompt updated for phase: \(phaseName)", category: .ai)
    }

    func advancePhase() async -> InterviewPhase? {
        guard let newPhase = await state.advanceToNextPhase() else { return nil }

        // Update wizard progress
        let completedSteps = await state.completedWizardSteps
        let currentStep = await state.currentWizardStep
        synchronizeWizardTracker(currentStep: currentStep, completedSteps: completedSteps)

        await registerObjectivesForCurrentPhase()
        return newPhase
    }

    func getCompletedObjectiveIds() async -> Set<String> {
        let objectives = await state.getAllObjectives()
        return Set(objectives
            .filter { $0.status == .completed || $0.status == .skipped }
            .map { $0.id })
    }

    // MARK: - Objective Management

    func registerObjectivesForCurrentPhase() async {
        // Objectives are now automatically registered by StateCoordinator
        // when the phase is set, so this is no longer needed
        Logger.info("📋 Objectives auto-registered by StateCoordinator for current phase", category: .ai)
    }

    func updateObjectiveStatus(objectiveId: String, status: String) async throws -> JSON {
        // Emit event to update objective status
        await eventBus.publish(.objectiveStatusUpdateRequested(
            id: objectiveId,
            status: status.lowercased(),
            source: "tool",
            notes: nil
        ))

        var result = JSON()
        result["success"].boolValue = true
        result["objective_id"].stringValue = objectiveId
        result["new_status"].stringValue = status.lowercased()

        return result
    }

    // MARK: - Timeline Management (Event-Driven)

    /// Apply user timeline update from editor (Phase 3)
    /// Replaces timeline in one shot and sends developer message
    func applyUserTimelineUpdate(cards: [TimelineCard], meta: JSON?, diff: TimelineDiff) async {
        // Build timeline JSON
        let timeline = TimelineCardAdapter.makeTimelineJSON(cards: cards, meta: meta)

        // Emit replacement event
        await eventBus.publish(.skeletonTimelineReplaced(timeline: timeline, diff: diff, meta: meta))

        // Build developer message
        var payload = JSON()
        payload["text"].string = "Developer status: Timeline cards updated by the user (\(diff.summary)). The skeleton_timeline artifact now reflects their edits. Do not re-validate unless new information is introduced."

        var details = JSON()
        details["validation_state"].string = "user_validated"
        details["diff_summary"].string = diff.summary
        details["updated_count"].int = cards.count
        payload["details"] = details
        payload["payload"] = timeline

        // Send developer message
        await eventBus.publish(.llmSendDeveloperMessage(payload: payload))

        Logger.info("📋 User timeline update applied (\(diff.summary))", category: .ai)
    }

    func createTimelineCard(fields: JSON) async -> JSON {
        var card = fields
        // Add ID if not present
        if card["id"].string == nil {
            card["id"].string = UUID().uuidString
        }

        // Emit event to create timeline card
        await eventBus.publish(.timelineCardCreated(card: card))

        var result = JSON()
        result["success"].boolValue = true
        result["id"].string = card["id"].string
        return result
    }

    func updateTimelineCard(id: String, fields: JSON) async -> JSON {
        // Emit event to update timeline card
        await eventBus.publish(.timelineCardUpdated(id: id, fields: fields))

        var result = JSON()
        result["success"].boolValue = true
        result["id"].string = id
        return result
    }

    func deleteTimelineCard(id: String) async -> JSON {
        // Emit event to delete timeline card
        await eventBus.publish(.timelineCardDeleted(id: id))

        var result = JSON()
        result["success"].boolValue = true
        result["id"].string = id
        return result
    }

    func reorderTimelineCards(orderedIds: [String]) async -> JSON {
        // Emit event to reorder timeline cards
        await eventBus.publish(.timelineCardsReordered(ids: orderedIds))

        var result = JSON()
        result["success"].boolValue = true
        result["count"].int = orderedIds.count
        return result
    }

    func requestPhaseTransition(from: String, to: String, reason: String?) async {
        await eventBus.publish(.phaseTransitionRequested(
            from: from,
            to: to,
            reason: reason
        ))
    }

    func missingObjectives() async -> [String] {
        await state.getMissingObjectives()
    }

    // MARK: - Artifact Queries (Read-Only State Access)

    func listArtifactSummaries() async -> [JSON] {
        await state.listArtifactSummaries()
    }

    func getArtifactRecord(id: String) async -> JSON? {
        await state.getArtifactRecord(id: id)
    }

    func getArtifact(id: String) async -> JSON? {
        // Query StateCoordinator's artifact state
        let artifacts = await state.artifacts

        // Search in experience cards
        if let card = artifacts.experienceCards.first(where: { $0["id"].string == id }) {
            return card
        }

        // Search in writing samples
        if let sample = artifacts.writingSamples.first(where: { $0["id"].string == id }) {
            return sample
        }

        return nil
    }

    func cancelUploadRequest(id: UUID) async {
        // Emit upload cancellation event
        await eventBus.publish(.uploadRequestCancelled(id: id))
    }

    func nextPhase() async -> InterviewPhase? {
        let canAdvance = await state.canAdvancePhase()
        guard canAdvance else { return nil }

        let currentPhase = await state.phase
        switch currentPhase {
        case .phase1CoreFacts:
            return .phase2DeepDive
        case .phase2DeepDive:
            return .phase3WritingCorpus
        case .phase3WritingCorpus, .complete:
            return nil
        }
    }

    // MARK: - Artifact Management

    func storeApplicantProfile(_ profile: JSON) {
        Task { [weak self] in
            guard let self else { return }
            await self.state.setApplicantProfile(profile)
            await MainActor.run {
                self.persistApplicantProfileToSwiftData(json: profile)
            }
            await self.saveCheckpoint()
        }
    }

    func storeSkeletonTimeline(_ timeline: JSON) {
        Task {
            await state.setSkeletonTimeline(timeline)
            await saveCheckpoint()
        }
    }

    func updateEnabledSections(_ sections: Set<String>) {
        Task {
            await state.setEnabledSections(sections)
            await saveCheckpoint()
        }
    }

    // MARK: - Message Management

    @discardableResult
    func appendUserMessage(_ text: String) async -> UUID {
        // Only update StateCoordinator - ChatboxHandler mirrors to transcript
        let id = await state.appendUserMessage(text)
        return id
    }

    @discardableResult
    func appendAssistantMessage(_ text: String, reasoningExpected: Bool) async -> UUID {
        // Only update StateCoordinator - ChatboxHandler mirrors to transcript
        let id = await state.appendAssistantMessage(text)
        return id
    }

    @discardableResult
    func beginAssistantStream(initialText: String, reasoningExpected: Bool) async -> UUID {
        // Only update StateCoordinator - ChatboxHandler mirrors to transcript
        let id = await state.beginStreamingMessage(
            initialText: initialText,
            reasoningExpected: reasoningExpected
        )
        return id
    }

    func updateAssistantStream(id: UUID, text: String) async {
        // Only update StateCoordinator - ChatboxHandler mirrors to transcript
        await state.updateStreamingMessage(id: id, delta: text)
    }

    func finalizeAssistantStream(id: UUID, text: String) async -> TimeInterval {
        // Only update StateCoordinator - ChatboxHandler mirrors to transcript
        await state.finalizeStreamingMessage(id: id, finalText: text)
        return 0 // Elapsed time now tracked by ChatboxHandler
    }

    func updateReasoningSummary(_ summary: String, for messageId: UUID, isFinal: Bool) async {
        // Only update StateCoordinator - ChatboxHandler mirrors to transcript
        await state.setReasoningSummary(summary, for: messageId)
    }

    func clearLatestReasoningSummary() {
        Task {
            await state.setReasoningSummary(nil, for: UUID())
        }
    }

    // MARK: - Waiting State

    func updateWaitingState(_ waiting: String?) {
        Task {
            let waitingState: StateCoordinator.WaitingState? = if let waiting {
                switch waiting {
                case "selection": .selection
                case "upload": .upload
                case "validation": .validation
                case "extraction": .extraction
                case "processing": .processing
                default: nil
                }
            } else {
                nil
            }
            await state.setWaitingState(waitingState)
        }
    }


    // MARK: - Extraction Management

    func setExtractionStatus(_ extraction: OnboardingPendingExtraction?) {
        Task {
            await state.setPendingExtraction(extraction)
            _pendingExtractionSync = extraction

            guard let extraction else { return }
            if shouldClearApplicantProfileIntake(for: extraction) {
                await MainActor.run {
                    toolRouter.clearApplicantProfileIntake()
                }
                Logger.debug(
                    "🧹 Cleared applicant profile intake for extraction",
                    category: .ai,
                    metadata: [
                        "title": extraction.title,
                        "summary": extraction.summary
                    ]
                )
            }
        }
    }

    private func shouldClearApplicantProfileIntake(for extraction: OnboardingPendingExtraction) -> Bool {
        // If the extraction already contains an applicant profile, clear the intake immediately.
        if extraction.rawExtraction["derived"]["applicant_profile"] != .null {
            return true
        }

        let metadata = extraction.rawExtraction["metadata"]
        var candidateStrings: [String] = []

        if let purpose = metadata["purpose"].string { candidateStrings.append(purpose) }
        if let documentKind = metadata["document_kind"].string { candidateStrings.append(documentKind) }
        if let sourceFilename = metadata["source_filename"].string { candidateStrings.append(sourceFilename) }

        candidateStrings.append(extraction.title)
        candidateStrings.append(extraction.summary)

        let resumeKeywords = ["resume", "curriculum vitae", "curriculum", "cv", "applicant profile"]
        for value in candidateStrings {
            let lowercased = value.lowercased()
            if resumeKeywords.contains(where: { lowercased.contains($0) }) {
                return true
            }
        }

        let tags = metadata["tags"].arrayValue.compactMap { $0.string?.lowercased() }
        if tags.contains(where: { tag in resumeKeywords.contains(where: { tag.contains($0) }) }) {
            return true
        }

        return false
    }

    func updateExtractionProgress(with update: ExtractionProgressUpdate) {
        Task {
            if var extraction = await state.pendingExtraction {
                extraction.applyProgressUpdate(update)
                await state.setPendingExtraction(extraction)
                _pendingExtractionSync = extraction
            } else {
                pendingExtractionProgressBuffer.append(update)
            }
        }
    }

    func setStreamingStatus(_ status: String?) async {
        await state.setStreamingStatus(status)
        _pendingStreamingStatusSync = status
    }

    private func synchronizeWizardTracker(
        currentStep: StateCoordinator.WizardStep,
        completedSteps: Set<StateCoordinator.WizardStep>
    ) {
        let mappedCurrent = OnboardingWizardStep(rawValue: currentStep.rawValue) ?? .introduction
        let mappedCompleted = Set(
            completedSteps.compactMap { OnboardingWizardStep(rawValue: $0.rawValue) }
        )
        wizardTracker.synchronize(currentStep: mappedCurrent, completedSteps: mappedCompleted)
    }

    // MARK: - Tool Management

    func presentUploadRequest(_ request: OnboardingUploadRequest, continuationId: UUID) {
        toolRouter.presentUploadRequest(request, continuationId: continuationId)
        Task {
            await state.setPendingUpload(request)
        }
    }

    func completeUpload(id: UUID, fileURLs: [URL]) async -> (UUID, JSON)? {
        let result = await toolRouter.completeUpload(id: id, fileURLs: fileURLs)
        Task {
            await state.setPendingUpload(nil)
        }
        return result
    }

    func skipUpload(id: UUID) async -> (UUID, JSON)? {
        let result = await toolRouter.skipUpload(id: id)
        Task {
            await state.setPendingUpload(nil)
        }
        return result
    }

    func presentChoicePrompt(_ prompt: OnboardingChoicePrompt, continuationId: UUID) {
        toolRouter.presentChoicePrompt(prompt, continuationId: continuationId)
        Task {
            await state.setPendingChoice(prompt)
        }
    }

    func submitChoice(optionId: String) -> (UUID, JSON)? {
        let result = toolRouter.promptHandler.resolveChoice(selectionIds: [optionId])
        Task {
            await state.setPendingChoice(nil)
        }
        return result
    }

    func presentValidationPrompt(_ prompt: OnboardingValidationPrompt, continuationId: UUID) {
        toolRouter.presentValidationPrompt(prompt, continuationId: continuationId)
        Task {
            await state.setPendingValidation(prompt)
        }
    }

    func submitValidationResponse(
        status: String,
        updatedData: JSON?,
        changes: JSON?,
        notes: String?
    ) -> (UUID, JSON)? {
        let result = toolRouter.submitValidationResponse(
            status: status,
            updatedData: updatedData,
            changes: changes,
            notes: notes
        )
        Task {
            await state.setPendingValidation(nil)
        }
        return result
    }

    // MARK: - Phase Advance

    func presentPhaseAdvanceRequest(
        _ request: OnboardingPhaseAdvanceRequest,
        continuationId: UUID
    ) {
        Task {
            phaseAdvanceContinuationId = continuationId
            await state.setPendingPhaseAdvanceRequest(request)
            // Emit event to notify UI about the request
            await eventBus.publish(.phaseAdvanceRequested(request: request, continuationId: continuationId))
        }
    }

    func approvePhaseAdvance() async {
        guard let continuationId = phaseAdvanceContinuationId,
              let request = await state.pendingPhaseAdvanceRequest else { return }

        // Perform the actual phase transition
        await requestPhaseTransition(
            from: request.currentPhase.rawValue,
            to: request.nextPhase.rawValue,
            reason: request.reason ?? "User approved phase advance"
        )

        // Wait a moment for the transition to complete
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        // Get the new phase after transition
        let newPhase = await state.phase

        // Clear the request
        await state.setPendingPhaseAdvanceRequest(nil)
        phaseAdvanceContinuationId = nil

        // Resume the tool continuation
        var payload = JSON()
        payload["approved"].boolValue = true
        payload["new_phase"].stringValue = newPhase.rawValue

        await resumeToolContinuation(id: continuationId, payload: payload)
    }

    func denyPhaseAdvance(feedback: String?) async {
        guard let continuationId = phaseAdvanceContinuationId else { return }

        await state.setPendingPhaseAdvanceRequest(nil)
        phaseAdvanceContinuationId = nil

        var payload = JSON()
        payload["approved"].boolValue = false
        if let feedback = feedback {
            payload["feedback"].stringValue = feedback
        }

        await resumeToolContinuation(id: continuationId, payload: payload)
    }

    // MARK: - Tool Execution

    func resumeToolContinuation(from result: (UUID, JSON)?) async {
        guard let (id, payload) = result else { return }
        await resumeToolContinuation(id: id, payload: payload)
    }

    func resumeToolContinuation(
        from result: (UUID, JSON)?,
        waitingState: WaitingStateChange,
        persistCheckpoint: Bool = false
    ) async {
        guard let (id, payload) = result else { return }

        if case .set(let state) = waitingState {
            updateWaitingState(state)
        }

        if persistCheckpoint {
            await saveCheckpoint()
        }

        await resumeToolContinuation(id: id, payload: payload)
    }

    func resumeToolContinuation(id: UUID, payload: JSON) async {
        guard let entry = toolQueueEntries.removeValue(forKey: id) else {
            Logger.warning("No queue entry for continuation \(id)", category: .ai)
            return
        }

        Logger.info("✅ Tool \(entry.toolName) resuming", category: .ai)

        do {
            try await toolExecutionCoordinator.resumeToolContinuation(
                id: id,
                userInput: payload
            )
        } catch {
            Logger.error("Failed to resume tool: \(error)", category: .ai)
        }
    }

    enum WaitingStateChange {
        case keep
        case set(String?)
    }

    // MARK: - Checkpoint Management

    /// Schedule a debounced checkpoint save (Phase 3)
    /// Rapid edits don't spam disk; saves occur 300ms after last change
    private func scheduleCheckpoint() {
        checkpointDebounce?.cancel()
        checkpointDebounce = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce
                guard let self else { return }
                await self.saveCheckpoint()
            } catch {
                // Task was cancelled (new edit came in)
            }
        }
    }

    func saveCheckpoint() async {
        let snapshot = await state.createSnapshot()
        let artifacts = await state.artifacts

        // Save to persistent storage - snapshot is used as-is
        checkpoints.save(
            snapshot: snapshot,
            profileJSON: artifacts.applicantProfile,
            timelineJSON: artifacts.skeletonTimeline,
            enabledSections: artifacts.enabledSections
        )
        Logger.debug("💾 Checkpoint saved", category: .ai)
    }

    func restoreFromCheckpointIfAvailable() async -> Bool {
        guard let checkpoint = checkpoints.restore() else { return false }

        await state.restoreFromSnapshot(checkpoint.snapshot)

        // Restore artifacts from checkpoint
        if let profile = checkpoint.profileJSON {
            await state.setApplicantProfile(profile)
            persistApplicantProfileToSwiftData(json: profile)
        }

        if let timeline = checkpoint.timelineJSON {
            await state.setSkeletonTimeline(timeline)
        }

        if !checkpoint.enabledSections.isEmpty {
            await state.setEnabledSections(checkpoint.enabledSections)
        }

        Logger.info("✅ Restored from checkpoint", category: .ai)
        return true
    }

    func clearCheckpoints() async {
        checkpoints.clear()
    }

    // MARK: - Data Store Management

    func loadPersistedArtifacts() async {
        let profileRecords = (await dataStore.list(dataType: "applicant_profile")).filter { $0 != .null }
        let timelineRecords = (await dataStore.list(dataType: "skeleton_timeline")).filter { $0 != .null }
        let artifactRecords = (await dataStore.list(dataType: "artifact_record")).filter { $0 != .null }

        if let profile = profileRecords.last {
            await state.setApplicantProfile(profile)
            persistApplicantProfileToSwiftData(json: profile)
        }

        if let timeline = timelineRecords.last {
            await state.setSkeletonTimeline(timeline)
        }

        if !artifactRecords.isEmpty {
            await state.setArtifactRecords(artifactRecords)
        }

        if profileRecords.isEmpty && timelineRecords.isEmpty && artifactRecords.isEmpty {
            Logger.info("📂 No persisted artifacts discovered", category: .ai)
        } else {
            Logger.info(
                "📂 Loaded persisted artifacts",
                category: .ai,
                metadata: [
                    "applicant_profile_count": "\(profileRecords.count)",
                    "skeleton_timeline_count": "\(timelineRecords.count)",
                    "artifact_record_count": "\(artifactRecords.count)"
                ]
            )
        }
    }

    func clearArtifacts() {
        Task {
            await dataStore.reset()
        }
    }

    func resetStore() async {
        await state.reset()
        chatTranscriptStore.reset()
        toolRouter.reset()
        wizardTracker.reset()
    }

    // MARK: - Persistence Helpers

    @MainActor
    private func persistApplicantProfileToSwiftData(json: JSON) {
        let draft = ApplicantProfileDraft(json: json)
        let profile = applicantProfileStore.currentProfile()
        draft.apply(to: profile, replaceMissing: false)
        applicantProfileStore.save(profile)
        Logger.info("💾 Applicant profile persisted to SwiftData", category: .ai)
    }

    // MARK: - Orchestrator Factory

    private func makeOrchestrator(
        service: OpenAIService,
        systemPrompt: String
    ) -> InterviewOrchestrator {
        return InterviewOrchestrator(
            service: service,
            systemPrompt: systemPrompt,
            eventBus: eventBus,
            toolRegistry: toolRegistry,
            state: state
        )
    }

    // MARK: - Tool Processing

    private func processToolCall(_ call: ToolCall) async -> JSON? {
        let tokenId = UUID()

        toolQueueEntries[tokenId] = ToolQueueEntry(
            tokenId: tokenId,
            callId: call.callId,
            toolName: call.name,
            status: "processing",
            requestedInput: call.arguments.rawString() ?? "{}",
            enqueuedAt: Date()
        )

        // Process the tool call through the executor
        // This will be expanded in Phase 2
        return nil
    }

    // MARK: - Utility

    func notifyInvalidModel(id: String) {
        Logger.warning("⚠️ Invalid model id reported: \(id)", category: .ai)
        modelAvailabilityMessage = "Your selected model (\(id)) is not available. Choose another model in Settings."
        onModelAvailabilityIssue?(id)
    }

    func clearModelAvailabilityMessage() {
        modelAvailabilityMessage = nil
    }

    func transcriptExportString() -> String {
        chatTranscriptStore.formattedTranscript()
    }

    func buildSystemPrompt(for phase: InterviewPhase) -> String {
        phaseRegistry.buildSystemPrompt(for: phase)
    }
}
