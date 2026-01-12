import Foundation
import SwiftyJSON
import SwiftOpenAI

// MARK: - Initialization Result Types
/// Groups core infrastructure components for initialization
private struct CoreInfrastructure {
    let eventBus: EventCoordinator
    let toolRegistry: ToolRegistry
    let phaseRegistry: PhaseScriptRegistry
    let phasePolicy: PhasePolicy
}

/// Groups state store components for initialization
private struct StateStores {
    let objectiveStore: ObjectiveStore
    let artifactRepository: ArtifactRepository
    let streamingBuffer: StreamingMessageBuffer
    let sessionUIState: SessionUIState
    let operationTracker: OperationTracker
    let conversationLog: ConversationLog
}

/// Groups document processing components for initialization
private struct DocumentComponents {
    let uploadStorage: OnboardingUploadStorage
    let documentProcessingService: DocumentProcessingService
    let documentArtifactHandler: DocumentArtifactHandler
    let documentArtifactMessenger: DocumentArtifactMessenger
}

/// Groups tool routing components for initialization
private struct ToolRouterComponents {
    let toolRouter: ToolHandler
    let toolExecutor: ToolExecutor
    let toolExecutionCoordinator: ToolExecutionCoordinator
}

/// Groups service components for initialization
private struct Services {
    let extractionManagementService: ExtractionManagementService
    let timelineManagementService: TimelineManagementService
    let sectionCardManagementService: SectionCardManagementService
    let dataPersistenceService: DataPersistenceService
}

/// Groups artifact ingestion components for initialization
private struct ArtifactIngestionComponents {
    let documentIngestionKernel: DocumentIngestionKernel
    let gitIngestionKernel: GitIngestionKernel
    let artifactIngestionCoordinator: ArtifactIngestionCoordinator
}


/// Owns all service instances for the onboarding module.
/// Extracted from OnboardingInterviewCoordinator to centralize dependency wiring.
@MainActor
final class OnboardingDependencyContainer {
    // MARK: - Core Infrastructure
    let eventBus: EventCoordinator
    let state: StateCoordinator
    let toolRegistry: ToolRegistry
    let phaseRegistry: PhaseScriptRegistry
    // MARK: - Handlers
    let toolRouter: ToolHandler
    let toolExecutionCoordinator: ToolExecutionCoordinator
    // MARK: - Controllers
    let lifecycleController: InterviewLifecycleController
    let phaseTransitionController: PhaseTransitionController
    let uiStateUpdateHandler: UIStateUpdateHandler
    // MARK: - Services
    let extractionManagementService: ExtractionManagementService
    let timelineManagementService: TimelineManagementService
    let sectionCardManagementService: SectionCardManagementService
    let dataPersistenceService: DataPersistenceService
    let voiceProfileService: VoiceProfileService
    let titleSetService: TitleSetService
    let dataResetService: OnboardingDataResetService
    let artifactArchiveManager: ArtifactArchiveManager

    // MARK: - Artifact Ingestion Infrastructure
    let documentIngestionKernel: DocumentIngestionKernel
    let gitIngestionKernel: GitIngestionKernel
    let artifactIngestionCoordinator: ArtifactIngestionCoordinator
    // MARK: - Document Processing
    let uploadStorage: OnboardingUploadStorage
    let documentProcessingService: DocumentProcessingService
    let webExtractionService: WebExtractionService
    let documentArtifactHandler: DocumentArtifactHandler
    let documentArtifactMessenger: DocumentArtifactMessenger
    let profilePersistenceHandler: ProfilePersistenceHandler
    let uiResponseCoordinator: UIResponseCoordinator
    let voiceProfileExtractionHandler: VoiceProfileExtractionHandler
    // MARK: - Stores
    let objectiveStore: ObjectiveStore
    let artifactRepository: ArtifactRepository
    let streamingBuffer: StreamingMessageBuffer
    let sessionUIState: SessionUIState
    // MARK: - Session Persistence
    let sessionPersistenceHandler: SwiftDataSessionPersistenceHandler
    // MARK: - Tool Execution
    let toolExecutor: ToolExecutor
    // MARK: - Artifact Store (SwiftData)
    let artifactRecordStore: ArtifactRecordStore
    // MARK: - External Dependencies (Passed In)
    private let applicantProfileStore: ApplicantProfileStore
    private let knowledgeCardStore: KnowledgeCardStore
    private let skillStore: SkillStore
    private let coverRefStore: CoverRefStore
    private let experienceDefaultsStore: ExperienceDefaultsStore
    private let guidanceStore: InferenceGuidanceStore
    let sessionStore: OnboardingSessionStore
    private let dataStore: InterviewDataStore
    private let candidateDossierStore: CandidateDossierStore
    let documentExtractionService: DocumentExtractionService
    // MARK: - Mutable State
    private(set) var llmFacade: LLMFacade?
    // MARK: - UI State
    let ui: OnboardingUIState
    let wizardTracker: WizardProgressTracker
    let conversationLogStore: ConversationLogStore

