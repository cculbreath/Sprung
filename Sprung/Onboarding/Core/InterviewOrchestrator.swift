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

    /// Send the initial message to start the interview
    func sendInitialMessage() async {
        guard isActive else {
            Logger.warning("InterviewOrchestrator not active, cannot send initial message", category: .ai)
            return
        }

        await emit(.processingStateChanged(true, statusMessage: "Starting interview..."))

        // Send user message to trigger conversational response
        // The system prompt's OPENING SEQUENCE section instructs the LLM to:
        // 1. Offer a warm welcome message
        // 2. Immediately invoke get_applicant_profile tool
        var payload = JSON()
        payload["text"].string = "I'm ready to begin."
        await emit(.llmSendUserMessage(payload: payload, isSystemGenerated: true))

        Logger.info("📤 Initial user message sent to trigger greeting and get_applicant_profile", category: .ai)
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