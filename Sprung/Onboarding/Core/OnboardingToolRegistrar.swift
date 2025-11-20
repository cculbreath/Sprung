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
        knowledgeCardAgent: KnowledgeCardAgent?,
        onModelAvailabilityIssue: @escaping (String) -> Void
    ) {
        guard let coordinator = coordinator else { return }
        
        // Set up extraction progress handler
        Task {
            await documentExtractionService.setInvalidModelHandler { [weak self] modelId in
                Task { @MainActor in
                    guard let self = self else { return }
                    // Notify coordinator (or UI state directly if we had access)
                    // For now, we'll use the callback
                    onModelAvailabilityIssue("Your selected model (\(modelId)) is not available. Choose another model in Settings.")
                    
                    // We might want to call a method on coordinator to handle this notification
                    // coordinator.notifyInvalidModel(id: modelId) 
                    // (Assuming this method exists or will be exposed)
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
        
        if let agent = knowledgeCardAgent {
            toolRegistry.register(GenerateKnowledgeCardTool(agentProvider: { agent }))
        }
        
        Logger.info("✅ Registered \(toolRegistry.allTools().count) tools", category: .ai)
    }
}
