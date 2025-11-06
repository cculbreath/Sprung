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
    private let systemPrompt: String

    private var isActive = false

    // MARK: - Initialization

    init(
        service: OpenAIService,
        systemPrompt: String,
        eventBus: EventCoordinator,
        toolRegistry: ToolRegistry,
        state: StateCoordinator
    ) {
        self.service = service
        self.systemPrompt = systemPrompt
        self.eventBus = eventBus
        self.state = state
        self.networkRouter = NetworkRouter(eventBus: eventBus)
        self.llmMessenger = LLMMessenger(
            service: service,
            systemPrompt: systemPrompt,
            eventBus: eventBus,
            networkRouter: networkRouter,
            toolRegistry: toolRegistry,
            state: state
        )
        Logger.info("🎯 InterviewOrchestrator initialized with LLMMessenger and ConversationContextAssembler", category: .ai)
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

    /// Send the initial message to start the interview
    func sendInitialMessage() async {
        guard isActive else {
            Logger.warning("InterviewOrchestrator not active, cannot send initial message", category: .ai)
            return
        }

        await emit(.processingStateChanged(true))

        // Send developer instruction requiring tool call
        var payload = JSON()
        payload["text"].string = """
        Greet the user warmly without using their name. For example: "Welcome! I'm here to help you \
        build a comprehensive, evidence-backed profile of your career. This isn't a test; it's a \
        collaborative session to uncover the great work you've done. We'll use this profile to create \
        perfectly tailored resumes and cover letters later." \
        You MUST call the get_applicant_profile tool in this same response after your greeting.
        """
        payload["forceToolName"].string = "get_applicant_profile"
        await emit(.llmSendDeveloperMessage(payload: payload))

        Logger.info("📤 Initial developer message sent with forced get_applicant_profile tool call", category: .ai)
    }

    func startInterview() async throws {
        await initializeSubscriptions()
        await sendInitialMessage()
    }

    func endInterview() {
        isActive = false
        Task {
            await llmMessenger.deactivate()
        }
    }

    func sendUserMessage(_ text: String) async throws {
        guard isActive else { return }

        await emit(.processingStateChanged(true))

        // Emit message request event (§4.3)
        var payload = JSON()
        payload["text"].string = text
        await emit(.llmSendUserMessage(payload: payload))
    }

    // MARK: - Dynamic Prompt Update (Phase 3)

    /// Update the system prompt when phases transition
    func updateSystemPrompt(_ text: String) async {
        await llmMessenger.updateSystemPrompt(text)
    }

    // MARK: - Model Configuration

    /// Set the model ID for the LLM messenger
    func setModelId(_ id: String) async {
        await llmMessenger.setModelId(id)
    }

}