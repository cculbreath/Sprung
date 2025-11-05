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

    // MARK: - Core Controllers (Decomposed Components)

    private let lifecycleController: InterviewLifecycleController
    private let checkpointManager: CheckpointManager
    private let phaseTransitionController: PhaseTransitionController
    private let continuationTracker: ContinuationTracker

    // MARK: - Data Store Dependencies

    private let applicantProfileStore: ApplicantProfileStore
    private let dataStore: InterviewDataStore
    let checkpoints: Checkpoints

    // MARK: - Orchestration State (minimal, not business state)

    private var orchestrator: InterviewOrchestrator?
    private var phaseAdvanceContinuationId: UUID?
    private var pendingExtractionProgressBuffer: [ExtractionProgressUpdate] = []
    private var reasoningSummaryClearTask: Task<Void, Never>?
    var onModelAvailabilityIssue: ((String) -> Void)?
    private(set) var preferences: OnboardingPreferences
    private(set) var modelAvailabilityMessage: String?

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

    func requestCancelLLM() async {
        await eventBus.publish(.llmCancelRequested)
    }

    // Properties that need synchronous access for SwiftUI
    // These will be updated via observation when state changes
    @ObservationIgnored
    private var _isProcessingSync = false
    var isProcessingSync: Bool { _isProcessingSync }

    @ObservationIgnored
    private var _isActiveSync = false
    var isActiveSync: Bool { _isActiveSync }

    @ObservationIgnored
    private var _pendingExtractionSync: OnboardingPendingExtraction?
    var pendingExtractionSync: OnboardingPendingExtraction? { _pendingExtractionSync }

    @ObservationIgnored
    private var _pendingStreamingStatusSync: String?
    var pendingStreamingStatusSync: String? { _pendingStreamingStatusSync }

    @ObservationIgnored
    private var _artifactRecordsSync: [JSON] = []
    var artifactRecordsSync: [JSON] { _artifactRecordsSync }

    @ObservationIgnored
    private var _pendingPhaseAdvanceRequestSync: OnboardingPhaseAdvanceRequest?
    var pendingPhaseAdvanceRequestSync: OnboardingPhaseAdvanceRequest? { _pendingPhaseAdvanceRequestSync }

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
            transcriptStore: chatTranscriptStore,
            state: state
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

        // Initialize core controllers
        self.lifecycleController = InterviewLifecycleController(
            state: state,
            eventBus: eventBus,
            phaseRegistry: registry,
            chatboxHandler: chatboxHandler,
            toolExecutionCoordinator: toolExecutionCoordinator,
            toolRouter: toolRouter,
            openAIService: openAIService,
            toolRegistry: toolRegistry,
            dataStore: dataStore
        )

        self.checkpointManager = CheckpointManager(
            state: state,
            checkpoints: checkpoints,
            applicantProfileStore: applicantProfileStore
        )

        self.phaseTransitionController = PhaseTransitionController(
            state: state,
            eventBus: eventBus,
            phaseRegistry: registry
        )

        self.continuationTracker = ContinuationTracker(
            toolExecutionCoordinator: toolExecutionCoordinator
        )

        // Wire up lifecycle controller to phase transition controller
        phaseTransitionController.setLifecycleController(lifecycleController)

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

        Logger.info("✅ Registered \(toolRegistry.allTools().count) tools", category: .ai)
    }

    // MARK: - Event Subscription

    private func subscribeToEvents() async {
        // Delegate to lifecycle controller
        lifecycleController.subscribeToEvents { [weak self] event in
            await self?.handleEvent(event)
        }
    }

    private func handleEvent(_ event: OnboardingEvent) async {
        // Schedule checkpoint for significant events (delegated to CheckpointManager)
        switch event {
        case .objectiveStatusChanged, .timelineCardCreated, .timelineCardUpdated,
             .timelineCardDeleted, .timelineCardsReordered, .skeletonTimelineReplaced,
             .artifactRecordPersisted, .phaseTransitionApplied:
            checkpointManager.scheduleCheckpoint()
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

        case .waitingStateChanged:
            // Event now handled by StateCoordinator
            break

        case .errorOccurred(let error):
            Logger.error("Interview error: \(error)", category: .ai)

        case .applicantProfileStored(let json):
            // Event now handled by StateCoordinator - persist to SwiftData
            await MainActor.run {
                self.persistApplicantProfileToSwiftData(json: json)
            }
            await checkpointManager.saveCheckpoint()

        case .skeletonTimelineStored, .enabledSectionsUpdated:
            // Events now handled by StateCoordinator - just checkpoint
            await checkpointManager.saveCheckpoint()

        case .checkpointRequested:
            await checkpointManager.saveCheckpoint()

        case .toolCallRequested:
            // Tool execution now handled by ToolExecutionCoordinator
            break

        case .toolCallCompleted:
            // Tool completion is handled by toolContinuationNeeded
            break

        case .toolContinuationNeeded:
            // Tool continuation managed by ToolExecutionCoordinator
            break

        case .objectiveStatusRequested(let id, let response):
            let status = await state.getObjectiveStatus(id)?.rawValue
            response(status)

        case .phaseAdvanceRequested:
            // Handled by state sync - trigger sync of pendingPhaseAdvanceRequest
            break

        // Tool UI events - handled by ToolHandler
        case .choicePromptRequested, .choicePromptCleared,
             .uploadRequestPresented, .uploadRequestCancelled,
             .validationPromptRequested, .validationPromptCleared,
             .applicantProfileIntakeRequested, .applicantProfileIntakeCleared,
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
            // Update the system prompt when phase transitions (delegated to PhaseTransitionController)
            await phaseTransitionController.handlePhaseTransition(phaseName)

        @unknown default:
            // Handle any new cases that might be added in the future
            break
        }
    }

    // MARK: - State Updates

    private func subscribeToStateUpdates() {
        // Delegate to lifecycle controller
        let handlers = StateUpdateHandlers(
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
        lifecycleController.subscribeToStateUpdates(handlers)
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
        case .artifactNewRequested, .artifactAdded, .artifactUpdated, .artifactDeleted,
             .artifactRecordProduced, .artifactRecordPersisted:
            await syncPendingExtractionFromState()
            await syncWizardProgressFromState()
            await syncArtifactRecordsFromState()

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

        case .phaseAdvanceRequested:
            await syncPendingPhaseAdvanceRequestFromState()

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

    private func syncArtifactRecordsFromState() async {
        _artifactRecordsSync = await state.artifacts.artifactRecords
    }

    private func syncPendingPhaseAdvanceRequestFromState() async {
        _pendingPhaseAdvanceRequestSync = await state.pendingPhaseAdvanceRequest
    }

    private func initialStateSync() async {
        _isProcessingSync = await state.isProcessing
        _isActiveSync = await state.isActive
        await syncPendingExtractionFromState()
        _pendingStreamingStatusSync = await state.pendingStreamingStatus
        await syncWizardProgressFromState()
        await syncArtifactRecordsFromState()
        await syncPendingPhaseAdvanceRequestFromState()
    }

    // MARK: - Interview Lifecycle

    func startInterview(resumeExisting: Bool = false) async -> Bool {
        Logger.info("🚀 Starting interview (resume: \(resumeExisting))", category: .ai)

        // Reset or restore state
        if resumeExisting {
            await loadPersistedArtifacts()
            let didRestore = await checkpointManager.restoreFromCheckpointIfAvailable()
            if !didRestore {
                await state.reset()
                checkpointManager.clearCheckpoints()
                clearArtifacts()
                await resetStore()
            }
        } else {
            await state.reset()
            checkpointManager.clearCheckpoints()
            clearArtifacts()
            await resetStore()
        }

        await phaseTransitionController.registerObjectivesForCurrentPhase()

        // Start interview through lifecycle controller
        let success = await lifecycleController.startInterview()
        if success {
            subscribeToStateUpdates()
            // Get the orchestrator created by lifecycleController
            self.orchestrator = lifecycleController.orchestrator
            // Update sync cache for isActive
            _isActiveSync = true
        }

        // Set model ID from preferences or ModelProvider default
        if let orchestrator = self.orchestrator {
            let cfg = ModelProvider.forTask(.orchestrator)
            await orchestrator.setModelId(preferences.preferredModelId ?? cfg.id)
        }

        // Start event subscriptions for handlers
        await chatboxHandler.startEventSubscriptions()
        await toolExecutionCoordinator.startEventSubscriptions()
        await state.startEventSubscriptions()
        subscribeToStateUpdates()
        await MainActor.run {
            toolRouter.startEventSubscriptions()
        }
        await state.publishAllowedToolsNow()

        // Workflow engine is managed by lifecycle controller

        // Start the orchestrator interview
        Task {
            do {
                if let orchestrator = self.orchestrator {
                    try await orchestrator.startInterview()
                }
            } catch {
                Logger.error("Interview failed: \(error)", category: .ai)
                await endInterview()
            }
        }

        return true
    }

    func endInterview() async {
        // Delegate to lifecycle controller
        await lifecycleController.endInterview()
        // Update sync cache for isActive
        _isActiveSync = false
    }

    // MARK: - Phase Management

    func advancePhase() async -> InterviewPhase? {
        let newPhase = await phaseTransitionController.advancePhase()

        // Update wizard progress
        let completedSteps = await state.completedWizardSteps
        let currentStep = await state.currentWizardStep
        synchronizeWizardTracker(currentStep: currentStep, completedSteps: completedSteps)

        return newPhase
    }

    func getCompletedObjectiveIds() async -> Set<String> {
        await phaseTransitionController.getCompletedObjectiveIds()
    }

    // MARK: - Objective Management

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
        await phaseTransitionController.requestPhaseTransition(from: from, to: to, reason: reason)
    }

    func missingObjectives() async -> [String] {
        await phaseTransitionController.missingObjectives()
    }

    // MARK: - Artifact Queries (Read-Only State Access)

    func listArtifactSummaries() async -> [JSON] {
        await state.listArtifactSummaries()
    }

    func listArtifactRecords() async -> [JSON] {
        await state.artifacts.artifactRecords
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
        await phaseTransitionController.nextPhase()
    }

    // MARK: - Artifact Management
    // Note: Artifact state mutations now happen via events in StateCoordinator
    // The coordinator only handles side effects like SwiftData persistence

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
    // Note: Waiting state mutations now happen via events in StateCoordinator

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
            await eventBus.publish(.uploadRequestPresented(request: request, continuationId: continuationId))
        }
    }

    func completeUpload(id: UUID, fileURLs: [URL]) async -> (UUID, JSON)? {
        let result = await toolRouter.completeUpload(id: id, fileURLs: fileURLs)
        Task {
            await eventBus.publish(.uploadRequestCancelled(id: id))
        }
        return result
    }

    func skipUpload(id: UUID) async -> (UUID, JSON)? {
        let result = await toolRouter.skipUpload(id: id)
        Task {
            await eventBus.publish(.uploadRequestCancelled(id: id))
        }
        return result
    }

    func presentChoicePrompt(_ prompt: OnboardingChoicePrompt, continuationId: UUID) {
        toolRouter.presentChoicePrompt(prompt, continuationId: continuationId)
        Task {
            await eventBus.publish(.choicePromptRequested(prompt: prompt, continuationId: continuationId))
        }
    }

    func submitChoice(optionId: String) -> (UUID, JSON)? {
        let result = toolRouter.promptHandler.resolveChoice(selectionIds: [optionId])
        if let (continuationId, _) = result {
            Task {
                await eventBus.publish(.choicePromptCleared(continuationId: continuationId))
            }
        }
        return result
    }

    func presentValidationPrompt(_ prompt: OnboardingValidationPrompt, continuationId: UUID) {
        toolRouter.presentValidationPrompt(prompt, continuationId: continuationId)
        Task {
            await eventBus.publish(.validationPromptRequested(prompt: prompt, continuationId: continuationId))
        }
    }

    func submitValidationResponse(
        status: String,
        updatedData: JSON?,
        changes: JSON?,
        notes: String?
    ) -> (UUID, JSON)? {
        // Get pending validation before clearing it
        let pendingValidation = pendingValidationPrompt

        let result = toolRouter.submitValidationResponse(
            status: status,
            updatedData: updatedData,
            changes: changes,
            notes: notes
        )
        if let (continuationId, _) = result {
            Task {
                await eventBus.publish(.validationPromptCleared(continuationId: continuationId))
            }
        }
        return result
    }

    // MARK: - Phase Advance

    func presentPhaseAdvanceRequest(
        _ request: OnboardingPhaseAdvanceRequest,
        continuationId: UUID
    ) {
        Task {
            continuationTracker.trackPhaseAdvanceContinuation(id: continuationId)
            await state.setPendingPhaseAdvanceRequest(request)
            // Emit event to notify UI about the request
            await eventBus.publish(.phaseAdvanceRequested(request: request, continuationId: continuationId))
        }
    }

    func approvePhaseAdvance() async {
        guard let continuationId = continuationTracker.getPhaseAdvanceContinuationId(),
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
        _pendingPhaseAdvanceRequestSync = nil
        continuationTracker.clearPhaseAdvanceContinuation()

        // Resume the tool continuation
        var payload = JSON()
        payload["approved"].boolValue = true
        payload["new_phase"].stringValue = newPhase.rawValue

        await continuationTracker.resumeToolContinuation(id: continuationId, payload: payload)
    }

    func denyPhaseAdvance(feedback: String?) async {
        guard let continuationId = continuationTracker.getPhaseAdvanceContinuationId() else { return }

        await state.setPendingPhaseAdvanceRequest(nil)
        _pendingPhaseAdvanceRequestSync = nil
        continuationTracker.clearPhaseAdvanceContinuation()

        var payload = JSON()
        payload["approved"].boolValue = false
        if let feedback = feedback {
            payload["feedback"].stringValue = feedback
        }

        await continuationTracker.resumeToolContinuation(id: continuationId, payload: payload)
    }

    // MARK: - Tool Execution

    func resumeToolContinuation(from result: (UUID, JSON)?) async {
        await continuationTracker.resumeToolContinuation(from: result)
    }

    func resumeToolContinuation(
        from result: (UUID, JSON)?,
        waitingState: WaitingStateChange,
        persistCheckpoint: Bool = false
    ) async {
        guard let (id, payload) = result else { return }

        if case .set(let state) = waitingState {
            // Publish event instead of direct mutation
            await eventBus.publish(.waitingStateChanged(state))
        }

        if persistCheckpoint {
            await checkpointManager.saveCheckpoint()
        }

        await continuationTracker.resumeToolContinuation(id: id, payload: payload)
    }

    func resumeToolContinuation(id: UUID, payload: JSON) async {
        do {
            try await toolExecutionCoordinator.resumeToolContinuation(
                id: id,
                userInput: payload
            )
        } catch {
            Logger.error("Failed to resume tool continuation \(id): \(error)", category: .ai)
        }
    }

    enum WaitingStateChange {
        case keep
        case set(String?)
    }

    // MARK: - Checkpoint Management (Delegated to CheckpointManager)
    // No methods needed here - all delegated to checkpointManager

    // MARK: - Data Store Management

    func loadPersistedArtifacts() async {
        let profileRecords = (await dataStore.list(dataType: "applicant_profile")).filter { $0 != .null }
        let timelineRecords = (await dataStore.list(dataType: "skeleton_timeline")).filter { $0 != .null }
        let artifactRecords = (await dataStore.list(dataType: "artifact_record")).filter { $0 != .null }
        let knowledgeCardRecords = (await dataStore.list(dataType: "knowledge_card")).filter { $0 != .null }

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

        if !knowledgeCardRecords.isEmpty {
            await state.setKnowledgeCards(knowledgeCardRecords)
        }

        if profileRecords.isEmpty && timelineRecords.isEmpty && artifactRecords.isEmpty && knowledgeCardRecords.isEmpty {
            Logger.info("📂 No persisted artifacts discovered", category: .ai)
        } else {
            Logger.info(
                "📂 Loaded persisted artifacts",
                category: .ai,
                metadata: [
                    "applicant_profile_count": "\(profileRecords.count)",
                    "skeleton_timeline_count": "\(timelineRecords.count)",
                    "artifact_record_count": "\(artifactRecords.count)",
                    "knowledge_card_count": "\(knowledgeCardRecords.count)"
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
        phaseTransitionController.buildSystemPrompt(for: phase)
    }
}
