import Foundation
import Observation
import SwiftyJSON
import SwiftOpenAI
import UniformTypeIdentifiers

@MainActor
@Observable
final class OnboardingInterviewCoordinator {
    // MARK: - Core Dependencies
    let state: StateCoordinator
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
    private let ingestionCoordinator: IngestionCoordinator

    // MARK: - Data Store Dependencies
    private let applicantProfileStore: ApplicantProfileStore
    private let dataStore: InterviewDataStore
    let checkpoints: Checkpoints
    private let draftKnowledgeStore: DraftKnowledgeStore

    // MARK: - Document Processing
    private let uploadStorage: OnboardingUploadStorage
    private let documentProcessingService: DocumentProcessingService
    private let documentArtifactHandler: DocumentArtifactHandler
    private let documentArtifactMessenger: DocumentArtifactMessenger
    private let profilePersistenceHandler: ProfilePersistenceHandler
    private let uiResponseCoordinator: UIResponseCoordinator
    private var toolRegistrar: OnboardingToolRegistrar!
    private var coordinatorEventRouter: CoordinatorEventRouter!
    private var toolInteractionCoordinator: ToolInteractionCoordinator!

    // MARK: - UI State
    let ui: OnboardingUIState
    
    // MARK: - Tool Registration
    // MARK: - Computed Properties (Read from StateCoordinator)
    var currentPhase: InterviewPhase {
        get async { await state.phase }
    }
    
    func currentApplicantProfile() -> ApplicantProfile {
        applicantProfileStore.currentProfile()
    }
    
    var artifacts: OnboardingArtifacts {
        get async { await state.artifacts }
    }

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

        // 1. Initialize ToolRegistry early
        let toolRegistry = ToolRegistry()
        self.toolRegistry = toolRegistry

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

        self.ui = OnboardingUIState(preferences: preferences)
        
        let objectiveStore = ObjectiveStore(eventBus: eventBus, phasePolicy: phasePolicy, initialPhase: .phase1CoreFacts)
        let artifactRepository = ArtifactRepository(eventBus: eventBus)
        let chatTranscriptStore = ChatTranscriptStore(eventBus: eventBus)
        let sessionUIState = SessionUIState(eventBus: eventBus, phasePolicy: phasePolicy, initialPhase: .phase1CoreFacts)
        let draftStore = DraftKnowledgeStore(eventBus: eventBus)

        // 2. Initialize StateCoordinator
        self.state = StateCoordinator(
            eventBus: eventBus,
            phasePolicy: phasePolicy,
            objectives: objectiveStore,
            artifacts: artifactRepository,
            chat: chatTranscriptStore,
            uiState: sessionUIState,
            draftStore: draftStore
        )
        self.openAIService = openAIService
        self.knowledgeCardAgent = openAIService.map { KnowledgeCardAgent(client: $0) }
        self.applicantProfileStore = applicantProfileStore
        self.dataStore = dataStore
        self.checkpoints = checkpoints
        self.draftKnowledgeStore = draftStore

        self.uploadStorage = OnboardingUploadStorage()

        // 3. Initialize Document Services
        self.documentProcessingService = DocumentProcessingService(
            documentExtractionService: documentExtractionService,
            uploadStorage: self.uploadStorage,
            dataStore: dataStore
        )
        self.documentExtractionService = documentExtractionService

        self.documentArtifactHandler = DocumentArtifactHandler(
            eventBus: eventBus,
            documentProcessingService: self.documentProcessingService
        )

        self.documentArtifactMessenger = DocumentArtifactMessenger(eventBus: eventBus)

        self.chatboxHandler = ChatboxHandler(
            eventBus: eventBus,
            state: state
        )

        // 4. Initialize Tool Execution
        self.toolExecutor = ToolExecutor(registry: toolRegistry)
        self.toolExecutionCoordinator = ToolExecutionCoordinator(
            eventBus: eventBus,
            toolExecutor: toolExecutor,
            stateCoordinator: state
        )

        // 5. Initialize Tool Router Components
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

        // 6. Initialize Controllers & Managers
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

