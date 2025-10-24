//
//  InterviewOrchestrator.swift
//  Sprung
//
//  Coordinates the onboarding interview conversation with OpenAI's Responses API,
//  mediating tool execution and state persistence.
//

import Foundation
import SwiftyJSON
import SwiftOpenAI

actor InterviewOrchestrator {
    struct Callbacks {
        let updateProcessingState: @Sendable (Bool) async -> Void
        let emitAssistantMessage: @Sendable (String) async -> Void
        let handleWaitingState: @Sendable (InterviewSession.Waiting?) async -> Void
        let handleError: @Sendable (String) async -> Void
    }

    private let client: OpenAIService
    private let state: InterviewState
    private let toolExecutor: ToolExecutor
    private let checkpoints: Checkpoints
    private let callbacks: Callbacks
    private let systemPrompt: String

    private var conversationId: String?
    private var lastResponseId: String?
    private var currentModelId: String = "gpt-5"
    private var continuationCallIds: [UUID: String] = [:]

    init(
        client: OpenAIService,
        state: InterviewState,
        toolExecutor: ToolExecutor,
        checkpoints: Checkpoints,
        callbacks: Callbacks,
        systemPrompt: String
    ) {
        self.client = client
        self.state = state
        self.toolExecutor = toolExecutor
        self.checkpoints = checkpoints
        self.callbacks = callbacks
        self.systemPrompt = systemPrompt
    }

    func startInterview(modelId: String) async {
        currentModelId = modelId
        conversationId = nil
        lastResponseId = nil

        await callbacks.updateProcessingState(true)
        defer { Task { await self.callbacks.updateProcessingState(false) } }

        do {
            try await requestResponse(withUserMessage: "Let's begin the onboarding interview.")
        } catch {
            await callbacks.handleError("Failed to start interview: \(error.localizedDescription)")
        }
    }

    func sendUserMessage(_ text: String) async {
        await callbacks.updateProcessingState(true)
        defer { Task { await self.callbacks.updateProcessingState(false) } }

        do {
            try await requestResponse(withUserMessage: text)
        } catch {
            await callbacks.handleError("Failed to send message: \(error.localizedDescription)")
        }
    }

    func resumeToolContinuation(id: UUID, payload: JSON) async {
        await callbacks.updateProcessingState(true)
        defer { Task { await self.callbacks.updateProcessingState(false) } }

        do {
            let result = try await toolExecutor.resumeContinuation(id: id, with: payload)
            let callId = continuationCallIds.removeValue(forKey: id)
            await state.setWaiting(nil)
            await callbacks.handleWaitingState(nil)
            try await handleToolResult(result, callId: callId)
        } catch {
            await callbacks.handleError("Failed to resume tool: \(error.localizedDescription)")
        }
    }

    private func requestResponse(
        withUserMessage userMessage: String? = nil,
        functionOutputs: [InputType.FunctionToolCallOutput] = []
    ) async throws {
        var inputItems: [InputItem] = []

        if let userMessage {
            let contentItem = ContentItem.text(TextContent(text: userMessage))
            let inputMessage = InputMessage(role: "user", content: .array([contentItem]))
            inputItems.append(.message(inputMessage))
        }

        for output in functionOutputs {
            inputItems.append(.functionToolCallOutput(output))
        }

        guard !inputItems.isEmpty else {
            debugLog("No input items provided for response request.")
            return
        }

        let config = ModelProvider.forTask(.orchestrator)
        var textConfig = TextConfiguration(format: .text, verbosity: config.defaultVerbosity)

        var parameters = ModelResponseParameter(
            input: .array(inputItems),
            model: .custom(currentModelId),
            conversation: conversationId.map { .id($0) },
            instructions: conversationId == nil ? systemPrompt : nil,
            previousResponseId: lastResponseId,
            store: true,
            temperature: 0.7,
            text: textConfig
        )
        parameters.parallelToolCalls = false
        parameters.tools = toolExecutor.availableToolSchemas()
        if let effort = config.defaultReasoningEffort {
            parameters.reasoning = Reasoning(effort: effort)
        }

        let response = try await client.responseCreate(parameters)
        lastResponseId = response.id
        if let conversation = response.conversation {
            conversationId = extractConversationId(from: conversation)
        }

        try await handleResponse(response)
        let session = await state.currentSession()
        await checkpoints.save(from: session)
    }

    private func handleResponse(_ response: ResponseModel) async throws {
        for item in response.output {
            switch item {
            case .message(let message):
                let text = extractAssistantText(from: message)
                if !text.isEmpty {
                    await callbacks.emitAssistantMessage(text)
                }
            case .functionCall(let functionCall):
                try await handleFunctionCall(functionCall)
            default:
                continue
            }
        }
    }

    private func handleFunctionCall(_ functionCall: OutputItem.FunctionToolCall) async throws {
        let argumentsJSON = JSON(parseJSON: functionCall.arguments)
        guard argumentsJSON != .null else {
            await callbacks.handleError("Tool call \(functionCall.name) had invalid parameters.")
            return
        }

        let callId = functionCall.callId
        let identifier = functionCall.id ?? callId
        let call = ToolCall(id: identifier, name: functionCall.name, arguments: argumentsJSON, callId: callId)
        let result = try await toolExecutor.handleToolCall(call)

        try await handleToolResult(result, callId: callId, toolName: functionCall.name)
    }

    private func handleToolResult(
        _ result: ToolResult,
        callId: String?,
        toolName: String? = nil
    ) async throws {
        switch result {
        case .immediate(let json):
            guard let callId else { return }
            try await sendToolOutput(callId: callId, output: json)
        case .waiting(_, let token):
            if let callId {
                continuationCallIds[token.id] = callId
            }
            let waitingState = waitingState(for: toolName)
            await state.setWaiting(waitingState)
            await callbacks.handleWaitingState(waitingState)
        case .error(let error):
            await callbacks.handleError("Tool error: \(error)")
        }
    }

    private func sendToolOutput(callId: String, output: JSON) async throws {
        guard let outputString = output.rawString(.withoutEscapingSlashes) else {
            throw NSError(domain: "InterviewOrchestrator", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Failed to encode tool output as JSON string."
            ])
        }

        let functionOutput = InputType.FunctionToolCallOutput(callId: callId, output: outputString)
        try await requestResponse(functionOutputs: [functionOutput])
    }

    private func extractAssistantText(from message: OutputItem.Message) -> String {
        message.content.compactMap { content -> String? in
            if case let .outputText(output) = content {
                return output.text
            }
            return nil
        }
        .joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractConversationId(from conversation: Conversation) -> String {
        switch conversation {
        case .id(let identifier):
            return identifier
        case .object(let object):
            return object.id
        }
    }

    private func waitingState(for toolName: String?) -> InterviewSession.Waiting? {
        guard let toolName else { return nil }
        switch toolName {
        case "get_user_option":
            return .selection
        case "submit_for_validation":
            return .validation
        default:
            return nil
        }
    }
}
