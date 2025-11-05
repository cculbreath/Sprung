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

    // MARK: - Services (Phase 3 Decomposition)

    private let extractionManagementService: ExtractionManagementService
    private let timelineManagementService: TimelineManagementService
    private let dataPersistenceService: DataPersistenceService

    // MARK: - Data Store Dependencies

    private let applicantProfileStore: ApplicantProfileStore
    private let dataStore: InterviewDataStore
    let checkpoints: Checkpoints

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

    var skeletonTimelineJSON: JSON? {
        get async { await state.artifacts.skeletonTimeline }
    }

    var artifacts: StateCoordinator.OnboardingArtifacts {
        get async { await state.artifacts }
    }

    // MARK: - Chat Messages

    var messages: [OnboardingMessage] {
        state.messagesSync
    }

    func sendChatMessage(_ text: String) async {
        await chatboxHandler.sendUserMessage(text)
    }

    func requestCancelLLM() async {
        await eventBus.publish(.llmCancelRequested)
    }

    // MARK: - Synchronous Cache Properties (Read from StateCoordinator)

    /// Sync cache access for SwiftUI views
    /// StateCoordinator is the single source of truth with nonisolated(unsafe) sync caches
    var isProcessingSync: Bool { state.isProcessingSync }
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

        case .llmReasoningSummaryDelta(let delta):
            // Sidebar reasoning (ChatGPT-style) - not attached to messages
            await state.updateReasoningSummary(delta: delta)

        case .llmReasoningSummaryComplete(let text):
            // Sidebar reasoning complete
            await state.completeReasoningSummary(finalText: text)

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
             .artifactRecordProduced, .artifactRecordPersisted, .artifactRecordsReplaced,
             .knowledgeCardPersisted, .knowledgeCardsReplaced,
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
        case .processingStateChanged:
            // Sync cache now maintained by StateCoordinator
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

        await phaseTransitionController.registerObjectivesForCurrentPhase()

        // Start interview through lifecycle controller
        let success = await lifecycleController.startInterview()
        if success {
            subscribeToStateUpdates()
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
        hasSubscribedToStateUpdates = false
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

    func presentUploadRequest(_ request: OnboardingUploadRequest, continuationId: UUID) {
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

        if let validation = pendingValidation,
           validation.dataType == "knowledge_card",
           let data = updatedData,
           data != .null,
           ["approved", "modified"].contains(status.lowercased()) {
            Task {
                do {
                    try await dataStore.persist(dataType: "knowledge_card", payload: data)
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
        if let (continuationId, _) = result {
            Task {
                await eventBus.publish(.validationPromptCleared(continuationId: continuationId))
            }
        }
        return result
    }

    // MARK: - UI Continuation Facade Methods (Architecture-Compliant)
    // These methods provide simple interfaces for views to submit user input
    // without exposing internal coordination logic or requiring direct continuation calls.

    /// Submit a user's choice selection and automatically resume tool execution.
    /// Views should call this instead of manually resolving and resuming.
    func submitChoiceSelection(_ selectionIds: [String]) async {
        let result = toolRouter.promptHandler.resolveChoice(selectionIds: selectionIds)
        await continuationTracker.resumeToolContinuation(from: result)
    }

    /// Submit validation response and automatically resume tool execution.
    /// Views should call this instead of manually submitting and resuming.
    func submitValidationAndResume(
        status: String,
        updatedData: JSON?,
        changes: JSON?,
        notes: String?
    ) async {
        let result = submitValidationResponse(
            status: status,
            updatedData: updatedData,
            changes: changes,
            notes: notes
        )
        await continuationTracker.resumeToolContinuation(from: result)
    }

    /// Complete an upload with file URLs and automatically resume tool execution.
    /// Views should call this instead of manually completing and resuming.
    func completeUploadAndResume(id: UUID, fileURLs: [URL]) async {
        let result = await completeUpload(id: id, fileURLs: fileURLs)
        await continuationTracker.resumeToolContinuation(from: result)
    }

    /// Complete an upload with a link and automatically resume tool execution.
    /// Views should call this instead of manually completing and resuming.
    func completeUploadAndResume(id: UUID, link: URL) async {
        let result = await toolRouter.completeUpload(id: id, link: link)
        await continuationTracker.resumeToolContinuation(from: result)
    }

    /// Skip an upload and automatically resume tool execution.
    /// Views should call this instead of manually skipping and resuming.
    func skipUploadAndResume(id: UUID) async {
        let result = await skipUpload(id: id)
        await continuationTracker.resumeToolContinuation(from: result)
    }

    /// Confirm applicant profile and automatically resume tool execution.
    /// Views should call this instead of manually resolving and resuming.
    func confirmApplicantProfile(draft: ApplicantProfileDraft) async {
        let result = toolRouter.resolveApplicantProfile(with: draft)
        await continuationTracker.resumeToolContinuation(from: result)
    }

    /// Reject applicant profile and automatically resume tool execution.
    /// Views should call this instead of manually rejecting and resuming.
    func rejectApplicantProfile(reason: String) async {
        let result = toolRouter.rejectApplicantProfile(reason: reason)
        await continuationTracker.resumeToolContinuation(from: result)
    }

    /// Confirm section toggle and automatically resume tool execution.
    /// Views should call this instead of manually resolving and resuming.
    func confirmSectionToggle(enabled: [String]) async {
        let result = toolRouter.resolveSectionToggle(enabled: enabled)
        await continuationTracker.resumeToolContinuation(from: result)
    }

    /// Reject section toggle and automatically resume tool execution.
    /// Views should call this instead of manually rejecting and resuming.
    func rejectSectionToggle(reason: String) async {
        let result = toolRouter.rejectSectionToggle(reason: reason)
        await continuationTracker.resumeToolContinuation(from: result)
    }

    // MARK: - Applicant Profile Intake Facade Methods

    /// Begin profile upload flow.
    /// Views should call this instead of accessing toolRouter directly.
    func beginProfileUpload() {
        if let (request, continuationId) = toolRouter.beginApplicantProfileUpload() {
            presentUploadRequest(request, continuationId: continuationId)
        }
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

    /// Submit profile draft and automatically resume tool execution.
    /// Views should call this instead of manually completing and resuming.
    func submitProfileDraft(draft: ApplicantProfileDraft, source: OnboardingApplicantProfileIntakeState.Source) async {
        let result = toolRouter.completeApplicantProfileDraft(draft, source: source)
        await continuationTracker.resumeToolContinuation(from: result)
    }

    /// Submit profile URL and automatically resume tool execution.
    /// Views should call this instead of manually submitting and resuming.
    func submitProfileURL(_ urlString: String) async {
        let result = toolRouter.submitApplicantProfileURL(urlString)
        await continuationTracker.resumeToolContinuation(from: result)
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
        // StateCoordinator maintains sync cache
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
        // StateCoordinator maintains sync cache
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
}
