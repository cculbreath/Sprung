//
//  InterviewOrchestrator.swift
//  Sprung
//
//  Coordinates the onboarding interview conversation with OpenAI's Responses API.
//  State management is handled entirely through callbacks - this just orchestrates the flow.
//

import Foundation
import SwiftyJSON
import SwiftOpenAI

private struct ToolChoiceOverride {
    enum Mode {
        case require(tools: [String])
        case auto
    }
    let mode: Mode
}

/// Orchestrates the interview conversation with the LLM.
/// All state is managed externally via callbacks - this is purely orchestration.
actor InterviewOrchestrator {
    // MARK: - Error Handling

    private func formatError(_ error: Error) -> String {
        if let apiError = error as? APIError {
            return apiError.displayDescription
        }
        return error.localizedDescription
    }

    // MARK: - Callbacks

    struct Callbacks {
        let updateProcessingState: @Sendable (Bool) async -> Void
        let emitAssistantMessage: @Sendable (String, Bool) async -> UUID
        let beginStreamingAssistantMessage: @Sendable (String, Bool) async -> UUID
        let updateStreamingAssistantMessage: @Sendable (UUID, String) async -> Void
        let finalizeStreamingAssistantMessage: @Sendable (UUID, String) async -> Void
        let updateReasoningSummary: @Sendable (UUID, String, Bool) async -> Void
        let finalizeReasoningSummaries: @Sendable ([UUID]) async -> Void
        let updateStreamingStatus: @Sendable (String?) async -> Void
        let handleWaitingState: @Sendable (String?) async -> Void
        let handleError: @Sendable (String) async -> Void
        let storeApplicantProfile: @Sendable (JSON) async -> Void
        let storeSkeletonTimeline: @Sendable (JSON) async -> Void
        let updateEnabledSections: @Sendable (Set<String>) async -> Void
        let persistCheckpoint: @Sendable () async -> Void
        let getObjectiveStatus: @Sendable (String) async -> String?
        let processToolCall: @Sendable (ToolCall) async -> JSON?
    }

    // MARK: - Properties

    private let service: OpenAIService
    private let systemPrompt: String
    private let callbacks: Callbacks

    // Conversation state
    private var conversationId: String?
    private var lastResponseId: String?
    private var currentModelId: String = "gpt-5"

    // Tool execution tracking
    private var continuationCallIds: [UUID: String] = [:]
    private var continuationToolNames: [UUID: String] = [:]
    private var pendingToolContinuations: [UUID: CheckedContinuation<JSON, Error>] = [:]

    // Cached data for quick reference
    private var applicantProfileData: JSON?
    private var skeletonTimelineData: JSON?

    // Tool choice override for forcing specific tools
    private var nextToolChoiceOverride: ToolChoiceOverride?

    // Timeline tool names for special handling
    private let timelineToolNames: Set<String> = [
        "create_timeline_card",
        "update_timeline_card",
        "reorder_timeline_cards",
        "delete_timeline_card"
    ]

    // Phase-specific tool allowlists
    private let allowedToolsMap: [String: [String]] = [
        "phase1": [
            "get_user_option",
            "get_applicant_profile",
            "get_user_upload",
            "get_macos_contact_card",
            "extract_document",
            "list_artifacts",
            "get_artifact",
            "cancel_user_upload",
            "request_raw_file",
            "create_timeline_card",
            "update_timeline_card",
            "reorder_timeline_cards",
            "delete_timeline_card",
            "submit_for_validation",
            "persist_data",
            "set_objective_status",
            "next_phase"
        ],
        "phase2": [
            "get_user_option",
            "get_user_upload",
            "extract_document",
            "list_artifacts",
            "get_artifact",
            "cancel_user_upload",
            "request_raw_file",
            "submit_for_validation",
            "persist_data",
            "set_objective_status",
            "next_phase",
            "generate_knowledge_card"
        ],
        "phase3": [
            "get_user_option",
            "get_user_upload",
            "extract_document",
            "list_artifacts",
            "get_artifact",
            "cancel_user_upload",
            "request_raw_file",
            "submit_for_validation",
            "persist_data",
            "set_objective_status",
            "next_phase"
        ]
    ]

    private struct StreamBuffer {
        var messageId: UUID
        var text: String
        var pendingFragment: String
        var startedAt: Date
        var firstDeltaLogged: Bool
    }

    private var streamingBuffers: [String: StreamBuffer] = [:]
    private var reasoningSummaryBuffers: [String: String] = [:]
    private var reasoningSummaryFinalized: Set<String> = []
    private var messageIds: [String: UUID] = [:]
    private var pendingSummaryByItem: [String: String] = [:]
    private var appendedMessageUUIDs: [UUID] = []
    private var pendingSummaryFragments: [String] = []
    private var lastMessageUUID: UUID?
    private var isActive = false

    // MARK: - Initialization

    init(
        state: InterviewState,  // Temporary - will be removed completely in final cleanup
        service: OpenAIService,
        systemPrompt: String,
        callbacks: Callbacks
    ) {
        self.service = service
        self.systemPrompt = systemPrompt
        self.callbacks = callbacks
    }

    // MARK: - Interview Control

    func startInterview() async throws {
        isActive = true
        conversationId = nil
        lastResponseId = nil

        // Let the LLM drive the conversation via tool calls
        try await requestResponse(withUserMessage: "Begin the onboarding interview.")
    }

    func endInterview() {
        isActive = false
        conversationId = nil
        lastResponseId = nil
        streamingBuffers.removeAll()
        reasoningSummaryBuffers.removeAll()
        continuationCallIds.removeAll()
        continuationToolNames.removeAll()
    }

    func sendUserMessage(_ text: String) async throws {
        guard isActive else { return }
        await callbacks.updateProcessingState(true)
        defer { Task { await self.callbacks.updateProcessingState(false) } }

        try await requestResponse(withUserMessage: text)
    }

    // MARK: - Tool Continuation

    func resumeToolContinuation(id: UUID, payload: JSON) async throws {
        await callbacks.updateProcessingState(true)
        defer { Task { await self.callbacks.updateProcessingState(false) } }

        // Complete the pending continuation
        if let continuation = pendingToolContinuations.removeValue(forKey: id) {
            continuation.resume(returning: payload)
        }

        // Clear waiting state
        await callbacks.handleWaitingState(nil)

        // Continue the conversation
        if let callId = continuationCallIds.removeValue(forKey: id) {
            try await requestResponse(withToolOutput: payload, callId: callId)
        }
    }

    // MARK: - Response Handling

    private func requestResponse(
        withUserMessage text: String? = nil,
        withToolOutput output: JSON? = nil,
        callId: String? = nil
    ) async throws {
        guard isActive else { return }

        let request = buildRequest(
            userMessage: text,
            toolOutput: output,
            callId: callId
        )

        let responsesTask = Task {
            try await service.createAsyncRun(request: request)
        }

        do {
            for try await event in try await responsesTask.value {
                await handleResponseEvent(event)
            }
        } catch let error as APIError {
            if error.message?.contains("invalid model id") == true {
                await callbacks.handleError("Invalid model selected. Please check settings.")
            } else {
                throw error
            }
        }
    }

    private func buildRequest(
        userMessage: String?,
        toolOutput: JSON?,
        callId: String?
    ) -> ResponseCreateRequest {
        var messages: [Message] = []

        // Add system prompt
        messages.append(.system(content: .text(systemPrompt)))

        // Add user message if provided
        if let text = userMessage {
            messages.append(.user(content: .text(text)))
        }

        // Add tool output if provided
        if let output = toolOutput, let callId = callId {
            let content = MessageContent.toolOutput(
                ToolOutput(
                    toolCallId: callId,
                    output: output.rawString() ?? "{}"
                )
            )
            messages.append(.user(content: content))
        }

        // Build tool configuration
        let tools = buildAvailableTools()

        // Apply tool choice override if set
        let toolChoice: ResponseToolChoice = if let override = nextToolChoiceOverride {
            nextToolChoiceOverride = nil
            switch override.mode {
            case .require(let toolNames):
                .required(tools.filter { toolNames.contains($0.name) })
            case .auto:
                .auto
            }
        } else {
            .auto
        }

        return ResponseCreateRequest(
            model: currentModelId,
            modalities: [.text],
            messages: messages,
            tools: tools,
            toolChoice: toolChoice,
            metadata: conversationId.map { ["conversationId": $0] } ?? [:],
            stream: true
        )
    }

    private func buildAvailableTools() -> [ToolDefinition] {
        // Get current phase tools (simplified - no state dependency)
        let phaseTools = allowedToolsMap["phase1"] ?? []

        return phaseTools.compactMap { toolName in
            // Build tool definitions
            // This will be expanded with actual tool schemas
            ToolDefinition(
                type: "function",
                function: ToolFunction(
                    name: toolName,
                    description: "Tool: \(toolName)",
                    parameters: .init(type: .object, properties: [:])
                )
            )
        }
    }

    // MARK: - Event Stream Processing

    private func handleResponseEvent(_ event: ResponseStreamEvent) async {
        switch event {
        case .created(let response):
            conversationId = response.id
            lastResponseId = response.id

        case .done(let response):
            await finalizePendingMessages()
            conversationId = response.id
            lastResponseId = response.id

        case .contentDelta(let delta):
            await processContentDelta(delta)

        case .reasoning(let reasoning):
            await processReasoning(reasoning)

        case .toolCallDelta(let delta):
            await processToolCallDelta(delta)

        case .toolCallDone(let toolCall):
            await processToolCall(toolCall)

        default:
            break
        }
    }

    private func processContentDelta(_ delta: ResponseContentDelta) async {
        guard case .text(let text) = delta.content else { return }

        let itemId = delta.contentId
        if streamingBuffers[itemId] == nil {
            let messageId = await callbacks.beginStreamingAssistantMessage("", false)
            streamingBuffers[itemId] = StreamBuffer(
                messageId: messageId,
                text: "",
                pendingFragment: "",
                startedAt: Date(),
                firstDeltaLogged: false
            )
            messageIds[itemId] = messageId
            lastMessageUUID = messageId
        }

        guard var buffer = streamingBuffers[itemId] else { return }
        buffer.text += text
        buffer.pendingFragment += text

        await callbacks.updateStreamingAssistantMessage(buffer.messageId, buffer.pendingFragment)
        buffer.pendingFragment = ""
        streamingBuffers[itemId] = buffer
    }

    private func processReasoning(_ reasoning: ResponseReasoning) async {
        let summaryText = reasoning.summary
            .map(\.text)
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !summaryText.isEmpty else { return }

        if let currentMessage = lastMessageUUID {
            await callbacks.updateReasoningSummary(currentMessage, summaryText, true)
        } else if let mappedMessage = messageIds[reasoning.id] {
            await callbacks.updateReasoningSummary(mappedMessage, summaryText, true)
        } else {
            pendingSummaryFragments.append(summaryText)
        }
    }

    private func processToolCallDelta(_ delta: ResponseToolCallDelta) async {
        // Tool call deltas can be used for progress tracking
        // Currently not implemented
    }

    private func processToolCall(_ toolCall: ResponseToolCall) async {
        guard case .function(let call) = toolCall else { return }

        // Process the tool call through callbacks
        if let result = await callbacks.processToolCall(ToolCall(
            id: toolCall.id,
            type: "function",
            function: FunctionCall(
                name: call.name,
                arguments: call.arguments
            )
        )) {
            // Tool returned immediate result
            do {
                try await requestResponse(
                    withToolOutput: result,
                    callId: toolCall.id
                )
            } catch {
                await callbacks.handleError("Tool execution failed: \(error)")
            }
        } else {
            // Tool requires user interaction - will resume later
            let waitingState = waitingStateForTool(call.name)
            await callbacks.handleWaitingState(waitingState)
        }
    }

    private func finalizePendingMessages() async {
        for (itemId, buffer) in streamingBuffers {
            await callbacks.finalizeStreamingAssistantMessage(buffer.messageId, buffer.text)

            // Apply any pending reasoning summaries
            if let summary = pendingSummaryByItem[itemId] {
                await callbacks.updateReasoningSummary(buffer.messageId, summary, true)
                pendingSummaryByItem.removeValue(forKey: itemId)
            }
        }

        streamingBuffers.removeAll()
        messageIds.removeAll()
        lastMessageUUID = nil
        pendingSummaryFragments.removeAll()
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

// Temporary shim for InterviewState - will be removed in final cleanup
actor InterviewState {
    func setWaiting(_ waiting: String?) async {}
    func currentSession() async -> InterviewSession { InterviewSession() }
    func completeObjective(_ id: String) async {}
}

// Temporary shim for InterviewSession - will be removed in final cleanup
struct InterviewSession {
    enum Waiting: String { case selection, upload, validation }
    struct ObjectiveEntry {
        let id: String
        let status: OnboardingState.ObjectiveStatus
        let source: String
        let timestamp: Date
        let notes: String?
    }
    var phase: InterviewPhase = .phase1CoreFacts
    var objectivesDone: Set<String> = []
    var waiting: Waiting?
    var objectiveLedger: [ObjectiveEntry] = []
}