        self.ingestionCoordinator = IngestionCoordinator(
            eventBus: eventBus,
            state: state,
            documentProcessingService: documentProcessingService,
            agentProvider: { [openAIService] in
                openAIService.map { KnowledgeCardAgent(client: $0) }
            }
        )

        // 7. Initialize Handlers requiring other dependencies
        self.profilePersistenceHandler = ProfilePersistenceHandler(
            applicantProfileStore: applicantProfileStore,
            toolRouter: toolRouter,
            checkpointManager: checkpointManager,
            eventBus: eventBus
        )

        self.uiResponseCoordinator = UIResponseCoordinator(
            eventBus: eventBus,
            toolRouter: toolRouter,
            state: state
        )

        // 8. Post-Init Configuration (Self is now available for closures)
        phaseTransitionController.setLifecycleController(lifecycleController)

        toolRouter.uploadHandler.updateExtractionProgressHandler { [weak self] update in
            Task { @MainActor in
                guard let self else { return }
                self.extractionManagementService.updateExtractionProgress(with: update)
            }
        }

        // 9. Initialize Components requiring 'self'
        self.toolRegistrar = OnboardingToolRegistrar(
            coordinator: self,
            toolRegistry: toolRegistry,
            dataStore: dataStore,
            eventBus: eventBus
        )

        self.coordinatorEventRouter = CoordinatorEventRouter(
            ui: ui,
            state: state,
            checkpointManager: checkpointManager,
            phaseTransitionController: phaseTransitionController,
            toolRouter: toolRouter,
            applicantProfileStore: applicantProfileStore,
            eventBus: eventBus,
            coordinator: self
        )
        
        self.toolInteractionCoordinator = ToolInteractionCoordinator(
            eventBus: eventBus,
            toolRouter: toolRouter,
            dataStore: dataStore
        )

        toolRegistrar.registerTools(
            documentExtractionService: documentExtractionService,
            knowledgeCardAgent: knowledgeCardAgent,
            onModelAvailabilityIssue: { [weak self] message in
                self?.ui.modelAvailabilityMessage = message
            }
        )
        
        Logger.info("🎯 OnboardingInterviewCoordinator initialized with event-driven architecture", category: .ai)

        Task { await subscribeToEvents() }
        
        Task { await profilePersistenceHandler.start() }
        
