import Foundation
/// Handles registration of tools for the OnboardingInterviewCoordinator.
@MainActor
final class OnboardingToolRegistrar {
    private weak var coordinator: OnboardingInterviewCoordinator?
    private let toolRegistry: ToolRegistry
    private let dataStore: InterviewDataStore
    private let eventBus: EventCoordinator
    init(
        coordinator: OnboardingInterviewCoordinator,
        toolRegistry: ToolRegistry,
        dataStore: InterviewDataStore,
        eventBus: EventCoordinator
    ) {
        self.coordinator = coordinator
        self.toolRegistry = toolRegistry
        self.dataStore = dataStore
        self.eventBus = eventBus
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
        toolRegistry.register(PersistDataTool(dataStore: dataStore, eventBus: eventBus))
        toolRegistry.register(SetObjectiveStatusTool(coordinator: coordinator))
        toolRegistry.register(NextPhaseTool(coordinator: coordinator))
        toolRegistry.register(ValidateApplicantProfileTool(coordinator: coordinator))
        toolRegistry.register(GetValidatedApplicantProfileTool(coordinator: coordinator))
        toolRegistry.register(ConfigureEnabledSectionsTool(coordinator: coordinator))
        toolRegistry.register(AgentReadyTool())
        toolRegistry.register(StartPhaseTwoTool(coordinator: coordinator))
        toolRegistry.register(RequestEvidenceTool(coordinator: coordinator))
        toolRegistry.register(GetTimelineEntriesTool(coordinator: coordinator))
        toolRegistry.register(DisplayKnowledgeCardPlanTool(coordinator: coordinator))
        toolRegistry.register(SetCurrentKnowledgeCardTool(coordinator: coordinator, eventBus: eventBus))
        toolRegistry.register(ScanGitRepoTool(coordinator: coordinator))
        toolRegistry.register(SubmitKnowledgeCardTool(coordinator: coordinator, dataStore: dataStore, eventBus: eventBus))
        toolRegistry.register(StartPhaseThreeTool(coordinator: coordinator))
        toolRegistry.register(IngestWritingSampleTool(coordinator: coordinator, eventBus: eventBus))
        Logger.info("✅ Registered \(toolRegistry.allTools().count) tools", category: .ai)
    }
}
