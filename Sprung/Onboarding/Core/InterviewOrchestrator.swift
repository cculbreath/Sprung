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

    // Tool choice override for forcing specific tools (TODO: Move to LLMMessenger)
    private var nextToolChoiceOverride: ToolChoiceOverride?

    // Timeline tool names for special handling (TODO: Move to configuration)
    private let timelineToolNames: Set<String> = [
        "create_timeline_card",
        "update_timeline_card",
        "reorder_timeline_cards",
        "delete_timeline_card"
    ]

    private var isActive = false

    // MARK: - Initialization

    init(
        service: OpenAIService,
        systemPrompt: String,
        eventBus: EventCoordinator
    ) {
        self.service = service
        self.systemPrompt = systemPrompt
        self.eventBus = eventBus
        self.networkRouter = NetworkRouter(eventBus: eventBus)
        self.llmMessenger = LLMMessenger(
            service: service,
            systemPrompt: systemPrompt,
            eventBus: eventBus,
            networkRouter: networkRouter
        )
        Logger.info("🎯 InterviewOrchestrator initialized with LLMMessenger", category: .ai)
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

    // MARK: - Tool Continuation

    func resumeToolContinuation(id: UUID, payload: JSON) async throws {
        // Note: This method is deprecated - tool continuations now handled by ToolExecutionCoordinator
        // Kept for compatibility during migration
        Logger.warning("InterviewOrchestrator.resumeToolContinuation is deprecated", category: .ai)
    }

    // MARK: - Tool Continuation Management
    // Note: Tool execution and continuation management moved to ToolExecutionCoordinator (§4.6)
    // TODO: Move tool choice override and available tools logic to StateCoordinator/LLMMessenger

    // MARK: - Special Tool Handling

    func forceTimelineTools() async {
        nextToolChoiceOverride = ToolChoiceOverride(
            mode: .require(tools: Array(timelineToolNames))
        )
    }

    func resetToolChoice() async {
        nextToolChoiceOverride = ToolChoiceOverride(mode: .auto)
    }
}

private struct ToolChoiceOverride {
    enum Mode {
        case require(tools: [String])
        case auto
    }
    let mode: Mode
}