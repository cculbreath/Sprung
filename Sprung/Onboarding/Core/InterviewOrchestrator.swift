//
//  InterviewOrchestrator.swift
//  Sprung
//
//  Coordinates the onboarding interview conversation with OpenAI's Responses API.
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
    private let service: OpenAIService
    private let baseDeveloperMessage: String  // Sent once on first request, persists via previous_response_id
    private var isActive = false
    // MARK: - Initialization
    init(
        service: OpenAIService,
        baseDeveloperMessage: String,
        eventBus: EventCoordinator,
        toolRegistry: ToolRegistry,
        state: StateCoordinator
    ) {
        self.service = service
        self.baseDeveloperMessage = baseDeveloperMessage
        self.eventBus = eventBus
        self.state = state
        self.networkRouter = NetworkRouter(eventBus: eventBus)
        self.llmMessenger = LLMMessenger(
            service: service,
            baseDeveloperMessage: baseDeveloperMessage,
            eventBus: eventBus,
            networkRouter: networkRouter,
            toolRegistry: toolRegistry,
            state: state
        )
        Logger.info("🎯 InterviewOrchestrator initialized", category: .ai)
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
        await emit(.processingStateChanged(true, statusMessage: "Starting interview..."))

        // Front-load the welcome message into chat history before LLM sees it
        // This guarantees consistent welcome without relying on model behavior
        _ = await state.appendAssistantMessage(Self.welcomeMessage)
        Logger.info("👋 Welcome message injected into conversation history", category: .ai)

        // Send user message with forced toolChoice to skip any LLM greeting
        var payload = JSON()
        payload["text"].string = "I'm ready to proceed."
        await emit(.llmSendUserMessage(payload: payload, isSystemGenerated: true, toolChoice: "agent_ready"))
        Logger.info("📤 Initial user message sent with forced agent_ready tool", category: .ai)
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
    func endInterview() {
        isActive = false
        Task {
            await llmMessenger.deactivate()
        }
    }
    func sendUserMessage(_ text: String) async throws {
        guard isActive else { return }
        await emit(.processingStateChanged(true, statusMessage: "Sending message..."))
        // Emit message request event (§4.3)
        var payload = JSON()
        payload["text"].string = text
        await emit(.llmSendUserMessage(payload: payload))
    }
    // MARK: - Model Configuration
    /// Set the model ID for the LLM messenger
    func setModelId(_ id: String) async {
        await llmMessenger.setModelId(id)
    }
}
