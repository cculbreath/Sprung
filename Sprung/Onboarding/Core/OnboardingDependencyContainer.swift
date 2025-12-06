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
    let chatTranscriptStore: ChatTranscriptStore
    let sessionUIState: SessionUIState
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
    let chatboxHandler: ChatboxHandler
}

/// Groups controller components for initialization
private struct Controllers {
    let lifecycleController: InterviewLifecycleController
    let phaseTransitionController: PhaseTransitionController
}

/// Groups service components for initialization
private struct Services {
    let extractionManagementService: ExtractionManagementService
    let timelineManagementService: TimelineManagementService
    let dataPersistenceService: DataPersistenceService
}

/// Groups artifact ingestion components for initialization
private struct ArtifactIngestionComponents {
    let documentIngestionKernel: DocumentIngestionKernel
    let gitIngestionKernel: GitIngestionKernel
    let artifactIngestionCoordinator: ArtifactIngestionCoordinator
}

/// Groups parameters for controller creation
private struct ControllerCreationParams {
    let state: StateCoordinator
    let eventBus: EventCoordinator
    let phaseRegistry: PhaseScriptRegistry
    let chatboxHandler: ChatboxHandler
    let toolExecutionCoordinator: ToolExecutionCoordinator
    let toolRouter: ToolHandler
    let openAIService: OpenAIService?
    let toolRegistry: ToolRegistry
    let dataStore: InterviewDataStore
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
    let chatboxHandler: ChatboxHandler
    let toolExecutionCoordinator: ToolExecutionCoordinator
    // MARK: - Controllers
    let lifecycleController: InterviewLifecycleController
    let phaseTransitionController: PhaseTransitionController
    let sessionCoordinator: InterviewSessionCoordinator
    let artifactQueryCoordinator: ArtifactQueryCoordinator
    let uiStateUpdateHandler: UIStateUpdateHandler
    // MARK: - Services
    let extractionManagementService: ExtractionManagementService
    let timelineManagementService: TimelineManagementService
    let dataPersistenceService: DataPersistenceService

