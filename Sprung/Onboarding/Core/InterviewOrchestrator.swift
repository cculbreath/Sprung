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
    private let llmMessenger: LLMMessenger
    private let networkRouter: NetworkRouter
    private let service: OpenAIService
    private let systemPrompt: String

    // Timeline tool names for special handling (TODO: Move to configuration)

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

    func startInterview() async throws {
        isActive = true
        await llmMessenger.activate()

        // Start event subscriptions
        await llmMessenger.startEventSubscriptions()
        // Note: Tool subscription now handled by ToolExecutionCoordinator

        await emit(.processingStateChanged(true))

        // Emit message request event (§4.3)
        var payload = JSON()
        payload["text"].string = "Begin the onboarding interview."
        await emit(.llmSendUserMessage(payload: payload))
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

}