    // MARK: - Multi-Agent Infrastructure
    let agentActivityTracker: AgentActivityTracker

    // MARK: - Card Pipeline Services
    let cardMergeService: CardMergeService
    let chatInventoryService: ChatInventoryService?

    // MARK: - Usage Tracking
    let tokenUsageTracker: TokenUsageTracker

    // MARK: - Interview Todo List
    let todoStore: InterviewTodoStore

    // MARK: - Artifact Filesystem Context
    let artifactFilesystemContext: ArtifactFilesystemContext

    // MARK: - UI Tool Continuation Manager
    let uiToolContinuationManager: UIToolContinuationManager

    // MARK: - User Action Queue Infrastructure
    let userActionQueue: UserActionQueue
    let drainGate: DrainGate
    let queueDrainCoordinator: QueueDrainCoordinator
    let gateBlockEventHandler: GateBlockEventHandler

    // MARK: - Debug Services
    #if DEBUG
    let debugRegenerationService: DebugRegenerationService
    #endif

    // MARK: - Early-Initialized Coordinators (No Coordinator Reference Needed)
    let coordinatorEventRouter: CoordinatorEventRouter
    // MARK: - Late-Initialized Components (Require Coordinator Reference)
    private(set) var toolRegistrar: OnboardingToolRegistrar!
    // MARK: - Initialization
    init(
        llmFacade: LLMFacade?,
        documentExtractionService: DocumentExtractionService,
        applicantProfileStore: ApplicantProfileStore,
        knowledgeCardStore: KnowledgeCardStore,
        skillStore: SkillStore,
        coverRefStore: CoverRefStore,
        experienceDefaultsStore: ExperienceDefaultsStore,
        guidanceStore: InferenceGuidanceStore,
        sessionStore: OnboardingSessionStore,
        dataStore: InterviewDataStore,
        candidateDossierStore: CandidateDossierStore,
        preferences: OnboardingPreferences
    ) {
        // Store external dependencies
        self.llmFacade = llmFacade
        self.documentExtractionService = documentExtractionService
        self.applicantProfileStore = applicantProfileStore
        self.knowledgeCardStore = knowledgeCardStore
        self.skillStore = skillStore
        self.coverRefStore = coverRefStore
        self.experienceDefaultsStore = experienceDefaultsStore
        self.guidanceStore = guidanceStore
        self.sessionStore = sessionStore
        self.dataStore = dataStore
        self.candidateDossierStore = candidateDossierStore

        // Initialize artifact store using same context as sessionStore
        guard let context = sessionStore.modelContext else {
            fatalError("OnboardingDependencyContainer requires valid model context at initialization. " +
                       "Ensure SessionStore has initialized its model context before creating the container.")
        }
        self.artifactRecordStore = ArtifactRecordStore(context: context)

        // 1. Initialize core infrastructure
        let core = Self.createCoreInfrastructure()
        self.eventBus = core.eventBus
        self.toolRegistry = core.toolRegistry
        self.phaseRegistry = core.phaseRegistry

        // 2. Initialize UI state
        self.ui = OnboardingUIState(preferences: preferences)
        self.wizardTracker = WizardProgressTracker()
        self.conversationLogStore = ConversationLogStore()
        self.agentActivityTracker = AgentActivityTracker()
        self.tokenUsageTracker = TokenUsageTracker()
        self.todoStore = InterviewTodoStore(eventBus: core.eventBus)
        self.artifactFilesystemContext = ArtifactFilesystemContext()
        self.uiToolContinuationManager = UIToolContinuationManager()

        // 2b. Initialize user action queue infrastructure
        self.userActionQueue = UserActionQueue()
        self.drainGate = DrainGate()
        self.queueDrainCoordinator = QueueDrainCoordinator(
            queue: userActionQueue,
            gate: drainGate,
            eventBus: self.eventBus
        )
        self.gateBlockEventHandler = GateBlockEventHandler(
            eventBus: self.eventBus,
            drainGate: drainGate
        )
        // Note: gateBlockEventHandler.startListening() called later after all properties initialized

        // 3. Initialize state stores
        let stores = Self.createStateStores(eventBus: core.eventBus, phasePolicy: core.phasePolicy)
        self.objectiveStore = stores.objectiveStore
        self.artifactRepository = stores.artifactRepository
        self.streamingBuffer = stores.streamingBuffer
        self.sessionUIState = stores.sessionUIState

        // 4. Initialize state coordinator
        self.state = StateCoordinator(
            eventBus: core.eventBus, phasePolicy: core.phasePolicy, phaseRegistry: core.phaseRegistry,
            objectives: stores.objectiveStore, artifacts: stores.artifactRepository,
            streamingBuffer: stores.streamingBuffer, uiState: stores.sessionUIState,
            todoStore: todoStore, operationTracker: stores.operationTracker,
            conversationLog: stores.conversationLog
        )

        // Wire up agent activity tracker for status reporting in interview context
        // (captured locally to avoid self capture issue in init)
        let stateRef = self.state
        let trackerRef = self.agentActivityTracker
        Task {
            await stateRef.setAgentActivityTracker(trackerRef)
        }

        // Agent completion callback - logs only, no separate LLM message.
        // Agent status is included in message headers when legitimate messages are sent.
        trackerRef.onAllAgentsCompleted = { summaries in
            let succeeded = summaries.filter { $0.succeeded }.count
            let failed = summaries.count - succeeded
            Logger.info("🏁 All agents completed: \(succeeded) succeeded, \(failed) failed", category: .ai)
        }

        // 4a. Initialize card pipeline services (deferred - needs sessionPersistenceHandler)
        // Created below after sessionPersistenceHandler is initialized
        if let facade = llmFacade {
            self.chatInventoryService = ChatInventoryService(
                llmFacade: facade,
                conversationLog: stores.conversationLog,
                artifactRepository: stores.artifactRepository,
                eventBus: core.eventBus
            )
        } else {
            self.chatInventoryService = nil
        }

        // 5. Initialize document services
        let docs = Self.createDocumentComponents(
            eventBus: core.eventBus, documentExtractionService: documentExtractionService, dataStore: dataStore,
            stateCoordinator: state, agentTracker: agentActivityTracker, llmFacade: llmFacade
        )
        self.uploadStorage = docs.uploadStorage
        self.documentProcessingService = docs.documentProcessingService
        self.documentArtifactHandler = docs.documentArtifactHandler
        self.documentArtifactMessenger = docs.documentArtifactMessenger
        self.webExtractionService = WebExtractionService(llmFacade: llmFacade)

        // 6. Initialize tool router components
        let tools = Self.createToolRouterComponents(
            eventBus: core.eventBus, toolRegistry: core.toolRegistry, state: state,
            uploadStorage: docs.uploadStorage, applicantProfileStore: applicantProfileStore, dataStore: dataStore,
            ui: ui
        )
        self.toolRouter = tools.toolRouter
        self.toolExecutor = tools.toolExecutor
        self.toolExecutionCoordinator = tools.toolExecutionCoordinator

        // 7. Initialize session persistence handler (needed by phase transition controller)
        self.sessionPersistenceHandler = SwiftDataSessionPersistenceHandler(
            eventBus: core.eventBus,
            sessionStore: sessionStore,
            artifactRecordStore: artifactRecordStore
        )

        // 7b. Initialize guidance services
        self.voiceProfileService = VoiceProfileService(llmFacade: llmFacade)
        self.titleSetService = TitleSetService(llmFacade: llmFacade)

        // 7c. Initialize data reset service
        self.dataResetService = OnboardingDataResetService(
            sessionPersistenceHandler: sessionPersistenceHandler,
            knowledgeCardStore: knowledgeCardStore,
            skillStore: skillStore,
            coverRefStore: coverRefStore,
            experienceDefaultsStore: experienceDefaultsStore,
            applicantProfileStore: applicantProfileStore,
            artifactRecordStore: artifactRecordStore
        )

        // 7d. Initialize artifact archive manager
        self.artifactArchiveManager = ArtifactArchiveManager(
            artifactRecordStore: artifactRecordStore,
            artifactRepository: stores.artifactRepository,
            sessionPersistenceHandler: sessionPersistenceHandler,
            eventBus: core.eventBus
        )

        // 7a. Initialize card merge service (deferred from 4a - needs sessionPersistenceHandler)
        self.cardMergeService = CardMergeService(
            artifactRecordStore: artifactRecordStore,
            sessionPersistenceHandler: sessionPersistenceHandler,
            llmFacade: llmFacade,
            eventBus: core.eventBus,
            agentActivityTracker: agentActivityTracker
        )

        // 7e. Initialize debug regeneration service
        #if DEBUG
        self.debugRegenerationService = DebugRegenerationService(
            documentProcessingService: docs.documentProcessingService,
            agentActivityTracker: agentActivityTracker,
            cardMergeService: cardMergeService,
            knowledgeCardStore: knowledgeCardStore,
            eventBus: core.eventBus
        )
        #endif

        // 8. Initialize phase transition controller (depends on session persistence handler)
        self.phaseTransitionController = PhaseTransitionController(
            state: state, eventBus: core.eventBus, phaseRegistry: core.phaseRegistry,
            artifactRecordStore: artifactRecordStore, sessionPersistenceHandler: sessionPersistenceHandler,
            knowledgeCardStore: knowledgeCardStore, artifactFilesystemContext: artifactFilesystemContext
        )

        // 9. Initialize services
        let services = Self.createServices(
            eventBus: core.eventBus, state: state, toolRouter: tools.toolRouter,
            wizardTracker: wizardTracker, phaseTransitionController: phaseTransitionController,
            dataStore: dataStore, applicantProfileStore: applicantProfileStore
        )
        self.extractionManagementService = services.extractionManagementService
        self.timelineManagementService = services.timelineManagementService
        self.sectionCardManagementService = services.sectionCardManagementService
        self.dataPersistenceService = services.dataPersistenceService

        // 10. Initialize lifecycle controller (merged with session coordinator)
        self.lifecycleController = InterviewLifecycleController(
            state: state,
            eventBus: core.eventBus,
            phaseRegistry: core.phaseRegistry,
            toolExecutionCoordinator: tools.toolExecutionCoordinator,
            toolRouter: tools.toolRouter,
            llmFacade: llmFacade,
            toolRegistry: core.toolRegistry,
            dataStore: dataStore,
            phaseTransitionController: phaseTransitionController,
            dataPersistenceService: services.dataPersistenceService,
            documentArtifactHandler: docs.documentArtifactHandler,
            documentArtifactMessenger: docs.documentArtifactMessenger,
            ui: ui,
            sessionPersistenceHandler: sessionPersistenceHandler,
            knowledgeCardStore: knowledgeCardStore,
            skillStore: skillStore,
            todoStore: todoStore
        )
        self.uiStateUpdateHandler = UIStateUpdateHandler(ui: ui, state: state, wizardTracker: wizardTracker)

        // 11. Initialize artifact ingestion infrastructure
        let ingestion = Self.createArtifactIngestionComponents(
            eventBus: core.eventBus, documentProcessingService: docs.documentProcessingService, llmFacade: llmFacade
        )
        self.documentIngestionKernel = ingestion.documentIngestionKernel
        self.gitIngestionKernel = ingestion.gitIngestionKernel
        self.artifactIngestionCoordinator = ingestion.artifactIngestionCoordinator

        // Wire up agent activity tracker to git kernel for UI visibility (captured locally to avoid self capture issue)
        let activityTracker = self.agentActivityTracker
        Task {
            await ingestion.gitIngestionKernel.setAgentActivityTracker(activityTracker)
        }

        // 12. Initialize remaining handlers
        self.profilePersistenceHandler = ProfilePersistenceHandler(
            applicantProfileStore: applicantProfileStore, toolRouter: tools.toolRouter, eventBus: core.eventBus, ui: ui
        )
        self.uiResponseCoordinator = UIResponseCoordinator(
            eventBus: core.eventBus, toolRouter: tools.toolRouter, state: state, ui: ui,
            sessionUIState: sessionUIState, continuationManager: uiToolContinuationManager,
            userActionQueue: userActionQueue, drainGate: drainGate,
            queueDrainCoordinator: queueDrainCoordinator
        )

        // 12a. Initialize voice profile extraction handler
        self.voiceProfileExtractionHandler = VoiceProfileExtractionHandler(
            eventBus: core.eventBus,
            voiceProfileService: voiceProfileService,
            guidanceStore: guidanceStore,
            artifactRecordStore: artifactRecordStore,
            sessionPersistenceHandler: sessionPersistenceHandler,
            agentActivityTracker: agentActivityTracker,
            conversationLog: stores.conversationLog
        )
        // 11. Initialize early coordinators (don't need coordinator reference)
        // Create extracted services first
        let kcWorkflow = KnowledgeCardWorkflowService(
            ui: ui,
            state: state,
            knowledgeCardStore: knowledgeCardStore,
            skillStore: skillStore,
            eventBus: core.eventBus,
            cardMergeService: cardMergeService,
            chatInventoryService: chatInventoryService,
            agentActivityTracker: agentActivityTracker,
            sessionUIState: stores.sessionUIState,
            phaseTransitionController: phaseTransitionController
        )
        // Configure LLM facade provider for prose summary generation
        let llmFacadeRef = llmFacade
        kcWorkflow.setLLMFacadeProvider { llmFacadeRef }

        let onboardingPersistence = OnboardingPersistenceService(
            ui: ui,
            dataStore: dataStore,
            coverRefStore: coverRefStore,
            experienceDefaultsStore: experienceDefaultsStore,
            eventBus: core.eventBus,
            artifactRecordStore: self.artifactRecordStore,
            sessionPersistenceHandler: self.sessionPersistenceHandler
        )

        self.coordinatorEventRouter = CoordinatorEventRouter(
            ui: ui,
            state: state,
            phaseTransitionController: phaseTransitionController,
            toolRouter: tools.toolRouter,
            eventBus: core.eventBus,
            knowledgeCardWorkflow: kcWorkflow,
            onboardingPersistence: onboardingPersistence
        )

        // 12. Post-init configuration
        tools.toolRouter.uploadHandler.updateExtractionProgressHandler { [services] update in
            Task { @MainActor in services.extractionManagementService.updateExtractionProgress(with: update) }
        }

        // 15. Start conversation log listening
        conversationLogStore.startListening(eventBus: core.eventBus)

        // 16. Start gate block event handler listening
        let gateHandler = self.gateBlockEventHandler
        Task {
            await gateHandler.startListening()
        }

        Logger.info("🏗️ OnboardingDependencyContainer initialized", category: .ai)
    }