        Task { await ingestionCoordinator.start() }
    }

    // MARK: - Event Subscription
    private func subscribeToEvents() async {
        coordinatorEventRouter.subscribeToEvents(lifecycle: lifecycleController)
    }

    // MARK: - State Updates
    private func subscribeToStateUpdates() {
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
        case .processingStateChanged(let isProcessing, let statusMessage):
            ui.updateProcessing(isProcessing: isProcessing, statusMessage: statusMessage)
            Logger.info("🎨 UI Update: Chat glow/spinner \(isProcessing ? "ACTIVATED ✨" : "DEACTIVATED") - isProcessing=\(isProcessing), status: \(ui.currentStatusMessage ?? "none")", category: .ai)
            await syncWizardProgressFromState()

        case .streamingStatusUpdated(_, let statusMessage):
            if let statusMessage = statusMessage {
                ui.currentStatusMessage = statusMessage
            }
            break

        case .waitingStateChanged(_, let statusMessage):
            if let statusMessage = statusMessage {
                ui.currentStatusMessage = statusMessage
            }
            break

        case .toolCallRequested(_, let statusMessage):
            if let statusMessage = statusMessage {
                ui.currentStatusMessage = statusMessage
            }
            break

        case .toolCallCompleted(_, _, let statusMessage):
            if let statusMessage = statusMessage {
                ui.currentStatusMessage = statusMessage
            }
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
            await syncWizardProgressFromState()

        default:
            break
        }
    }

    private func handleLLMEvent(_ event: OnboardingEvent) async {
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

    private func handleStateSyncEvent(_ event: OnboardingEvent) async {
        switch event {
        case .stateSnapshot, .stateAllowedToolsUpdated:
            await syncWizardProgressFromState()

        case .phaseAdvanceRequested:
            break

        default:
            break
        }
    }

    private func syncWizardProgressFromState() async {
        let step = await state.currentWizardStep
        let completed = await state.completedWizardSteps
        ui.updateWizardProgress(step: step, completed: completed)
    }

    private func initialStateSync() async {
        await syncWizardProgressFromState()

        ui.messages = await state.messages
        Logger.info("📥 Initial state sync: loaded \(ui.messages.count) messages", category: .ai)
    }

    // MARK: - Interview Lifecycle
    func startInterview(resumeExisting: Bool = false) async -> Bool {
        Logger.info("🚀 Starting interview (resume: \(resumeExisting))", category: .ai)

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

        if !isActuallyResuming {
            await state.setPhase(.phase1CoreFacts)
        }

        await phaseTransitionController.registerObjectivesForCurrentPhase()

        subscribeToStateUpdates()

        await documentArtifactHandler.start()
        await documentArtifactMessenger.start()

        let success = await lifecycleController.startInterview(isResuming: isActuallyResuming)
        if success {
            ui.isActive = await state.isActive
            Logger.info("🎛️ Coordinator isActive synced: \(ui.isActive)", category: .ai)
        }

        if let orchestrator = lifecycleController.orchestrator {
            let cfg = ModelProvider.forTask(.orchestrator)
            await orchestrator.setModelId(ui.preferences.preferredModelId ?? cfg.id)
        }

        return true
    }

    func endInterview() async {
        await lifecycleController.endInterview()
        ui.isActive = await state.isActive
        Logger.info("🎛️ Coordinator isActive synced: \(ui.isActive)", category: .ai)
    }

    func restoreFromSpecificCheckpoint(_ checkpoint: OnboardingCheckpoint) async {
        await loadPersistedArtifacts()
        let didRestore = await checkpointManager.restoreFromSpecificCheckpoint(checkpoint)
        if didRestore {
            Logger.info("✅ Restored from specific checkpoint", category: .ai)
        } else {
            Logger.warning("⚠️ Failed to restore from specific checkpoint", category: .ai)
        }
    }

    // MARK: - Evidence Handling
    func handleEvidenceUpload(url: URL, requirementId: String) async {
        await ingestionCoordinator.handleEvidenceUpload(url: url, requirementId: requirementId)
    }

    // MARK: - Phase Management
    func advancePhase() async -> InterviewPhase? {
        let newPhase = await phaseTransitionController.advancePhase()

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
        await uiResponseCoordinator.applyUserTimelineUpdate(cards: cards, meta: meta, diff: diff)
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
        let artifacts = await state.artifacts

        if let card = artifacts.experienceCards.first(where: { $0["id"].string == id }) {
            return card
        }

        if let sample = artifacts.writingSamples.first(where: { $0["id"].string == id }) {
            return sample
        }

        return nil
    }

    func cancelUploadRequest(id: UUID) async {
        await eventBus.publish(.uploadRequestCancelled(id: id))
    }

    func nextPhase() async -> InterviewPhase? {
        await phaseTransitionController.nextPhase()
    }

    // MARK: - Artifact Management
    // MARK: - Message Management (Delegated to StateCoordinator via ChatboxHandler)
    // Message management methods have been removed as they are handled directly by StateCoordinator
    // and ChatboxHandler.

    // MARK: - Waiting State
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

    // MARK: - Tool Management (Delegated to ToolInteractionCoordinator)
    func presentUploadRequest(_ request: OnboardingUploadRequest) {
        toolInteractionCoordinator.presentUploadRequest(request)
    }

    func completeUpload(id: UUID, fileURLs: [URL]) async -> JSON? {
        await toolInteractionCoordinator.completeUpload(id: id, fileURLs: fileURLs)
    }

    func skipUpload(id: UUID) async -> JSON? {
        await toolInteractionCoordinator.skipUpload(id: id)
    }

    func presentChoicePrompt(_ prompt: OnboardingChoicePrompt) {
        toolInteractionCoordinator.presentChoicePrompt(prompt)
    }

    func submitChoice(optionId: String) -> JSON? {
        toolInteractionCoordinator.submitChoice(optionId: optionId)
    }

    func presentValidationPrompt(_ prompt: OnboardingValidationPrompt) {
        toolInteractionCoordinator.presentValidationPrompt(prompt)
    }

    func submitValidationResponse(
        status: String,
        updatedData: JSON?,
        changes: JSON?,
        notes: String?
    ) async -> JSON? {
        await toolInteractionCoordinator.submitValidationResponse(
            status: status,
            updatedData: updatedData,
            changes: changes,
            notes: notes
        )
    }

    // MARK: - Applicant Profile Intake Facade Methods (Delegated to ToolInteractionCoordinator)
    func beginProfileUpload() {
        let request = toolInteractionCoordinator.beginProfileUpload()
        presentUploadRequest(request)
    }

    func beginProfileURLEntry() {
        toolInteractionCoordinator.beginProfileURLEntry()
    }

    func beginProfileContactsFetch() {
        toolInteractionCoordinator.beginProfileContactsFetch()
    }

    func beginProfileManualEntry() {
        toolInteractionCoordinator.beginProfileManualEntry()
    }

    func resetProfileIntakeToOptions() {
        toolInteractionCoordinator.resetProfileIntakeToOptions()
    }

    func submitProfileDraft(draft: ApplicantProfileDraft, source: OnboardingApplicantProfileIntakeState.Source) async {
        await uiResponseCoordinator.submitProfileDraft(draft: draft, source: source)
    }

    func submitProfileURL(_ urlString: String) async {
        await uiResponseCoordinator.submitProfileURL(urlString)
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
    func submitChoiceSelection(_ selectionIds: [String]) async {
        await uiResponseCoordinator.submitChoiceSelection(selectionIds)
    }

    func completeUploadAndResume(id: UUID, fileURLs: [URL]) async {
        await uiResponseCoordinator.completeUploadAndResume(id: id, fileURLs: fileURLs, coordinator: self)
    }

    func completeUploadAndResume(id: UUID, link: URL) async {
        await uiResponseCoordinator.completeUploadAndResume(id: id, link: link, coordinator: self)
    }

    func skipUploadAndResume(id: UUID) async {
        await uiResponseCoordinator.skipUploadAndResume(id: id, coordinator: self)
    }

    func submitValidationAndResume(
        status: String,
        updatedData: JSON?,
        changes: JSON?,
        notes: String?
    ) async {
        await uiResponseCoordinator.submitValidationAndResume(
            status: status,
            updatedData: updatedData,
            changes: changes,
            notes: notes,
            coordinator: self
        )
    }

    func confirmApplicantProfile(draft: ApplicantProfileDraft) async {
        await uiResponseCoordinator.confirmApplicantProfile(draft: draft)
    }

    func rejectApplicantProfile(reason: String) async {
        await uiResponseCoordinator.rejectApplicantProfile(reason: reason)
    }

    func confirmSectionToggle(enabled: [String]) async {
        await uiResponseCoordinator.confirmSectionToggle(enabled: enabled)
    }

    func rejectSectionToggle(reason: String) async {
        await uiResponseCoordinator.rejectSectionToggle(reason: reason)
    }

    func clearValidationPromptAndNotifyLLM(message: String) async {
        await uiResponseCoordinator.clearValidationPromptAndNotifyLLM(message: message)
    }

    func sendChatMessage(_ text: String) async {
        await uiResponseCoordinator.sendChatMessage(text)
    }

    func requestCancelLLM() async {
        await uiResponseCoordinator.requestCancelLLM()
    }


    // MARK: - Checkpoint Management (Delegated to CheckpointManager)
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
        ui.modelAvailabilityMessage = "Your selected model (\(id)) is not available. Choose another model in Settings."
        uiResponseCoordinator.notifyInvalidModel(id: id)
    }

    func clearModelAvailabilityMessage() {
        ui.modelAvailabilityMessage = nil
    }

    func transcriptExportString() -> String {
        ChatTranscriptFormatter.format(messages: ui.messages)
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

    func resetAllOnboardingData() async {
        Logger.info("🗑️ Resetting all onboarding data", category: .ai)

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

        clearArtifacts()
        Logger.info("✅ Upload artifacts cleared", category: .ai)

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

        await resetStore()
        Logger.info("✅ Interview state reset", category: .ai)

        Logger.info("🎉 All onboarding data has been reset", category: .ai)
    }
    #endif
}
