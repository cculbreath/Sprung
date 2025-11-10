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
    private let openAIService: OpenAIService?
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

    func startInterview() async -> Bool {
        Logger.info("🚀 Starting interview (lifecycle controller)", category: .ai)

        // Verify we have an OpenAI service
        guard let service = openAIService else {
            await state.setActiveState(false)
            return false
        }

        // Set interview as active
        await state.setActiveState(true)

        // Build orchestrator
        let phase = await state.phase
        let baseDeveloperMessage = phaseRegistry.buildSystemPrompt(for: phase)
        let orchestrator = makeOrchestrator(service: service, baseDeveloperMessage: baseDeveloperMessage)
        self.orchestrator = orchestrator

        // Initialize orchestrator subscriptions FIRST
        // This ensures LLMMessenger is subscribed before we publish allowed tools
        await orchestrator.initializeSubscriptions()

        // Start event subscriptions for all other handlers
        await chatboxHandler.startEventSubscriptions()
        await toolExecutionCoordinator.startEventSubscriptions()
        await state.startEventSubscriptions()
        await toolRouter.startEventSubscriptions()

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

        // Send phase introductory prompt for the current phase
        // This sends the phase-specific instructions as a developer message,
        // followed by "I am ready to begin" as a user message to trigger the conversation
        let currentPhase = await state.phase
        await eventBus.publish(.phaseTransitionApplied(phase: currentPhase.rawValue, timestamp: Date()))

        return true
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
    let performInitialSync: () async -> Void
}
