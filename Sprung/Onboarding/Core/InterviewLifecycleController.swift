import Foundation
import SwiftyJSON
import SwiftOpenAI
/// Manages interview lifecycle: start/end, orchestrator setup, and event subscriptions.
/// Extracted from OnboardingInterviewCoordinator to improve maintainability.
@MainActor
final class InterviewLifecycleController {
    // MARK: - Dependencies
    private let state: StateCoordinator
    private let eventBus: EventCoordinator
    private let phaseRegistry: PhaseScriptRegistry
    private let chatboxHandler: ChatboxHandler
    private let toolExecutionCoordinator: ToolExecutionCoordinator
    private let toolRouter: ToolHandler
    private var openAIService: OpenAIService?
    private let toolRegistry: ToolRegistry
    private let dataStore: InterviewDataStore
    // MARK: - Lifecycle State
    private(set) var orchestrator: InterviewOrchestrator?
    private(set) var workflowEngine: ObjectiveWorkflowEngine?
    private(set) var artifactPersistenceHandler: ArtifactPersistenceHandler?
    private(set) var transcriptPersistenceHandler: TranscriptPersistenceHandler?
    // Event subscription tracking
    private var eventSubscriptionTask: Task<Void, Never>?
    private var stateUpdateTasks: [Task<Void, Never>] = []
    // MARK: - Initialization
    init(
        state: StateCoordinator,
        eventBus: EventCoordinator,
        phaseRegistry: PhaseScriptRegistry,
        chatboxHandler: ChatboxHandler,
        toolExecutionCoordinator: ToolExecutionCoordinator,
        toolRouter: ToolHandler,
        openAIService: OpenAIService?,
        toolRegistry: ToolRegistry,
        dataStore: InterviewDataStore
    ) {
        self.state = state
        self.eventBus = eventBus
        self.phaseRegistry = phaseRegistry
        self.chatboxHandler = chatboxHandler
        self.toolExecutionCoordinator = toolExecutionCoordinator
        self.toolRouter = toolRouter
        self.openAIService = openAIService
        self.toolRegistry = toolRegistry
        self.dataStore = dataStore
    }
    // MARK: - Interview Lifecycle
    func startInterview(isResuming: Bool = false) async -> Bool {
        Logger.info("🚀 Starting interview (lifecycle controller, resuming: \(isResuming))", category: .ai)
        // Verify we have an OpenAI service
        guard let service = openAIService else {
            await state.setActiveState(false)
            return false
        }
        // Set interview as active
        await state.setActiveState(true)

        // Apply user settings from AppStorage
        let flexProcessingEnabled = UserDefaults.standard.bool(forKey: "onboardingInterviewFlexProcessing")
        // Default to true if key doesn't exist (first launch)
        let flexDefault = UserDefaults.standard.object(forKey: "onboardingInterviewFlexProcessing") == nil
        await state.setUseFlexProcessing(flexDefault ? true : flexProcessingEnabled)
        let reasoningEffort = UserDefaults.standard.string(forKey: "onboardingInterviewReasoningEffort") ?? "medium"
        await state.setDefaultReasoningEffort(reasoningEffort)
        Logger.info("⚙️ Applied settings: flexProcessing=\(flexDefault ? true : flexProcessingEnabled), reasoning=\(reasoningEffort)", category: .ai)

        // Start event subscriptions BEFORE orchestrator sends initial message
        // StateCoordinator must be listening for .llmEnqueueUserMessage events
        // to process the queue and emit .llmExecuteUserMessage for LLMMessenger
        await state.startEventSubscriptions()
        await chatboxHandler.startEventSubscriptions()
        await toolExecutionCoordinator.startEventSubscriptions()
        await toolRouter.startEventSubscriptions()
        // Build orchestrator
        let phase = await state.phase
        let baseDeveloperMessage = phaseRegistry.buildSystemPrompt(for: phase)
        let orchestrator = makeOrchestrator(service: service, baseDeveloperMessage: baseDeveloperMessage)
        self.orchestrator = orchestrator

        // Publish phase transition BEFORE orchestrator sends initial message
        // This ensures the phase intro (with toolChoice=agent_ready) is queued
        // and can be bundled with the initial "I'm ready to begin" user message
        if !isResuming {
            await eventBus.publish(.phaseTransitionApplied(phase: phase.rawValue, timestamp: Date()))
        }

        // Initialize orchestrator with resume flag
        // Now safe to send initial message - StateCoordinator is already subscribed
        // and phase intro is already queued for bundling
        do {
            try await orchestrator.startInterview(isResuming: isResuming)
        } catch {
            Logger.error("Failed to start orchestrator: \(error)", category: .ai)
            await state.setActiveState(false)
            return false
        }
        // NOW publish allowed tools - LLMMessenger is already subscribed
        await state.publishAllowedToolsNow()
        // Start workflow engine
        let engine = ObjectiveWorkflowEngine(
            eventBus: eventBus,
            phaseRegistry: phaseRegistry,
            state: state
        )
        workflowEngine = engine
        await engine.start()
        // Start artifact persistence handler
        let persistenceHandler = ArtifactPersistenceHandler(
            eventBus: eventBus,
            dataStore: dataStore
        )
        artifactPersistenceHandler = persistenceHandler
        await persistenceHandler.start()
        // Start transcript persistence handler
        let transcriptHandler = TranscriptPersistenceHandler(
            eventBus: eventBus,
            dataStore: dataStore
        )
        transcriptPersistenceHandler = transcriptHandler
        await transcriptHandler.start()
        // Note: Phase transition is published earlier in this function (before orchestrator starts)
        // so that the phase intro can be bundled with the initial "I'm ready to begin" message
        return true
    }
    func updateOpenAIService(_ service: OpenAIService?) {
        self.openAIService = service
        if orchestrator != nil, service != nil {
            // If we have an active orchestrator, we might need to update its service reference
            // However, InterviewOrchestrator holds a let reference.
            // For now, we'll just log. In a full implementation, we might need to restart the orchestrator
            // or make its service updatable too.
            // Given the current architecture, a restart of the interview might be cleaner if it was already running.
            Logger.info("🔄 OpenAIService updated in LifecycleController", category: .ai)
        }
    }
    func endInterview() async {
        Logger.info("🛑 Ending interview (lifecycle controller)", category: .ai)
        // Stop orchestrator
        await orchestrator?.endInterview()
        orchestrator = nil
        // Stop workflow engine
        await workflowEngine?.stop()
        workflowEngine = nil
        // Stop artifact persistence handler
        await artifactPersistenceHandler?.stop()
        artifactPersistenceHandler = nil
        // Stop transcript persistence handler
        await transcriptPersistenceHandler?.stop()
        transcriptPersistenceHandler = nil
        // Update state via events
        await eventBus.publish(.processingStateChanged(false))
        await eventBus.publish(.waitingStateChanged(nil))
        // Cancel state update tasks
        stateUpdateTasks.forEach { $0.cancel() }
        stateUpdateTasks.removeAll()
    }
    // MARK: - Event Subscriptions
    func subscribeToEvents(_ handler: @escaping (OnboardingEvent) async -> Void) {
        // Cancel any existing subscription
        eventSubscriptionTask?.cancel()
        // Subscribe to all events
        eventSubscriptionTask = Task { [weak self] in
            guard let self else { return }
            for await event in await eventBus.streamAll() {
                await handler(event)
            }
        }
    }
    func subscribeToStateUpdates(_ handlers: StateUpdateHandlers) {
        stateUpdateTasks.forEach { $0.cancel() }
        stateUpdateTasks.removeAll()
        let processingTask = Task { [weak self] in
            guard let self else { return }
            for await event in await self.eventBus.stream(topic: .processing) {
                if Task.isCancelled { break }
                await handlers.handleProcessingEvent(event)
            }
        }
        stateUpdateTasks.append(processingTask)
        let artifactTask = Task { [weak self] in
            guard let self else { return }
            for await event in await self.eventBus.stream(topic: .artifact) {
                if Task.isCancelled { break }
                await handlers.handleArtifactEvent(event)
            }
        }
        stateUpdateTasks.append(artifactTask)
        let llmTask = Task { [weak self] in
            guard let self else { return }
            for await event in await self.eventBus.stream(topic: .llm) {
                if Task.isCancelled { break }
                await handlers.handleLLMEvent(event)
            }
        }
        stateUpdateTasks.append(llmTask)
        let stateTask = Task { [weak self] in
            guard let self else { return }
            for await event in await self.eventBus.stream(topic: .state) {
                if Task.isCancelled { break }
                await handlers.handleStateEvent(event)
            }
        }
        stateUpdateTasks.append(stateTask)
        // Timeline topic - separate stream for immediate UI updates
        // This avoids the congested streamAll() queue
        let timelineTask = Task { [weak self] in
            guard let self else { return }
            for await event in await self.eventBus.stream(topic: .timeline) {
                if Task.isCancelled { break }
                await handlers.handleTimelineEvent(event)
            }
        }
        stateUpdateTasks.append(timelineTask)
        Task {
            await handlers.performInitialSync()
        }
    }
    // MARK: - Factory Methods
    private func makeOrchestrator(
        service: OpenAIService,
        baseDeveloperMessage: String
    ) -> InterviewOrchestrator {
        return InterviewOrchestrator(
            service: service,
            baseDeveloperMessage: baseDeveloperMessage,
            eventBus: eventBus,
            toolRegistry: toolRegistry,
            state: state
        )
    }
}
// MARK: - State Update Handlers Protocol
struct StateUpdateHandlers {
    let handleProcessingEvent: (OnboardingEvent) async -> Void
    let handleArtifactEvent: (OnboardingEvent) async -> Void
    let handleLLMEvent: (OnboardingEvent) async -> Void
    let handleStateEvent: (OnboardingEvent) async -> Void
    let handleTimelineEvent: (OnboardingEvent) async -> Void
    let performInitialSync: () async -> Void
}