    // MARK: - Private Factory Methods
    private static func createCoreInfrastructure() -> CoreInfrastructure {
        let eventBus = EventCoordinator()
        let toolRegistry = ToolRegistry()
        let phaseRegistry = PhaseScriptRegistry()
        let phasePolicy = PhasePolicy(
            requiredObjectives: Dictionary(uniqueKeysWithValues: InterviewPhase.allCases.map {
                ($0, phaseRegistry.script(for: $0)?.requiredObjectives ?? [])
            }),
            // Tool permissions derived from ToolBundlePolicy (single source of truth)
            allowedTools: ToolBundlePolicy.allowedToolsByPhase
        )
        return CoreInfrastructure(eventBus: eventBus, toolRegistry: toolRegistry,
                                  phaseRegistry: phaseRegistry, phasePolicy: phasePolicy)
    }

    private static func createStateStores(eventBus: EventCoordinator, phasePolicy: PhasePolicy) -> StateStores {
        let operationTracker = OperationTracker()
        let conversationLog = ConversationLog(operations: operationTracker, eventBus: eventBus)
        return StateStores(
            objectiveStore: ObjectiveStore(eventBus: eventBus, phasePolicy: phasePolicy, initialPhase: .phase1VoiceContext),
            artifactRepository: ArtifactRepository(eventBus: eventBus),
            streamingBuffer: StreamingMessageBuffer(),
            sessionUIState: SessionUIState(eventBus: eventBus, phasePolicy: phasePolicy, initialPhase: .phase1VoiceContext),
            operationTracker: operationTracker,
            conversationLog: conversationLog
        )
    }