    // MARK: - Artifact Ingestion Infrastructure
    let documentIngestionKernel: DocumentIngestionKernel
    let gitIngestionKernel: GitIngestionKernel
    let artifactIngestionCoordinator: ArtifactIngestionCoordinator
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
    // MARK: - Session Persistence
    let sessionPersistenceHandler: SwiftDataSessionPersistenceHandler
    // MARK: - Tool Execution
    let toolExecutor: ToolExecutor
    // MARK: - External Dependencies (Passed In)
    private let applicantProfileStore: ApplicantProfileStore
    private let resRefStore: ResRefStore
    private let coverRefStore: CoverRefStore
    private let experienceDefaultsStore: ExperienceDefaultsStore
    let sessionStore: OnboardingSessionStore
    private let dataStore: InterviewDataStore
    let documentExtractionService: DocumentExtractionService
    // MARK: - Mutable State
    private(set) var openAIService: OpenAIService?
    private(set) var llmFacade: LLMFacade?
    // MARK: - UI State
    let ui: OnboardingUIState
    let wizardTracker: WizardProgressTracker
    let conversationLogStore: ConversationLogStore
    // MARK: - Early-Initialized Coordinators (No Coordinator Reference Needed)
    let toolInteractionCoordinator: ToolInteractionCoordinator
    let coordinatorEventRouter: CoordinatorEventRouter
    // MARK: - Late-Initialized Components (Require Coordinator Reference)
    private(set) var toolRegistrar: OnboardingToolRegistrar!
    // MARK: - Initialization
    init(
        openAIService: OpenAIService?,
        llmFacade: LLMFacade?,
        documentExtractionService: DocumentExtractionService,
        applicantProfileStore: ApplicantProfileStore,
        resRefStore: ResRefStore,
        coverRefStore: CoverRefStore,
        experienceDefaultsStore: ExperienceDefaultsStore,
        sessionStore: OnboardingSessionStore,
        dataStore: InterviewDataStore,
        preferences: OnboardingPreferences
    ) {
        // Store external dependencies
        self.openAIService = openAIService
        self.llmFacade = llmFacade
        self.documentExtractionService = documentExtractionService
        self.applicantProfileStore = applicantProfileStore
        self.resRefStore = resRefStore
        self.coverRefStore = coverRefStore
        self.experienceDefaultsStore = experienceDefaultsStore
        self.sessionStore = sessionStore
        self.dataStore = dataStore

        // 1. Initialize core infrastructure
        let core = Self.createCoreInfrastructure()
        self.eventBus = core.eventBus
        self.toolRegistry = core.toolRegistry
        self.phaseRegistry = core.phaseRegistry

        // 2. Initialize UI state
        self.ui = OnboardingUIState(preferences: preferences)
        self.wizardTracker = WizardProgressTracker()
        self.conversationLogStore = ConversationLogStore()

        // 3. Initialize state stores
        let stores = Self.createStateStores(eventBus: core.eventBus, phasePolicy: core.phasePolicy)
        self.objectiveStore = stores.objectiveStore
        self.artifactRepository = stores.artifactRepository
        self.chatTranscriptStore = stores.chatTranscriptStore
        self.sessionUIState = stores.sessionUIState

        // 4. Initialize state coordinator
        self.state = StateCoordinator(
            eventBus: core.eventBus, phasePolicy: core.phasePolicy,
            objectives: stores.objectiveStore, artifacts: stores.artifactRepository,
            chat: stores.chatTranscriptStore, uiState: stores.sessionUIState
        )

        // 5. Initialize document services
        let docs = Self.createDocumentComponents(
            eventBus: core.eventBus, documentExtractionService: documentExtractionService, dataStore: dataStore
        )
        self.uploadStorage = docs.uploadStorage
        self.documentProcessingService = docs.documentProcessingService
        self.documentArtifactHandler = docs.documentArtifactHandler
        self.documentArtifactMessenger = docs.documentArtifactMessenger

        // 6. Initialize tool router components
        let tools = Self.createToolRouterComponents(
            eventBus: core.eventBus, toolRegistry: core.toolRegistry, state: state,
            uploadStorage: docs.uploadStorage, applicantProfileStore: applicantProfileStore, dataStore: dataStore
        )
        self.toolRouter = tools.toolRouter
        self.toolExecutor = tools.toolExecutor
        self.toolExecutionCoordinator = tools.toolExecutionCoordinator
        self.chatboxHandler = tools.chatboxHandler

        // 7. Initialize controllers
        let controllerParams = ControllerCreationParams(
            state: state, eventBus: core.eventBus, phaseRegistry: core.phaseRegistry,
            chatboxHandler: tools.chatboxHandler, toolExecutionCoordinator: tools.toolExecutionCoordinator,
            toolRouter: tools.toolRouter, openAIService: openAIService, toolRegistry: core.toolRegistry,
            dataStore: dataStore
        )
        let controllers = Self.createControllers(params: controllerParams)
        self.lifecycleController = controllers.lifecycleController
        self.phaseTransitionController = controllers.phaseTransitionController

        // 8. Initialize services
        let services = Self.createServices(
            eventBus: core.eventBus, state: state, toolRouter: tools.toolRouter,
            wizardTracker: wizardTracker, phaseTransitionController: controllers.phaseTransitionController,
            dataStore: dataStore, applicantProfileStore: applicantProfileStore
        )
        self.extractionManagementService = services.extractionManagementService
        self.timelineManagementService = services.timelineManagementService
        self.dataPersistenceService = services.dataPersistenceService

        // 9. Initialize session persistence handler first (needed by session coordinator)
        self.sessionPersistenceHandler = SwiftDataSessionPersistenceHandler(
            eventBus: core.eventBus,
            sessionStore: sessionStore,
            chatTranscriptStore: stores.chatTranscriptStore
        )

        // 10. Initialize session and query coordinators
        self.sessionCoordinator = InterviewSessionCoordinator(
            lifecycleController: controllers.lifecycleController,
            phaseTransitionController: controllers.phaseTransitionController, state: state,
            dataPersistenceService: services.dataPersistenceService,
            documentArtifactHandler: docs.documentArtifactHandler,
            documentArtifactMessenger: docs.documentArtifactMessenger, ui: ui,
            sessionPersistenceHandler: sessionPersistenceHandler,
            chatTranscriptStore: stores.chatTranscriptStore
        )
        self.artifactQueryCoordinator = ArtifactQueryCoordinator(state: state, eventBus: core.eventBus)
        self.uiStateUpdateHandler = UIStateUpdateHandler(ui: ui, state: state, wizardTracker: wizardTracker)

        // 11. Initialize artifact ingestion infrastructure
        let ingestion = Self.createArtifactIngestionComponents(
            eventBus: core.eventBus, documentProcessingService: docs.documentProcessingService, llmFacade: llmFacade
        )
        self.documentIngestionKernel = ingestion.documentIngestionKernel
        self.gitIngestionKernel = ingestion.gitIngestionKernel
        self.artifactIngestionCoordinator = ingestion.artifactIngestionCoordinator

        // 12. Initialize remaining handlers
        self.profilePersistenceHandler = ProfilePersistenceHandler(
            applicantProfileStore: applicantProfileStore, toolRouter: tools.toolRouter, eventBus: core.eventBus, ui: ui
        )
        self.uiResponseCoordinator = UIResponseCoordinator(
            eventBus: core.eventBus, toolRouter: tools.toolRouter, state: state, ui: ui
        )
        // 13. Initialize early coordinators (don't need coordinator reference)
        self.toolInteractionCoordinator = ToolInteractionCoordinator(
            eventBus: core.eventBus, toolRouter: tools.toolRouter
        )
        self.coordinatorEventRouter = CoordinatorEventRouter(
            ui: ui, state: state, phaseTransitionController: controllers.phaseTransitionController,
            toolRouter: tools.toolRouter, applicantProfileStore: applicantProfileStore,
            resRefStore: resRefStore, coverRefStore: coverRefStore,
            experienceDefaultsStore: experienceDefaultsStore,
            eventBus: core.eventBus, dataStore: dataStore
        )

        // 14. Post-init configuration
        controllers.phaseTransitionController.setLifecycleController(controllers.lifecycleController)
        tools.toolRouter.uploadHandler.updateExtractionProgressHandler { [services] update in
            Task { @MainActor in services.extractionManagementService.updateExtractionProgress(with: update) }
        }

        // 15. Start conversation log listening
        conversationLogStore.startListening(eventBus: core.eventBus)

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
            allowedTools: Dictionary(uniqueKeysWithValues: InterviewPhase.allCases.map {
                ($0, Set(phaseRegistry.script(for: $0)?.allowedTools ?? []))
            })
        )
        return CoreInfrastructure(eventBus: eventBus, toolRegistry: toolRegistry,
                                  phaseRegistry: phaseRegistry, phasePolicy: phasePolicy)
    }

    private static func createStateStores(eventBus: EventCoordinator, phasePolicy: PhasePolicy) -> StateStores {
        StateStores(
            objectiveStore: ObjectiveStore(eventBus: eventBus, phasePolicy: phasePolicy, initialPhase: .phase1CoreFacts),
            artifactRepository: ArtifactRepository(eventBus: eventBus),
            chatTranscriptStore: ChatTranscriptStore(eventBus: eventBus),
            sessionUIState: SessionUIState(eventBus: eventBus, phasePolicy: phasePolicy, initialPhase: .phase1CoreFacts)
        )
    }

    private static func createDocumentComponents(
        eventBus: EventCoordinator, documentExtractionService: DocumentExtractionService, dataStore: InterviewDataStore
    ) -> DocumentComponents {
        let uploadStorage = OnboardingUploadStorage()
        let documentProcessingService = DocumentProcessingService(
            documentExtractionService: documentExtractionService, uploadStorage: uploadStorage, dataStore: dataStore
        )
        return DocumentComponents(
            uploadStorage: uploadStorage, documentProcessingService: documentProcessingService,
            documentArtifactHandler: DocumentArtifactHandler(eventBus: eventBus,
                                                             documentProcessingService: documentProcessingService),
            documentArtifactMessenger: DocumentArtifactMessenger(eventBus: eventBus)
        )
    }

    private static func createToolRouterComponents(
        eventBus: EventCoordinator, toolRegistry: ToolRegistry, state: StateCoordinator,
        uploadStorage: OnboardingUploadStorage, applicantProfileStore: ApplicantProfileStore,
        dataStore: InterviewDataStore
    ) -> ToolRouterComponents {
        let chatboxHandler = ChatboxHandler(eventBus: eventBus, state: state)
        let toolExecutor = ToolExecutor(registry: toolRegistry)
        let toolExecutionCoordinator = ToolExecutionCoordinator(
            eventBus: eventBus, toolExecutor: toolExecutor, stateCoordinator: state
        )
        let uploadHandler = UploadInteractionHandler(
            uploadFileService: UploadFileService(), uploadStorage: uploadStorage,
            applicantProfileStore: applicantProfileStore, dataStore: dataStore,
            eventBus: eventBus, extractionProgressHandler: nil
        )
        let toolRouter = ToolHandler(
            promptHandler: PromptInteractionHandler(), uploadHandler: uploadHandler,
            profileHandler: ProfileInteractionHandler(contactsImportService: ContactsImportService(), eventBus: eventBus),
            sectionHandler: SectionToggleHandler(), eventBus: eventBus
        )
        return ToolRouterComponents(toolRouter: toolRouter, toolExecutor: toolExecutor,
                                    toolExecutionCoordinator: toolExecutionCoordinator, chatboxHandler: chatboxHandler)
    }

    private static func createControllers(params: ControllerCreationParams) -> Controllers {
        Controllers(
            lifecycleController: InterviewLifecycleController(
                state: params.state, eventBus: params.eventBus, phaseRegistry: params.phaseRegistry,
                chatboxHandler: params.chatboxHandler, toolExecutionCoordinator: params.toolExecutionCoordinator,
                toolRouter: params.toolRouter, openAIService: params.openAIService,
                toolRegistry: params.toolRegistry, dataStore: params.dataStore
            ),
            phaseTransitionController: PhaseTransitionController(
                state: params.state, eventBus: params.eventBus, phaseRegistry: params.phaseRegistry
            )
        )
    }

    private static func createServices(
        eventBus: EventCoordinator, state: StateCoordinator, toolRouter: ToolHandler,
        wizardTracker: WizardProgressTracker, phaseTransitionController: PhaseTransitionController,
        dataStore: InterviewDataStore, applicantProfileStore: ApplicantProfileStore
    ) -> Services {
        Services(
            extractionManagementService: ExtractionManagementService(
                eventBus: eventBus, state: state, toolRouter: toolRouter, wizardTracker: wizardTracker
            ),
            timelineManagementService: TimelineManagementService(
                eventBus: eventBus, phaseTransitionController: phaseTransitionController
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
            eventBus: eventBus
        )
        // Register tools
        toolRegistrar.registerTools(
            documentExtractionService: documentExtractionService,
            onModelAvailabilityIssue: onModelAvailabilityIssue
        )
        Logger.info("🏗️ OnboardingDependencyContainer late initialization completed", category: .ai)
    }
    // MARK: - Service Updates
    func updateOpenAIService(_ service: OpenAIService?) {
        self.openAIService = service
        lifecycleController.updateOpenAIService(service)
    }

    func updateLLMFacade(_ facade: LLMFacade?) {
        self.llmFacade = facade
        Task {
            await gitIngestionKernel.updateLLMFacade(facade)
        }
    }
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
    func getDataStore() -> InterviewDataStore {
        dataStore
    }
    func getResRefStore() -> ResRefStore {
        resRefStore
    }

    /// Knowledge cards created during onboarding (persisted as ResRefs with isFromOnboarding=true)
    var onboardingKnowledgeCards: [ResRef] {
        resRefStore.resRefs.filter { $0.isFromOnboarding }
    }
}
