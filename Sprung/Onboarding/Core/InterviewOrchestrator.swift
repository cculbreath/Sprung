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
/// All communication happens through events - clean unidirectional flow.
actor InterviewOrchestrator: OnboardingEventEmitter {
    // MARK: - Properties

    let eventBus: OnboardingEventBus
    private let service: OpenAIService
    private let systemPrompt: String

    // Conversation state
    private var conversationId: String?
    private var lastResponseId: String?
    private var currentModelId: String = "gpt-5"

    // Tool execution tracking
    private var continuationCallIds: [UUID: String] = [:]
    private var continuationToolNames: [UUID: String] = [:]

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

    private struct StreamBuffer {
        var messageId: UUID
        var text: String
        var pendingFragment: String
        var startedAt: Date
        var firstDeltaLogged: Bool
    }

    private var streamingBuffers: [String: StreamBuffer] = [:]
    private var messageIds: [String: UUID] = [:]
    private var lastMessageUUID: UUID?
    private var isActive = false

    // MARK: - Initialization

    init(
        service: OpenAIService,
        systemPrompt: String,
        eventBus: OnboardingEventBus
    ) {
        self.service = service
        self.systemPrompt = systemPrompt
        self.eventBus = eventBus
        Logger.info("🎯 InterviewOrchestrator initialized with event bus", category: .ai)
    }

    // MARK: - Interview Control

    func startInterview() async throws {
        isActive = true
        conversationId = nil
        lastResponseId = nil

        await emit(.processingStateChanged(true))
        defer {
            Task {
                await emit(.processingStateChanged(false))
            }
        }

        // Let the LLM drive the conversation via tool calls
        do {
            try await requestResponse(withUserMessage: "Begin the onboarding interview.")
        } catch {
            await emit(.errorOccurred("Failed to start interview: \(error.localizedDescription)"))
            throw error
        }
    }

    func endInterview() {
        isActive = false
        conversationId = nil
        lastResponseId = nil
        streamingBuffers.removeAll()
        continuationCallIds.removeAll()
        continuationToolNames.removeAll()
    }

    func sendUserMessage(_ text: String) async throws {
        guard isActive else { return }

        await emit(.processingStateChanged(true))
        defer {
            Task {
                await emit(.processingStateChanged(false))
            }
        }

        do {
            try await requestResponse(withUserMessage: text)
        } catch {
            await emit(.errorOccurred("Failed to send message: \(error.localizedDescription)"))
            throw error
        }
    }

    // MARK: - Tool Continuation

    func resumeToolContinuation(id: UUID, payload: JSON) async throws {
        await emit(.processingStateChanged(true))
        defer {
            Task {
                await emit(.processingStateChanged(false))
            }
        }

        // Clear waiting state
        await emit(.waitingStateChanged(nil))

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

        do {
            let stream = try await service.responseCreateStream(request)
            for try await event in stream {
                await handleResponseEvent(event)
            }
        } catch {
            await emit(.errorOccurred("API Error: \(error.localizedDescription)"))
            throw error
        }
    }

    private func buildRequest(
        userMessage: String?,
        toolOutput: JSON?,
        callId: String?
    ) -> ModelResponseParameter {
        var inputItems: [InputItem] = []

        // Add system prompt
        inputItems.append(.message(InputMessage(
            role: "developer",
            content: .text(systemPrompt)
        )))

        // Add user message if provided
        if let text = userMessage {
            inputItems.append(.message(InputMessage(
                role: "user",
                content: .text(text)
            )))
        }

        // Add tool output if provided
        if let output = toolOutput, let callId = callId {
            inputItems.append(.functionToolCallOutput(FunctionToolCallOutput(
                callId: callId,
                output: output.rawString() ?? "{}"
            )))
        }

        // Build tool configuration
        let tools = buildAvailableTools()

        // Apply tool choice override if set
        let toolChoice: ToolChoiceMode?
        if let override = nextToolChoiceOverride {
            nextToolChoiceOverride = nil
            switch override.mode {
            case .require(let toolNames):
                if let toolName = toolNames.first {
                    toolChoice = .function(name: toolName)
                } else {
                    toolChoice = .auto
                }
            case .auto:
                toolChoice = .auto
            }
        } else {
            toolChoice = .auto
        }

        return ModelResponseParameter(
            input: .array(inputItems),
            model: .custom(currentModelId),
            stream: true,
            toolChoice: toolChoice,
            tools: tools
        )
    }

    private func buildAvailableTools() -> [Tool] {
        // Get current phase tools (simplified - no state dependency)
        let phaseTools = [
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
        ]

        return phaseTools.map { toolName in
            Tool.function(FunctionTool(
                name: toolName,
                parameters: JSONSchema(type: .object, properties: [:]),
                description: "Tool: \(toolName)"
            ))
        }
    }

    // MARK: - Event Stream Processing

    private func handleResponseEvent(_ event: ResponseStreamEvent) async {
        switch event {
        case .responseFailed(let failed):
            let message = failed.response.error?.message ?? "Response failed"
            await emit(.errorOccurred("Stream error: \(message)"))

        case .responseCompleted(let completed):
            await finalizePendingMessages()
            conversationId = completed.response.id
            lastResponseId = completed.response.id

        case .responseInProgress(let inProgress):
            // Process deltas from in-progress response
            for item in inProgress.response.output {
                switch item {
                case .message(let message):
                    for contentItem in message.content {
                        switch contentItem {
                        case .text(let text):
                            await processContentDelta(0, text.text)
                        default:
                            break
                        }
                    }
                case .functionToolCall(let toolCall):
                    await processToolCall(toolCall)
                default:
                    break
                }
            }

        case .responseCreated, .responseIncomplete:
            // These events don't need special handling for our use case
            break

        default:
            break
        }
    }

    private func processContentDelta(_ index: Int, _ text: String) async {
        let itemId = "message_\(index)"

        if streamingBuffers[itemId] == nil {
            let messageId = UUID()
            await emit(.streamingMessageBegan(id: messageId, text: "", reasoningExpected: false))
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

        await emit(.streamingMessageUpdated(id: buffer.messageId, delta: buffer.pendingFragment))
        buffer.pendingFragment = ""
        streamingBuffers[itemId] = buffer
    }

    private func processToolCall(_ toolCall: FunctionToolCall) async {
        let functionName = toolCall.name
        let arguments = toolCall.arguments

        // Convert arguments string to JSON
        let argsJSON = JSON(parseJSON: arguments)

        let call = ToolCall(
            id: UUID().uuidString,
            name: functionName,
            arguments: argsJSON,
            callId: toolCall.id
        )

        await emit(.toolCallRequested(call))

        // Set waiting state based on tool
        let waitingState = waitingStateForTool(functionName)
        await emit(.waitingStateChanged(waitingState))

        // Store continuation info
        let continuationId = UUID()
        continuationCallIds[continuationId] = toolCall.id
        continuationToolNames[continuationId] = functionName
        await emit(.toolContinuationNeeded(id: continuationId, toolName: functionName))
    }

    private func finalizePendingMessages() async {
        for (_, buffer) in streamingBuffers {
            await emit(.streamingMessageFinalized(id: buffer.messageId, finalText: buffer.text))
        }

        streamingBuffers.removeAll()
        messageIds.removeAll()
        lastMessageUUID = nil
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