    private static func createDocumentComponents(
        eventBus: EventCoordinator, documentExtractionService: DocumentExtractionService, dataStore: InterviewDataStore,
        stateCoordinator: StateCoordinator, agentTracker: AgentActivityTracker, llmFacade: LLMFacade?
    ) -> DocumentComponents {
        // Update the extraction service with the event bus and agent tracker
        Task {
            await documentExtractionService.updateEventBus(eventBus)
            await documentExtractionService.setAgentTracker(agentTracker)
        }

        let uploadStorage = OnboardingUploadStorage()
        let documentProcessingService = DocumentProcessingService(
            documentExtractionService: documentExtractionService,
            llmFacade: llmFacade
        )
        return DocumentComponents(
            uploadStorage: uploadStorage, documentProcessingService: documentProcessingService,
            documentArtifactHandler: DocumentArtifactHandler(eventBus: eventBus,
                                                             documentProcessingService: documentProcessingService,
                                                             agentTracker: agentTracker,
                                                             stateCoordinator: stateCoordinator),
            documentArtifactMessenger: DocumentArtifactMessenger(eventBus: eventBus, stateCoordinator: stateCoordinator)
        )
    }

    private static func createToolRouterComponents(
        eventBus: EventCoordinator, toolRegistry: ToolRegistry, state: StateCoordinator,
        uploadStorage: OnboardingUploadStorage, applicantProfileStore: ApplicantProfileStore,
        dataStore: InterviewDataStore, ui: OnboardingUIState
    ) -> ToolRouterComponents {
        let toolExecutor = ToolExecutor(registry: toolRegistry)
        let toolExecutionCoordinator = ToolExecutionCoordinator(
            eventBus: eventBus, toolExecutor: toolExecutor, stateCoordinator: state, ui: ui
        )
        let uploadHandler = UploadInteractionHandler(
            uploadFileService: UploadFileService(), uploadStorage: uploadStorage,
            applicantProfileStore: applicantProfileStore,
            eventBus: eventBus, extractionProgressHandler: nil
        )
        let toolRouter = ToolHandler(
            promptHandler: PromptInteractionHandler(), uploadHandler: uploadHandler,
            profileHandler: ProfileInteractionHandler(contactsImportService: ContactsImportService(), eventBus: eventBus),
            sectionHandler: SectionToggleHandler(), eventBus: eventBus
        )
        return ToolRouterComponents(toolRouter: toolRouter, toolExecutor: toolExecutor,
                                    toolExecutionCoordinator: toolExecutionCoordinator)
    }

