//
//  InterviewOrchestrator.swift
//  Sprung
//
//  Coordinates the onboarding interview conversation via LLMFacade.
//  Uses event-driven architecture - no callbacks, no bidirectional dependencies.
//
import Foundation
import SwiftyJSON
import SwiftOpenAI
/// Orchestrates the interview conversation with the LLM.
/// Delegates to LLMMessenger (§4.3) for message sending.
/// Delegates to NetworkRouter (§4.4) for stream event processing.
actor InterviewOrchestrator: OnboardingEventEmitter {
    // MARK: - Properties
    let eventBus: EventCoordinator
    private let state: StateCoordinator
    private let llmMessenger: LLMMessenger
    private let networkRouter: NetworkRouter
    private var isActive = false
    // MARK: - Initialization
    init(
        llmFacade: LLMFacade,
        baseSystemPrompt: String,
        eventBus: EventCoordinator,
        toolRegistry: ToolRegistry,
        state: StateCoordinator,
        todoStore: InterviewTodoStore
    ) {
        self.eventBus = eventBus
        self.state = state
        self.networkRouter = NetworkRouter(eventBus: eventBus)
        self.llmMessenger = LLMMessenger(
            llmFacade: llmFacade,
            baseSystemPrompt: baseSystemPrompt,
            eventBus: eventBus,
            networkRouter: networkRouter,
            toolRegistry: toolRegistry,
            state: state,
            todoStore: todoStore
        )
        Logger.info("🎯 InterviewOrchestrator initialized (using LLMFacade)", category: .ai)
    }
    // MARK: - Interview Control
    /// Initialize and subscribe to events, but don't send the initial message yet
    func initializeSubscriptions() async {
        isActive = true
        await llmMessenger.activate()
        // Start event subscriptions
        await llmMessenger.startEventSubscriptions()
        // Note: Tool subscription now handled by ToolExecutionCoordinator
        Logger.info("📡 InterviewOrchestrator subscriptions initialized", category: .ai)
    }
    /// Welcome message injected into conversation history before first LLM call
    private static let welcomeMessage = """
        Welcome to the Sprung onboarding interview! I'll guide you through collecting your professional documents \
        and asking questions to build a complete profile. We'll use this to generate tailored resumes and cover letters.

        Feel free to use the chat box anytime to ask questions, provide additional context, or redirect our conversation.

        Let's get started!
        """

    /// Send the initial message to start the interview
    func sendInitialMessage() async {
        guard isActive else {
            Logger.warning("InterviewOrchestrator not active, cannot send initial message", category: .ai)
            return
        }
        await emit(.processing(.stateChanged(isProcessing: true, statusMessage: "Starting interview...")))

        // Front-load the welcome message into chat history before LLM sees it
        // This guarantees consistent welcome without relying on model behavior
        _ = await state.appendAssistantMessage(Self.welcomeMessage)
        Logger.info("👋 Welcome message injected into conversation history", category: .ai)

        // Send user message to trigger LLM response
        var payload = JSON()
        payload["text"].string = "I'm ready to proceed."
        await emit(.llm(.sendUserMessage(payload: payload, isSystemGenerated: true)))
        Logger.info("📤 Initial user message sent", category: .ai)
    }
    func startInterview(isResuming: Bool = false) async throws {
        await initializeSubscriptions()
        // Only send initial greeting if not resuming from checkpoint
        if !isResuming {
            await sendInitialMessage()
        } else {
            Logger.info("📝 Resuming interview with existing conversation context", category: .ai)
        }
    }
}
