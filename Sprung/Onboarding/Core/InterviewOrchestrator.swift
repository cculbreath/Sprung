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

    // Tool execution tracking (continuations)
    private var continuationCallIds: [UUID: String] = [:]
    private var continuationToolNames: [UUID: String] = [:]

    // Cached data for quick reference (TODO: Move to StateCoordinator)
    private var applicantProfileData: JSON?
    private var skeletonTimelineData: JSON?

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
        startToolSubscription()

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
        continuationCallIds.removeAll()
        continuationToolNames.removeAll()
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
        await emit(.processingStateChanged(true))

        // Clear waiting state
        await emit(.waitingStateChanged(nil))

        // Get the call ID for this continuation
        guard let callId = continuationCallIds.removeValue(forKey: id) else {
            Logger.warning("No continuation found for id: \(id)", category: .ai)
            return
        }

        // Emit tool response event (§4.3)
        var responsePayload = JSON()
        responsePayload["callId"].string = callId
        responsePayload["output"] = payload
        await emit(.llmToolResponseMessage(payload: responsePayload))
    }

    // MARK: - Tool Continuation Management
    // Note: Request building moved to LLMMessenger (§4.3)
    // TODO: Move tool choice override and available tools logic to StateCoordinator/LLMMessenger

    /// Subscribe to tool call events and manage continuations
    func startToolSubscription() {
        Task {
            for await event in await eventBus.stream(topic: .tool) {
                if case .toolCallRequested(let call) = event {
                    await handleToolCall(call)
                }
            }
        }
    }

    private func handleToolCall(_ call: ToolCall) async {
        // Set waiting state based on tool
        let waitingState = waitingStateForTool(call.name)
        await emit(.waitingStateChanged(waitingState))

        // Store continuation info
        let continuationId = UUID()
        continuationCallIds[continuationId] = call.callId
        continuationToolNames[continuationId] = call.name
        await emit(.toolContinuationNeeded(id: continuationId, toolName: call.name))
    }

    private func waitingStateForTool(_ toolName: String) -> String? {
        switch toolName {
        case "get_user_option":
            return "selection"
        case "get_user_upload":
            return "upload"
        case "submit_for_validation":
            return "validation"
        case "extract_document":
            return "extraction"
        default:
            return nil
        }
    }

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