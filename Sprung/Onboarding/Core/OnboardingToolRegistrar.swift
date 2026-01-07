import Foundation
/// Handles registration of tools for the OnboardingInterviewCoordinator.
@MainActor
final class OnboardingToolRegistrar {
    private weak var coordinator: OnboardingInterviewCoordinator?
    private let toolRegistry: ToolRegistry
    private let dataStore: InterviewDataStore
    private let eventBus: EventCoordinator
    private let phaseRegistry: PhaseScriptRegistry
    private let todoStore: InterviewTodoStore

    init(
        coordinator: OnboardingInterviewCoordinator,
        toolRegistry: ToolRegistry,
        dataStore: InterviewDataStore,
        eventBus: EventCoordinator,
        phaseRegistry: PhaseScriptRegistry,
        todoStore: InterviewTodoStore
    ) {
        self.coordinator = coordinator
        self.toolRegistry = toolRegistry
        self.dataStore = dataStore
        self.eventBus = eventBus
        self.phaseRegistry = phaseRegistry
        self.todoStore = todoStore
    }
    func registerTools(
        documentExtractionService: DocumentExtractionService,
        onModelAvailabilityIssue: @escaping (String) -> Void
    ) {
        guard let coordinator = coordinator else { return }
        // Set up extraction progress handler
        Task {
            await documentExtractionService.setInvalidModelHandler { [weak self] modelId in
                Task { @MainActor in
                    guard self != nil else { return }
                    onModelAvailabilityIssue("Your selected model (\(modelId)) is not available. Choose another model in Settings.")
                }
            }
        }
        // Register all tools with coordinator reference
        toolRegistry.register(GetUserOptionTool(coordinator: coordinator))
        toolRegistry.register(GetUserUploadTool(coordinator: coordinator))
        toolRegistry.register(CancelUserUploadTool(coordinator: coordinator))
        toolRegistry.register(GetApplicantProfileTool(coordinator: coordinator))
        toolRegistry.register(CreateTimelineCardTool(coordinator: coordinator))
        toolRegistry.register(UpdateTimelineCardTool(coordinator: coordinator))
        toolRegistry.register(DeleteTimelineCardTool(coordinator: coordinator))
        toolRegistry.register(ReorderTimelineCardsTool(coordinator: coordinator))
        toolRegistry.register(DisplayTimelineForReviewTool(coordinator: coordinator))
        toolRegistry.register(SubmitForValidationTool(coordinator: coordinator))
        toolRegistry.register(ListArtifactsTool(coordinator: coordinator))
        toolRegistry.register(GetArtifactRecordTool(coordinator: coordinator))
        toolRegistry.register(RequestRawArtifactFileTool(coordinator: coordinator))
        toolRegistry.register(UpdateArtifactMetadataTool(coordinator: coordinator))
        toolRegistry.register(CreateWebArtifactTool(coordinator: coordinator, eventBus: eventBus))
        toolRegistry.register(NextPhaseTool(coordinator: coordinator, dataStore: dataStore, registry: phaseRegistry))
        toolRegistry.register(AskUserSkipToNextPhaseTool(coordinator: coordinator))
        toolRegistry.register(ValidateApplicantProfileTool(coordinator: coordinator))
        toolRegistry.register(ConfigureEnabledSectionsTool(coordinator: coordinator))
        toolRegistry.register(UpdateDossierNotesTool(coordinator: coordinator))
        toolRegistry.register(AgentReadyTool(todoStore: todoStore))
        toolRegistry.register(GetTimelineEntriesTool(coordinator: coordinator))
        // KC workflow: Document merge UI → Approve & Create button → Direct ResRef conversion
        toolRegistry.register(OpenDocumentCollectionTool(coordinator: coordinator))
        toolRegistry.register(IngestWritingSampleTool(coordinator: coordinator, eventBus: eventBus))
        toolRegistry.register(GenerateExperienceDefaultsTool(
            coordinator: coordinator,
            eventBus: eventBus,
            agentActivityTracker: coordinator.agentActivityTracker
        ))
        toolRegistry.register(SubmitCandidateDossierTool(eventBus: eventBus, dataStore: dataStore))

        // Filesystem tools for browsing exported artifacts (ephemeral responses, pruned after N turns)
        toolRegistry.register(ReadArtifactFileTool())
        toolRegistry.register(ListArtifactDirectoryTool())
        toolRegistry.register(GlobArtifactSearchTool())
        toolRegistry.register(GrepArtifactSearchTool())

        // Meta tools (interview process management)
        toolRegistry.register(UpdateTodoListTool(todoStore: todoStore))

        Logger.info("✅ Registered \(toolRegistry.allTools().count) tools", category: .ai)
    }
}
