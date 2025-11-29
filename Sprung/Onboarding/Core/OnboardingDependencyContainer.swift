import Foundation
import SwiftyJSON
import SwiftOpenAI

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
    let chatboxHandler: ChatboxHandler
    let toolExecutionCoordinator: ToolExecutionCoordinator

    // MARK: - Controllers
    let lifecycleController: InterviewLifecycleController
    let checkpointManager: CheckpointManager
    let phaseTransitionController: PhaseTransitionController
    let sessionCoordinator: InterviewSessionCoordinator
    let artifactQueryCoordinator: ArtifactQueryCoordinator
    let uiStateUpdateHandler: UIStateUpdateHandler

    // MARK: - Services
    let extractionManagementService: ExtractionManagementService
    let timelineManagementService: TimelineManagementService
    let dataPersistenceService: DataPersistenceService
    let ingestionCoordinator: IngestionCoordinator

    // MARK: - Document Processing
    let uploadStorage: OnboardingUploadStorage
    let documentProcessingService: DocumentProcessingService
    let documentArtifactHandler: DocumentArtifactHandler
    let documentArtifactMessenger: DocumentArtifactMessenger
    let profilePersistenceHandler: ProfilePersistenceHandler
    let uiResponseCoordinator: UIResponseCoordinator

    // MARK: - Stores
    let objectiveStore: ObjectiveStore
    let artifactRepository: ArtifactRepository
    let chatTranscriptStore: ChatTranscriptStore
    let sessionUIState: SessionUIState
    let draftKnowledgeStore: DraftKnowledgeStore

    // MARK: - Tool Execution
    let toolExecutor: ToolExecutor

    // MARK: - External Dependencies (Passed In)
    private let applicantProfileStore: ApplicantProfileStore
    private let dataStore: InterviewDataStore
    let checkpoints: Checkpoints
    let documentExtractionService: DocumentExtractionService

    // MARK: - Mutable State
    private(set) var openAIService: OpenAIService?
    private(set) var knowledgeCardAgent: KnowledgeCardAgent?

    // MARK: - UI State
    let ui: OnboardingUIState
    let wizardTracker: WizardProgressTracker

    // MARK: - Late-Initialized Components (Require Coordinator Reference)
    private(set) var toolRegistrar: OnboardingToolRegistrar!
    private(set) var coordinatorEventRouter: CoordinatorEventRouter!
    private(set) var toolInteractionCoordinator: ToolInteractionCoordinator!

    // MARK: - Initialization
    init(
        openAIService: OpenAIService?,
        documentExtractionService: DocumentExtractionService,
        applicantProfileStore: ApplicantProfileStore,
        dataStore: InterviewDataStore,
        checkpoints: Checkpoints,
        preferences: OnboardingPreferences
    ) {
        // Store external dependencies
        self.openAIService = openAIService
        self.documentExtractionService = documentExtractionService
        self.applicantProfileStore = applicantProfileStore
        self.dataStore = dataStore
        self.checkpoints = checkpoints

        // 1. Initialize Event Bus (foundation for all communication)
        let eventBus = EventCoordinator()
        self.eventBus = eventBus

        // 2. Initialize Registries
        let toolRegistry = ToolRegistry()
        self.toolRegistry = toolRegistry

        let phaseRegistry = PhaseScriptRegistry()
        self.phaseRegistry = phaseRegistry

        // 3. Build Phase Policy
        let phasePolicy = PhasePolicy(
            requiredObjectives: Dictionary(uniqueKeysWithValues: InterviewPhase.allCases.map {
                ($0, phaseRegistry.script(for: $0)?.requiredObjectives ?? [])
            }),
            allowedTools: Dictionary(uniqueKeysWithValues: InterviewPhase.allCases.map {
                ($0, Set(phaseRegistry.script(for: $0)?.allowedTools ?? []))
            })
        )

        // 4. Initialize UI State
        self.ui = OnboardingUIState(preferences: preferences)
        self.wizardTracker = WizardProgressTracker()

        // 5. Initialize State Stores
        let objectiveStore = ObjectiveStore(eventBus: eventBus, phasePolicy: phasePolicy, initialPhase: .phase1CoreFacts)
        self.objectiveStore = objectiveStore

        let artifactRepository = ArtifactRepository(eventBus: eventBus)
        self.artifactRepository = artifactRepository

        let chatTranscriptStore = ChatTranscriptStore(eventBus: eventBus)
        self.chatTranscriptStore = chatTranscriptStore

        let sessionUIState = SessionUIState(eventBus: eventBus, phasePolicy: phasePolicy, initialPhase: .phase1CoreFacts)
        self.sessionUIState = sessionUIState

        let draftKnowledgeStore = DraftKnowledgeStore(eventBus: eventBus)
        self.draftKnowledgeStore = draftKnowledgeStore

        // 6. Initialize State Coordinator
        let state = StateCoordinator(
            eventBus: eventBus,
            phasePolicy: phasePolicy,
            objectives: objectiveStore,
            artifacts: artifactRepository,
            chat: chatTranscriptStore,
            uiState: sessionUIState,
            draftStore: draftKnowledgeStore
        )
        self.state = state

        // 7. Initialize Knowledge Card Agent
        self.knowledgeCardAgent = openAIService.map { KnowledgeCardAgent(client: $0) }

        // 8. Initialize Upload Storage and Document Services
        let uploadStorage = OnboardingUploadStorage()
        self.uploadStorage = uploadStorage

        let documentProcessingService = DocumentProcessingService(
            documentExtractionService: documentExtractionService,
            uploadStorage: uploadStorage,
            dataStore: dataStore
        )
        self.documentProcessingService = documentProcessingService

        let documentArtifactHandler = DocumentArtifactHandler(
            eventBus: eventBus,
            documentProcessingService: documentProcessingService
        )
        self.documentArtifactHandler = documentArtifactHandler

        let documentArtifactMessenger = DocumentArtifactMessenger(eventBus: eventBus)
        self.documentArtifactMessenger = documentArtifactMessenger

        // 9. Initialize Chatbox Handler
        let chatboxHandler = ChatboxHandler(
            eventBus: eventBus,
            state: state
        )
        self.chatboxHandler = chatboxHandler

        // 10. Initialize Tool Execution
        let toolExecutor = ToolExecutor(registry: toolRegistry)
        self.toolExecutor = toolExecutor

        let toolExecutionCoordinator = ToolExecutionCoordinator(
            eventBus: eventBus,
            toolExecutor: toolExecutor,
            stateCoordinator: state
        )
        self.toolExecutionCoordinator = toolExecutionCoordinator

        // 11. Initialize Tool Router Components
        let promptHandler = PromptInteractionHandler()
        let uploadFileService = UploadFileService()
        let uploadHandler = UploadInteractionHandler(
            uploadFileService: uploadFileService,
            uploadStorage: uploadStorage,
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

        let toolRouter = ToolHandler(
            promptHandler: promptHandler,
            uploadHandler: uploadHandler,
            profileHandler: profileHandler,
            sectionHandler: sectionHandler,
            eventBus: eventBus
        )
        self.toolRouter = toolRouter

        // 12. Initialize Controllers
        let lifecycleController = InterviewLifecycleController(
            state: state,
            eventBus: eventBus,
            phaseRegistry: phaseRegistry,
            chatboxHandler: chatboxHandler,
            toolExecutionCoordinator: toolExecutionCoordinator,
            toolRouter: toolRouter,
            openAIService: openAIService,
            toolRegistry: toolRegistry,
            dataStore: dataStore
        )
        self.lifecycleController = lifecycleController

        let checkpointManager = CheckpointManager(
            state: state,
            eventBus: eventBus,
            checkpoints: checkpoints,
            applicantProfileStore: applicantProfileStore
        )
        self.checkpointManager = checkpointManager

        let phaseTransitionController = PhaseTransitionController(
            state: state,
            eventBus: eventBus,
            phaseRegistry: phaseRegistry
        )
        self.phaseTransitionController = phaseTransitionController

        // 13. Initialize Services
        let extractionManagementService = ExtractionManagementService(
            eventBus: eventBus,
            state: state,
            toolRouter: toolRouter,
            wizardTracker: wizardTracker
        )
        self.extractionManagementService = extractionManagementService

        let timelineManagementService = TimelineManagementService(
            eventBus: eventBus,
            phaseTransitionController: phaseTransitionController
        )
        self.timelineManagementService = timelineManagementService

        let dataPersistenceService = DataPersistenceService(
            eventBus: eventBus,
            state: state,
            dataStore: dataStore,
            applicantProfileStore: applicantProfileStore,
            toolRouter: toolRouter,
            wizardTracker: wizardTracker
        )
        self.dataPersistenceService = dataPersistenceService

        // 14. Initialize Session Coordinator (consolidates lifecycle operations)
        let sessionCoordinator = InterviewSessionCoordinator(
            lifecycleController: lifecycleController,
            checkpointManager: checkpointManager,
            phaseTransitionController: phaseTransitionController,
            state: state,
            dataPersistenceService: dataPersistenceService,
            documentArtifactHandler: documentArtifactHandler,
            documentArtifactMessenger: documentArtifactMessenger,
            ui: ui
        )
        self.sessionCoordinator = sessionCoordinator

        // 15. Initialize Artifact Query Coordinator
        let artifactQueryCoordinator = ArtifactQueryCoordinator(
            state: state,
            eventBus: eventBus
        )
        self.artifactQueryCoordinator = artifactQueryCoordinator

        // 16. Initialize UI State Update Handler
        let uiStateUpdateHandler = UIStateUpdateHandler(
            ui: ui,
            state: state,
            wizardTracker: wizardTracker,
            checkpointManager: checkpointManager
        )
        self.uiStateUpdateHandler = uiStateUpdateHandler

        let ingestionCoordinator = IngestionCoordinator(
            eventBus: eventBus,
            state: state,
            documentProcessingService: documentProcessingService,
            agentProvider: { [openAIService] in
                openAIService.map { KnowledgeCardAgent(client: $0) }
            }
        )
        self.ingestionCoordinator = ingestionCoordinator

        // 14. Initialize Handlers requiring other dependencies
        let profilePersistenceHandler = ProfilePersistenceHandler(
            applicantProfileStore: applicantProfileStore,
            toolRouter: toolRouter,
            checkpointManager: checkpointManager,
            eventBus: eventBus
        )
        self.profilePersistenceHandler = profilePersistenceHandler

        let uiResponseCoordinator = UIResponseCoordinator(
            eventBus: eventBus,
            toolRouter: toolRouter,
            state: state
        )
        self.uiResponseCoordinator = uiResponseCoordinator

        // 15. Post-Init Configuration
        phaseTransitionController.setLifecycleController(lifecycleController)
        toolRouter.uploadHandler.updateExtractionProgressHandler { [extractionManagementService] update in
            Task { @MainActor in
                extractionManagementService.updateExtractionProgress(with: update)
            }
        }

        Logger.info("🏗️ OnboardingDependencyContainer initialized", category: .ai)
    }

    // MARK: - Late Initialization (Requires Coordinator Reference)

    /// Complete initialization of components that require a reference to the coordinator.
    /// Must be called after the coordinator is fully constructed.
    func completeInitialization(
        coordinator: OnboardingInterviewCoordinator,
        onModelAvailabilityIssue: @escaping (String) -> Void
    ) {
        // Initialize components requiring coordinator reference
        self.toolRegistrar = OnboardingToolRegistrar(
            coordinator: coordinator,
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
            coordinator: coordinator
        )

        self.toolInteractionCoordinator = ToolInteractionCoordinator(
            eventBus: eventBus,
            toolRouter: toolRouter,
            dataStore: dataStore
        )

        // Register tools
        toolRegistrar.registerTools(
            documentExtractionService: documentExtractionService,
            knowledgeCardAgent: knowledgeCardAgent,
            onModelAvailabilityIssue: onModelAvailabilityIssue
        )

        Logger.info("🏗️ OnboardingDependencyContainer late initialization completed", category: .ai)
    }

    // MARK: - Service Updates

    func updateOpenAIService(_ service: OpenAIService?) {
        self.openAIService = service
        self.knowledgeCardAgent = service.map { KnowledgeCardAgent(client: $0) }
        lifecycleController.updateOpenAIService(service)
    }

    func reregisterTools(onModelAvailabilityIssue: @escaping (String) -> Void) {
        toolRegistrar.registerTools(
            documentExtractionService: documentExtractionService,
            knowledgeCardAgent: knowledgeCardAgent,
            onModelAvailabilityIssue: onModelAvailabilityIssue
        )
    }

    func updateIngestionAgentProvider() async {
        await ingestionCoordinator.updateAgentProvider { [openAIService] in
            openAIService.map { KnowledgeCardAgent(client: $0) }
        }
    }

    // MARK: - Accessors for External Dependencies

    func getApplicantProfileStore() -> ApplicantProfileStore {
        applicantProfileStore
    }

    func getDataStore() -> InterviewDataStore {
        dataStore
    }
}
