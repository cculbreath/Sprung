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
    let eventBus: EventCoordinator
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

    // MARK: - Services (Phase 3 Decomposition)

    private let extractionManagementService: ExtractionManagementService
    private let timelineManagementService: TimelineManagementService
    private let dataPersistenceService: DataPersistenceService

    // MARK: - Data Store Dependencies

    private let applicantProfileStore: ApplicantProfileStore
    private let dataStore: InterviewDataStore
    let checkpoints: Checkpoints

    // MARK: - Document Processing

    private let uploadStorage: OnboardingUploadStorage
    private let documentProcessingService: DocumentProcessingService
    private let documentArtifactHandler: DocumentArtifactHandler
    private let documentArtifactMessenger: DocumentArtifactMessenger

    // MARK: - Orchestration State (minimal, not business state)

    private var orchestrator: InterviewOrchestrator?
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

    /// Returns the current ApplicantProfile from SwiftData storage
    func currentApplicantProfile() -> ApplicantProfile {
        applicantProfileStore.currentProfile()
    }

    var skeletonTimelineJSON: JSON? {
        get async { await state.artifacts.skeletonTimeline }
    }

    var artifacts: StateCoordinator.OnboardingArtifacts {
        get async { await state.artifacts }
    }

    // MARK: - Chat Messages

    private(set) var messages: [OnboardingMessage] = []

    // MARK: - Processing State

    private(set) var isProcessingSync: Bool = false

    func sendChatMessage(_ text: String) async {
        await chatboxHandler.sendUserMessage(text)
    }

    func requestCancelLLM() async {
        await eventBus.publish(.llmCancelRequested)
    }

    // MARK: - Synchronous Cache Properties (Read from StateCoordinator)

    /// Sync cache access for SwiftUI views
    /// StateCoordinator is the single source of truth with nonisolated(unsafe) sync caches
    var isActiveSync: Bool { state.isActiveSync }
    var pendingExtractionSync: OnboardingPendingExtraction? { state.pendingExtractionSync }
    var pendingStreamingStatusSync: String? { state.pendingStreamingStatusSync }
    var artifactRecordsSync: [JSON] { state.artifactRecordsSync }
    var pendingPhaseAdvanceRequestSync: OnboardingPhaseAdvanceRequest? { state.pendingPhaseAdvanceRequestSync }

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

    var pendingApplicantProfileSummary: JSON? {
        toolRouter.pendingApplicantProfileSummary
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

        // Create domain service actors
        let objectiveStore = ObjectiveStore(eventBus: eventBus, phasePolicy: phasePolicy, initialPhase: .phase1CoreFacts)
        let artifactRepository = ArtifactRepository(eventBus: eventBus)
        let chatTranscriptStore = ChatTranscriptStore(eventBus: eventBus)
        let sessionUIState = SessionUIState(eventBus: eventBus, phasePolicy: phasePolicy, initialPhase: .phase1CoreFacts)

        // Create StateCoordinator with injected services
        self.state = StateCoordinator(
            eventBus: eventBus,
            phasePolicy: phasePolicy,
            objectives: objectiveStore,
            artifacts: artifactRepository,
            chat: chatTranscriptStore,
            uiState: sessionUIState
        )
        self.openAIService = openAIService
        self.documentExtractionService = documentExtractionService
        self.knowledgeCardAgent = openAIService.map { KnowledgeCardAgent(client: $0) }
        self.applicantProfileStore = applicantProfileStore
        self.dataStore = dataStore
        self.checkpoints = checkpoints
        self.preferences = preferences

        // Initialize upload storage (shared across handlers)
        self.uploadStorage = OnboardingUploadStorage()

        // Initialize document processing service
        self.documentProcessingService = DocumentProcessingService(
            documentExtractionService: documentExtractionService,
            uploadStorage: self.uploadStorage,
            dataStore: dataStore
        )

        // Initialize document processing handlers
        self.documentArtifactHandler = DocumentArtifactHandler(
            eventBus: eventBus,
            documentProcessingService: self.documentProcessingService
        )

        self.documentArtifactMessenger = DocumentArtifactMessenger(eventBus: eventBus)

        self.chatboxHandler = ChatboxHandler(
            eventBus: eventBus,
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

        let uploadFileService = UploadFileService()
        let uploadHandler = UploadInteractionHandler(
            uploadFileService: uploadFileService,
            uploadStorage: self.uploadStorage,
            applicantProfileStore: applicantProfileStore,
            dataStore: dataStore,
            eventBus: eventBus,
            extractionProgressHandler: nil
        )

        let contactsImportService = ContactsImportService()
        let profileHandler = ProfileInteractionHandler(
            contactsImportService: contactsImportService,
            eventBus: eventBus
        )

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
            eventBus: eventBus,
            checkpoints: checkpoints,
            applicantProfileStore: applicantProfileStore
        )

        self.phaseTransitionController = PhaseTransitionController(
            state: state,
            eventBus: eventBus,
            phaseRegistry: registry
        )

        // Initialize services (Phase 3)
        self.extractionManagementService = ExtractionManagementService(
            eventBus: eventBus,
            state: state,
            toolRouter: toolRouter,
            wizardTracker: wizardTracker
        )

        self.timelineManagementService = TimelineManagementService(
            eventBus: eventBus,
            phaseTransitionController: phaseTransitionController
        )

        self.dataPersistenceService = DataPersistenceService(
            eventBus: eventBus,
            state: state,
            dataStore: dataStore,
            applicantProfileStore: applicantProfileStore,
            toolRouter: toolRouter,
            wizardTracker: wizardTracker
        )

        // Wire up lifecycle controller to phase transition controller
        phaseTransitionController.setLifecycleController(lifecycleController)

        toolRouter.uploadHandler.updateExtractionProgressHandler { [weak self] update in
            Task { @MainActor in
                guard let self else { return }
                self.extractionManagementService.updateExtractionProgress(with: update)
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
        toolRegistry.register(CreateTimelineCardTool(coordinator: self))
        toolRegistry.register(UpdateTimelineCardTool(coordinator: self))
        toolRegistry.register(DeleteTimelineCardTool(coordinator: self))
        toolRegistry.register(ReorderTimelineCardsTool(coordinator: self))
        toolRegistry.register(DisplayTimelineForReviewTool(coordinator: self))
        toolRegistry.register(SubmitForValidationTool(coordinator: self))
        toolRegistry.register(ListArtifactsTool(coordinator: self))
        toolRegistry.register(GetArtifactRecordTool(coordinator: self))
        toolRegistry.register(RequestRawArtifactFileTool(coordinator: self))
        toolRegistry.register(UpdateArtifactMetadataTool(coordinator: self))
        toolRegistry.register(PersistDataTool(dataStore: dataStore, eventBus: eventBus))
        toolRegistry.register(SetObjectiveStatusTool(coordinator: self))
        toolRegistry.register(NextPhaseTool(coordinator: self))
        toolRegistry.register(ValidateApplicantProfileTool(coordinator: self))
        toolRegistry.register(GetValidatedApplicantProfileTool(coordinator: self))
        toolRegistry.register(ConfigureEnabledSectionsTool(coordinator: self))
        toolRegistry.register(AgentReadyTool())

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
        case .objectiveStatusChanged(let id, _, let newStatus, _, _, _, _):
            checkpointManager.scheduleCheckpoint()

            // Dismiss profile summary when moving to skeleton_timeline
            if id == "applicant_profile" && newStatus == "completed" {
                await MainActor.run {
                    toolRouter.profileHandler.dismissProfileSummary()
                }
            }

        case .timelineCardCreated, .timelineCardUpdated,
             .timelineCardDeleted, .timelineCardsReordered, .skeletonTimelineReplaced,
             .artifactRecordPersisted, .phaseTransitionApplied:
            checkpointManager.scheduleCheckpoint()
        default:
            break
        }

        switch event {
        case .processingStateChanged:
            // Event now handled by StateCoordinator
            break

        case .streamingMessageBegan, .streamingMessageUpdated, .streamingMessageFinalized:
            // Event now handled by StateCoordinator - ChatboxHandler mirrors to transcript
            break

        case .llmReasoningSummaryDelta, .llmReasoningSummaryComplete:
            // Event now handled by StateCoordinator - sidebar reasoning display
            break

        case .streamingStatusUpdated:
            // Event now handled by StateCoordinator - StateCoordinator maintains sync cache
            break

        case .waitingStateChanged:
            // Event now handled by StateCoordinator
            break

        case .errorOccurred(let error):
            Logger.error("Interview error: \(error)", category: .ai)

        case .applicantProfileStored(let json):
            // Event now handled by StateCoordinator - persist to SwiftData
            await MainActor.run {
                let draft = ApplicantProfileDraft(json: json)
                let profile = self.applicantProfileStore.currentProfile()
                draft.apply(to: profile, replaceMissing: false)
                self.applicantProfileStore.save(profile)
                Logger.info("💾 Applicant profile persisted to SwiftData", category: .ai)

                // Update summary card if showing (e.g., when photo is added)
                // Regenerate JSON from SwiftData model to include any new image data
                if toolRouter.profileHandler.pendingApplicantProfileSummary != nil {
                    let updatedDraft = ApplicantProfileDraft(profile: profile)
                    let updatedJSON = updatedDraft.toSafeJSON()
                    toolRouter.profileHandler.updateProfileSummary(profile: updatedJSON)
                }
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

        case .objectiveStatusRequested(let id, let response):
            let status = await state.getObjectiveStatus(id)?.rawValue
            response(status)

        case .phaseAdvanceRequested:
            // Handled by state sync - trigger sync of pendingPhaseAdvanceRequest
            break

        case .phaseAdvanceDismissed:
            // User dismissed phase advance request
            break

        case .phaseAdvanceApproved, .phaseAdvanceDenied:
            // Phase advance approval/denial now handled by event handlers (step 6)
            break

        // Tool UI events - handled by ToolHandler
        case .choicePromptRequested, .choicePromptCleared,
             .uploadRequestPresented, .uploadRequestCancelled,
             .validationPromptRequested, .validationPromptCleared,
             .applicantProfileIntakeRequested, .applicantProfileIntakeCleared,
             .timelineCardCreated, .timelineCardDeleted, .timelineCardsReordered,
             .artifactGetRequested, .artifactNewRequested, .artifactAdded, .artifactUpdated, .artifactDeleted,
             .artifactRecordProduced, .artifactRecordPersisted, .artifactRecordsReplaced,
             .knowledgeCardPersisted, .knowledgeCardsReplaced,
             // Upload completion - handled by document processing handlers
             .uploadCompleted,
             // New spec-aligned events that StateCoordinator handles
             .objectiveStatusChanged, .objectiveStatusUpdateRequested,
             .stateSnapshot, .stateAllowedToolsUpdated,
             .llmUserMessageSent, .llmDeveloperMessageSent, .llmSentToolResponseMessage,
             .llmSendUserMessage, .llmSendDeveloperMessage, .llmToolResponseMessage, .llmStatus,
             .phaseTransitionRequested, .timelineCardUpdated:
            // These events are handled by StateCoordinator/handlers, not the coordinator
            break

        case .phaseTransitionApplied(let phaseName, _):
            // Update the system prompt when phase transitions (delegated to PhaseTransitionController)
            await phaseTransitionController.handlePhaseTransition(phaseName)

        case .profileSummaryUpdateRequested, .profileSummaryDismissRequested,
             .sectionToggleRequested, .sectionToggleCleared,
             .artifactMetadataUpdated,
             .llmReasoningItemsForToolCalls,
             .pendingExtractionUpdated,
             .llmEnqueueUserMessage, .llmEnqueueToolResponse,
             .llmExecuteUserMessage, .llmExecuteToolResponse,
             .llmCancelRequested,
             .chatboxUserMessageAdded,
             .skeletonTimelineReplaced:
            // These events are handled by StateCoordinator/handlers
            break

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
        case .processingStateChanged(let isProcessing):
            // Sync processing state for UI reactivity
            self.isProcessingSync = isProcessing
            Logger.info("🎨 UI Update: Chat glow/spinner \(isProcessing ? "ACTIVATED ✨" : "DEACTIVATED") - isProcessingSync=\(isProcessing)", category: .ai)
            await syncWizardProgressFromState()

        case .streamingStatusUpdated:
            // Sync cache now maintained by StateCoordinator
            break

        case .waitingStateChanged:
            // Sync cache now maintained by StateCoordinator
            break

        default:
            break
        }
    }

    private func handleArtifactEvent(_ event: OnboardingEvent) async {
        switch event {
        case .artifactNewRequested, .artifactAdded, .artifactUpdated, .artifactDeleted,
             .artifactRecordProduced, .artifactRecordPersisted, .artifactRecordsReplaced,
             .knowledgeCardPersisted, .knowledgeCardsReplaced:
            // Sync caches now maintained by StateCoordinator
            await syncWizardProgressFromState()

        default:
            break
        }
    }

    private func handleLLMEvent(_ event: OnboardingEvent) async {
        switch event {
        case .llmStatus:
            // Sync cache now maintained by StateCoordinator
            break

        case .chatboxUserMessageAdded:
            // User message added to transcript by ChatboxHandler - sync immediately
            messages = await state.messages

        case .streamingMessageBegan, .streamingMessageUpdated, .streamingMessageFinalized,
             .llmUserMessageSent:
            // Sync messages from StateCoordinator to trigger UI updates
            messages = await state.messages

        default:
            break
        }
    }

    private func handleStateSyncEvent(_ event: OnboardingEvent) async {
        switch event {
        case .stateSnapshot, .stateAllowedToolsUpdated:
            // Sync caches now maintained by StateCoordinator
            await syncWizardProgressFromState()

        case .phaseAdvanceRequested:
            // Sync cache now maintained by StateCoordinator
            break

        default:
            break
        }
    }

    private func syncWizardProgressFromState() async {
        let step = await state.currentWizardStep
        let completed = await state.completedWizardSteps
        synchronizeWizardTracker(currentStep: step, completedSteps: completed)
    }

    private func initialStateSync() async {
        // Sync caches now maintained by StateCoordinator
        await syncWizardProgressFromState()
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

        // Re-initialize phase to register objectives and update wizard step
        // reset() sets phase directly without calling setPhase(), so we need to do it here
        await state.setPhase(.phase1CoreFacts)

        await phaseTransitionController.registerObjectivesForCurrentPhase()

        // Subscribe to state updates BEFORE starting interview
        // This ensures we receive the initial processingStateChanged(true) event
        subscribeToStateUpdates()

        // Start document processing handlers
        await documentArtifactHandler.start()
        await documentArtifactMessenger.start()

        // Start interview through lifecycle controller
        let success = await lifecycleController.startInterview()
        if success {
            // Get the orchestrator created by lifecycleController
            self.orchestrator = lifecycleController.orchestrator
            // StateCoordinator maintains sync cache for isActive
        }

        // Set model ID from preferences or ModelProvider default
        if let orchestrator = self.orchestrator {
            let cfg = ModelProvider.forTask(.orchestrator)
            await orchestrator.setModelId(preferences.preferredModelId ?? cfg.id)
        }

        return true
    }

    func endInterview() async {
        // Delegate to lifecycle controller
        await lifecycleController.endInterview()
        // StateCoordinator maintains sync cache for isActive
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

    func updateObjectiveStatus(
        objectiveId: String,
        status: String,
        notes: String? = nil,
        details: [String: String]? = nil
    ) async throws -> JSON {
        // Emit event to update objective status
        await eventBus.publish(.objectiveStatusUpdateRequested(
            id: objectiveId,
            status: status.lowercased(),
            source: "tool",
            notes: notes,
            details: details
        ))

        var result = JSON()
        result["status"].string = "completed"
        result["success"].boolValue = true
        result["objective_id"].stringValue = objectiveId
        result["new_status"].stringValue = status.lowercased()

        return result
    }

    // MARK: - Timeline Management (Delegated to TimelineManagementService)

    func applyUserTimelineUpdate(cards: [TimelineCard], meta: JSON?, diff: TimelineDiff) async {
        await timelineManagementService.applyUserTimelineUpdate(cards: cards, meta: meta, diff: diff)
    }

    func createTimelineCard(fields: JSON) async -> JSON {
        await timelineManagementService.createTimelineCard(fields: fields)
    }

    func updateTimelineCard(id: String, fields: JSON) async -> JSON {
        await timelineManagementService.updateTimelineCard(id: id, fields: fields)
    }

    func deleteTimelineCard(id: String) async -> JSON {
        await timelineManagementService.deleteTimelineCard(id: id)
    }

    func reorderTimelineCards(orderedIds: [String]) async -> JSON {
        await timelineManagementService.reorderTimelineCards(orderedIds: orderedIds)
    }

    func requestPhaseTransition(from: String, to: String, reason: String?) async {
        await timelineManagementService.requestPhaseTransition(from: from, to: to, reason: reason)
    }

    func missingObjectives() async -> [String] {
        await timelineManagementService.missingObjectives()
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

    func requestArtifactMetadataUpdate(artifactId: String, updates: JSON) async {
        await eventBus.publish(.artifactMetadataUpdateRequested(artifactId: artifactId, updates: updates))
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

    // MARK: - Waiting State
    // Note: Waiting state mutations now happen via events in StateCoordinator

    // MARK: - Extraction Management (Delegated to ExtractionManagementService)

    func setExtractionStatus(_ extraction: OnboardingPendingExtraction?) {
        extractionManagementService.setExtractionStatus(extraction)
    }

    func updateExtractionProgress(with update: ExtractionProgressUpdate) {
        extractionManagementService.updateExtractionProgress(with: update)
    }

    func setStreamingStatus(_ status: String?) async {
        await extractionManagementService.setStreamingStatus(status)
    }

    private func synchronizeWizardTracker(
        currentStep: StateCoordinator.WizardStep,
        completedSteps: Set<StateCoordinator.WizardStep>
    ) {
        extractionManagementService.synchronizeWizardTracker(
            currentStep: currentStep,
            completedSteps: completedSteps
        )
    }

    // MARK: - Tool Management

    func presentUploadRequest(_ request: OnboardingUploadRequest) {
        Task {
            await eventBus.publish(.uploadRequestPresented(request: request))
        }
    }

    func completeUpload(id: UUID, fileURLs: [URL]) async -> JSON? {
        let result = await toolRouter.completeUpload(id: id, fileURLs: fileURLs)
        Task {
            await eventBus.publish(.uploadRequestCancelled(id: id))
        }
        return result
    }

    func skipUpload(id: UUID) async -> JSON? {
        let result = await toolRouter.skipUpload(id: id)
        Task {
            await eventBus.publish(.uploadRequestCancelled(id: id))
        }
        return result
    }

    func presentChoicePrompt(_ prompt: OnboardingChoicePrompt) {
        Task {
            await eventBus.publish(.choicePromptRequested(prompt: prompt))
        }
    }

    func submitChoice(optionId: String) -> JSON? {
        let result = toolRouter.promptHandler.resolveChoice(selectionIds: [optionId])
        if result != nil {
            Task {
                await eventBus.publish(.choicePromptCleared)
            }
        }
        return result
    }

    func presentValidationPrompt(_ prompt: OnboardingValidationPrompt) {
        Task {
            await eventBus.publish(.validationPromptRequested(prompt: prompt))
        }
    }

    func submitValidationResponse(
        status: String,
        updatedData: JSON?,
        changes: JSON?,
        notes: String?
    ) -> JSON? {
        // Get pending validation before clearing it
        let pendingValidation = pendingValidationPrompt

        if let validation = pendingValidation,
           validation.dataType == "knowledge_card",
           let data = updatedData,
           data != .null,
           ["approved", "modified"].contains(status.lowercased()) {
            Task {
                do {
                    _ = try await dataStore.persist(dataType: "knowledge_card", payload: data)
                } catch {
                    Logger.error("Failed to persist knowledge card: \(error)", category: .ai)
                }

                await eventBus.publish(.knowledgeCardPersisted(card: data))
            }
        }

        let result = toolRouter.submitValidationResponse(
            status: status,
            updatedData: updatedData,
            changes: changes,
            notes: notes
        )
        if result != nil {
            Task {
                await eventBus.publish(.validationPromptCleared)
            }
        }
        return result
    }

    // MARK: - Applicant Profile Intake Facade Methods

    /// Begin profile upload flow.
    /// Views should call this instead of accessing toolRouter directly.
    func beginProfileUpload() {
        let request = toolRouter.beginApplicantProfileUpload()
        presentUploadRequest(request)
    }

    /// Begin profile URL entry flow.
    /// Views should call this instead of accessing toolRouter directly.
    func beginProfileURLEntry() {
        toolRouter.beginApplicantProfileURL()
    }

    /// Begin profile contacts fetch flow.
    /// Views should call this instead of accessing toolRouter directly.
    func beginProfileContactsFetch() {
        toolRouter.beginApplicantProfileContactsFetch()
    }

    /// Begin profile manual entry flow.
    /// Views should call this instead of accessing toolRouter directly.
    func beginProfileManualEntry() {
        toolRouter.beginApplicantProfileManualEntry()
    }

    /// Reset profile intake to options view.
    /// Views should call this instead of accessing toolRouter directly.
    func resetProfileIntakeToOptions() {
        toolRouter.resetApplicantProfileIntakeToOptions()
    }

    /// Submit profile draft and send user message to LLM.
    /// Views should call this instead of manually completing.
    func submitProfileDraft(draft: ApplicantProfileDraft, source: OnboardingApplicantProfileIntakeState.Source) async {
        // Close the profile intake UI via event
        await eventBus.publish(.applicantProfileIntakeCleared)

        // Store profile in StateCoordinator/ArtifactRepository (which will emit the event)
        let profileJSON = draft.toSafeJSON()
        await state.storeApplicantProfile(profileJSON)

        // Emit artifact record for traceability
        toolRouter.completeApplicantProfileDraft(draft, source: source)

        // Show the profile summary card in the tool pane
        toolRouter.profileHandler.showProfileSummary(profile: profileJSON)

        // Build user message with the full profile JSON wrapped with validation status
        var userMessage = JSON()
        userMessage["role"].string = "user"

        // Create message with full JSON data including validation_status hint
        let introText = "I have provided my contact information via \(source == .contacts ? "contacts import" : "manual entry"). This data has been validated by me through the UI and is ready to use."

        // Wrap profile data with validation_status
        var wrappedData = JSON()
        wrappedData["applicant_profile"] = profileJSON
        wrappedData["validation_status"].string = "validated_by_user"

        let jsonText = wrappedData.rawString() ?? "{}"

        userMessage["content"].string = """
        \(introText)

        Profile data (JSON):
        ```json
        \(jsonText)
        ```

        An artifact record has been created with this contact information. Do NOT call validate_applicant_profile - this data is already validated.
        """

        await eventBus.publish(.llmEnqueueUserMessage(payload: userMessage, isSystemGenerated: true))

        Logger.info("✅ Profile submitted with detailed data sent to LLM (source: \(source == .contacts ? "contacts" : "manual"))", category: .ai)
    }

    /// Submit profile URL and send user message to LLM.
    /// Views should call this instead of manually submitting.
    func submitProfileURL(_ urlString: String) async {
        // Process URL submission (creates artifact if needed)
        guard toolRouter.submitApplicantProfileURL(urlString) != nil else { return }

        // Send user message to LLM indicating URL submission
        var userMessage = JSON()
        userMessage["role"].string = "user"
        userMessage["content"].string = "Profile URL submitted: \(urlString). Processing for contact information extraction."

        await eventBus.publish(.llmEnqueueUserMessage(payload: userMessage, isSystemGenerated: true))

        Logger.info("✅ Profile URL submitted and user message sent to LLM", category: .ai)
    }

    // MARK: - Phase Advance

    func approvePhaseAdvance() async {
        guard let request = await state.pendingPhaseAdvanceRequest else { return }
        await eventBus.publish(.phaseAdvanceApproved(request: request))
    }

    func denyPhaseAdvance(feedback: String?) async {
        await eventBus.publish(.phaseAdvanceDenied(feedback: feedback))
    }

    // MARK: - UI Response Handling (Send User Messages)

    /// Submit choice selection and send user message to LLM.
    func submitChoiceSelection(_ selectionIds: [String]) async {
        guard toolRouter.resolveChoice(selectionIds: selectionIds) != nil else { return }

        var userMessage = JSON()
        userMessage["role"].string = "user"
        userMessage["content"].string = "Selected option(s): \(selectionIds.joined(separator: ", "))"

        await eventBus.publish(.llmEnqueueUserMessage(payload: userMessage, isSystemGenerated: true))
        Logger.info("✅ Choice selection submitted and user message sent to LLM", category: .ai)
    }

    /// Complete upload and send user message to LLM.
    func completeUploadAndResume(id: UUID, fileURLs: [URL]) async {
        guard await completeUpload(id: id, fileURLs: fileURLs) != nil else { return }

        // Check if any uploaded files require async extraction (PDF, DOCX, HTML, etc.)
        // For these, skip sending immediate "upload successful" message - the DocumentArtifactMessenger
        // will send a more informative message with the extracted content once processing completes
        // Plain text formats (txt, md, rtf) are packaged immediately and don't need to wait
        // HTML requires extraction to remove scripts, CSS, and other noise
        let requiresAsyncExtraction = fileURLs.contains { url in
            let ext = url.pathExtension.lowercased()
            return ["pdf", "doc", "docx", "html", "htm"].contains(ext)
        }

        if requiresAsyncExtraction {
            Logger.info("📄 Upload completed - async document extraction in progress, skipping immediate message", category: .ai)
            return
        }

        var userMessage = JSON()
        userMessage["role"].string = "user"
        userMessage["content"].string = "Uploaded \(fileURLs.count) file(s) successfully."

        await eventBus.publish(.llmEnqueueUserMessage(payload: userMessage, isSystemGenerated: true))
        Logger.info("✅ Upload completed and user message sent to LLM", category: .ai)
    }

    /// Complete upload with link and send user message to LLM.
    func completeUploadAndResume(id: UUID, link: URL) async {
        guard await toolRouter.completeUpload(id: id, link: link) != nil else { return }

        var userMessage = JSON()
        userMessage["role"].string = "user"
        userMessage["content"].string = "Uploaded file from URL: \(link.absoluteString)"

        await eventBus.publish(.llmEnqueueUserMessage(payload: userMessage, isSystemGenerated: true))
        Logger.info("✅ Upload from URL completed and user message sent to LLM", category: .ai)
    }

    /// Skip upload and send user message to LLM.
    func skipUploadAndResume(id: UUID) async {
        guard await skipUpload(id: id) != nil else { return }

        var userMessage = JSON()
        userMessage["role"].string = "user"
        userMessage["content"].string = "Skipped upload."

        await eventBus.publish(.llmEnqueueUserMessage(payload: userMessage, isSystemGenerated: true))
        Logger.info("✅ Upload skipped and user message sent to LLM", category: .ai)
    }

    /// Submit validation response and send user message to LLM.
    func submitValidationAndResume(
        status: String,
        updatedData: JSON?,
        changes: JSON?,
        notes: String?
    ) async {
        guard submitValidationResponse(status: status, updatedData: updatedData, changes: changes, notes: notes) != nil else { return }

        var userMessage = JSON()
        userMessage["role"].string = "user"
        let statusDescription = status.lowercased() == "approved" ? "approved" : (status.lowercased() == "modified" ? "modified" : "rejected")
        userMessage["content"].string = "Validation response: \(statusDescription)"
        if let notes = notes, !notes.isEmpty {
            userMessage["content"].string = userMessage["content"].stringValue + ". Notes: \(notes)"
        }

        await eventBus.publish(.llmEnqueueUserMessage(payload: userMessage, isSystemGenerated: true))
        Logger.info("✅ Validation response submitted and user message sent to LLM", category: .ai)
    }

    /// Confirm applicant profile and send user message to LLM with actual profile data.
    func confirmApplicantProfile(draft: ApplicantProfileDraft) async {
        guard let resolution = toolRouter.resolveApplicantProfile(with: draft) else { return }

        // Extract the actual profile data from the resolution
        let profileData = resolution["data"]
        let status = resolution["status"].stringValue

        // Store profile in StateCoordinator/ArtifactRepository (persists the data)
        await state.storeApplicantProfile(profileData)

        // Build user message with the validated profile information
        var userMessage = JSON()
        userMessage["role"].string = "user"

        // Format profile data for the LLM
        var contentParts: [String] = ["I have provided my contact information:"]

        if let name = profileData["name"].string {
            contentParts.append("- Name: \(name)")
        }
        if let email = profileData["email"].string {
            contentParts.append("- Email: \(email)")
        }
        if let phone = profileData["phone"].string {
            contentParts.append("- Phone: \(phone)")
        }
        if let location = profileData["location"].string {
            contentParts.append("- Location: \(location)")
        }
        if let personalURL = profileData["personal_url"].string {
            contentParts.append("- Website: \(personalURL)")
        }

        // Add social profiles if present
        if let social = profileData["social_profiles"].array, !social.isEmpty {
            contentParts.append("- Social profiles: \(social.count) profile(s)")
        }

        contentParts.append("\nThis information has been validated and is ready for use.")

        userMessage["content"].string = contentParts.joined(separator: "\n")

        await eventBus.publish(.llmEnqueueUserMessage(payload: userMessage, isSystemGenerated: true))
        Logger.info("✅ Applicant profile confirmed (\(status)) and data sent to LLM", category: .ai)
    }

    /// Reject applicant profile and send user message to LLM.
    func rejectApplicantProfile(reason: String) async {
        guard toolRouter.rejectApplicantProfile(reason: reason) != nil else { return }

        var userMessage = JSON()
        userMessage["role"].string = "user"
        userMessage["content"].string = "Applicant profile rejected. Reason: \(reason)"

        await eventBus.publish(.llmEnqueueUserMessage(payload: userMessage, isSystemGenerated: true))
        Logger.info("✅ Applicant profile rejected and user message sent to LLM", category: .ai)
    }

    /// Confirm section toggle and send user message to LLM.
    func confirmSectionToggle(enabled: [String]) async {
        guard toolRouter.resolveSectionToggle(enabled: enabled) != nil else { return }

        var userMessage = JSON()
        userMessage["role"].string = "user"
        userMessage["content"].string = "Section toggle confirmed. Enabled sections: \(enabled.joined(separator: ", "))"

        await eventBus.publish(.llmEnqueueUserMessage(payload: userMessage, isSystemGenerated: true))
        Logger.info("✅ Section toggle confirmed and user message sent to LLM", category: .ai)
    }

    /// Reject section toggle and send user message to LLM.
    func rejectSectionToggle(reason: String) async {
        guard toolRouter.rejectSectionToggle(reason: reason) != nil else { return }

        var userMessage = JSON()
        userMessage["role"].string = "user"
        userMessage["content"].string = "Section toggle rejected. Reason: \(reason)"

        await eventBus.publish(.llmEnqueueUserMessage(payload: userMessage, isSystemGenerated: true))
        Logger.info("✅ Section toggle rejected and user message sent to LLM", category: .ai)
    }

    // MARK: - Checkpoint Management (Delegated to CheckpointManager)
    // No methods needed here - all delegated to checkpointManager

    // MARK: - Data Store Management (Delegated to DataPersistenceService)

    func loadPersistedArtifacts() async {
        await dataPersistenceService.loadPersistedArtifacts()
    }

    func clearArtifacts() {
        Task {
            await dataPersistenceService.clearArtifacts()
        }
    }

    func resetStore() async {
        await dataPersistenceService.resetStore()
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
        ChatTranscriptFormatter.format(messages: state.messagesSync)
    }

    func buildSystemPrompt(for phase: InterviewPhase) -> String {
        phaseTransitionController.buildSystemPrompt(for: phase)
    }

    #if DEBUG
    // MARK: - Debug Event Diagnostics

    func getRecentEvents(count: Int = 10) async -> [OnboardingEvent] {
        await eventBus.getRecentEvents(count: count)
    }

    func getEventMetrics() async -> EventCoordinator.EventMetrics {
        await eventBus.getMetrics()
    }

    func clearEventHistory() async {
        await eventBus.clearHistory()
    }

    /// Reset all onboarding data for testing from a clean slate
    func resetAllOnboardingData() async {
        Logger.info("🗑️ Resetting all onboarding data", category: .ai)

        // 1. Reset ApplicantProfile and remove photo
        await MainActor.run {
            let profile = applicantProfileStore.currentProfile()
            profile.name = "John Doe"
            profile.email = "applicant@example.com"
            profile.phone = "(555) 123-4567"
            profile.address = "123 Main Street"
            profile.city = "Austin"
            profile.state = "Texas"
            profile.zip = "78701"
            profile.websites = "example.com"
            profile.pictureData = nil
            profile.pictureMimeType = nil
            profile.profiles.removeAll()
            applicantProfileStore.save(profile)
            applicantProfileStore.clearCache()
            Logger.info("✅ ApplicantProfile reset and photo removed", category: .ai)
        }

        // 2. Clear all upload artifacts and their records
        clearArtifacts()
        Logger.info("✅ Upload artifacts cleared", category: .ai)

        // 3. Delete all uploaded files from storage
        let uploadsDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Onboarding")
            .appendingPathComponent("Uploads")

        if FileManager.default.fileExists(atPath: uploadsDir.path) {
            do {
                let files = try FileManager.default.contentsOfDirectory(at: uploadsDir, includingPropertiesForKeys: nil)
                for file in files {
                    try FileManager.default.removeItem(at: file)
                }
                Logger.info("✅ Deleted \(files.count) uploaded files from storage", category: .ai)
            } catch {
                Logger.error("❌ Failed to delete uploaded files: \(error.localizedDescription)", category: .ai)
            }
        }

        // 4. Reset the interview state (this resets StateCoordinator and all handlers)
        await resetStore()
        Logger.info("✅ Interview state reset", category: .ai)

        Logger.info("🎉 All onboarding data has been reset", category: .ai)
    }
    #endif
}