    private static func createServices(
        eventBus: EventCoordinator, state: StateCoordinator, toolRouter: ToolHandler,
        wizardTracker: WizardProgressTracker, phaseTransitionController: PhaseTransitionController,
        dataStore: InterviewDataStore, applicantProfileStore: ApplicantProfileStore
    ) -> Services {
        Services(
            extractionManagementService: ExtractionManagementService(
                eventBus: eventBus, state: state
            ),
            timelineManagementService: TimelineManagementService(
                eventBus: eventBus, phaseTransitionController: phaseTransitionController
            ),
            sectionCardManagementService: SectionCardManagementService(
                eventBus: eventBus
            ),
            dataPersistenceService: DataPersistenceService(
                eventBus: eventBus, state: state, dataStore: dataStore,
                toolRouter: toolRouter, wizardTracker: wizardTracker
            )
        )
    }

    private static func createArtifactIngestionComponents(
        eventBus: EventCoordinator, documentProcessingService: DocumentProcessingService, llmFacade: LLMFacade?
    ) -> ArtifactIngestionComponents {
        let documentKernel = DocumentIngestionKernel(
            documentProcessingService: documentProcessingService, eventBus: eventBus
        )
        let gitKernel = GitIngestionKernel(eventBus: eventBus)
        let coordinator = ArtifactIngestionCoordinator(
            eventBus: eventBus, documentKernel: documentKernel, gitKernel: gitKernel,
            documentProcessingService: documentProcessingService
        )
        Task {
            await documentKernel.setIngestionCoordinator(coordinator)
            await gitKernel.setIngestionCoordinator(coordinator)
            if let facade = llmFacade { await gitKernel.updateLLMFacade(facade) }
        }
        return ArtifactIngestionComponents(
            documentIngestionKernel: documentKernel, gitIngestionKernel: gitKernel,
            artifactIngestionCoordinator: coordinator
        )
    }
    // MARK: - Late Initialization (Requires Coordinator Reference)
    /// Complete initialization of components that require a reference to the coordinator.
    /// Must be called after the coordinator is fully constructed.
    func completeInitialization(
        coordinator: OnboardingInterviewCoordinator,
        onModelAvailabilityIssue: @escaping (String) -> Void
    ) {
        // Initialize tool registrar (only component still requiring coordinator reference)
        self.toolRegistrar = OnboardingToolRegistrar(
            coordinator: coordinator,
            toolRegistry: toolRegistry,
            dataStore: dataStore,
            eventBus: eventBus,
            phaseRegistry: phaseRegistry,
            todoStore: todoStore,
            artifactFilesystemContext: artifactFilesystemContext,
            candidateDossierStore: candidateDossierStore
        )
        // Register tools
        toolRegistrar.registerTools(
            documentExtractionService: documentExtractionService,
            onModelAvailabilityIssue: onModelAvailabilityIssue
        )

        // Start token usage tracking subscription
        tokenUsageTracker.startEventSubscription(eventBus: eventBus)

        Logger.info("🏗️ OnboardingDependencyContainer late initialization completed", category: .ai)
    }
    // MARK: - Service Updates
    func reregisterTools(onModelAvailabilityIssue: @escaping (String) -> Void) {
        toolRegistrar.registerTools(
            documentExtractionService: documentExtractionService,
            onModelAvailabilityIssue: onModelAvailabilityIssue
        )
    }
    // MARK: - Accessors for External Dependencies
    func getApplicantProfileStore() -> ApplicantProfileStore {
        applicantProfileStore
    }
    func getKnowledgeCardStore() -> KnowledgeCardStore {
        knowledgeCardStore
    }
    func getSkillStore() -> SkillStore {
        skillStore
    }
    func getCoverRefStore() -> CoverRefStore {
        coverRefStore
    }
    func getExperienceDefaultsStore() -> ExperienceDefaultsStore {
        experienceDefaultsStore
    }
    func getGuidanceStore() -> InferenceGuidanceStore {
        guidanceStore
    }
}
