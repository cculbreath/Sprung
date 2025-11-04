//
//  ToolExecutionCoordinator.swift
//  Sprung
//
//  Tool execution coordination (Spec §4.6)
//  Subscribes to tool call events and executes tools via ToolExecutor
//

import Foundation
import SwiftyJSON

/// Coordinates tool execution and continuation management
/// Responsibilities (Spec §4.6):
/// - Subscribe to LLM.toolCallReceived events
/// - Validate tool names against State.allowedTools
/// - Execute tools via ToolExecutor
/// - Manage continuation tokens
/// - Emit Tool.result and LLM.toolResponseMessage events
actor ToolExecutionCoordinator: OnboardingEventEmitter {
    // MARK: - Properties

    let eventBus: EventCoordinator
    private let toolExecutor: ToolExecutor
    private let stateCoordinator: StateCoordinator

    // Track pending continuations
    private var pendingContinuations: [UUID: String] = [:] // continuationId -> callId

    // MARK: - Initialization

    init(
        eventBus: EventCoordinator,
        toolExecutor: ToolExecutor,
        stateCoordinator: StateCoordinator
    ) {
        self.eventBus = eventBus
        self.toolExecutor = toolExecutor
        self.stateCoordinator = stateCoordinator
        Logger.info("🔧 ToolExecutionCoordinator initialized", category: .ai)
    }

    // MARK: - Event Subscriptions

    /// Start listening to tool call events
    func startEventSubscriptions() {
        Task {
            for await event in await eventBus.stream(topic: .tool) {
                await handleToolEvent(event)
            }
        }

        Logger.info("📡 ToolExecutionCoordinator subscribed to tool events", category: .ai)
    }

    // MARK: - Event Handlers

    private func handleToolEvent(_ event: OnboardingEvent) async {
        switch event {
        case .toolCallRequested(let call):
            await handleToolCall(call)

        case .toolContinuationNeeded(let id, let toolName):
            // This event is emitted by InterviewOrchestrator for continuations
            // The actual continuation resumption happens via resumeToolContinuation
            Logger.debug("Tool continuation needed: \(toolName) (\(id))", category: .ai)

        default:
            break
        }
    }

    // MARK: - Tool Execution

    /// Execute a tool call
    private func handleToolCall(_ call: ToolCall) async {
        // Validate against allowed tools
        let allowedTools = await stateCoordinator.getAllowedToolsForCurrentPhase()
        guard allowedTools.contains(call.name) else {
            Logger.warning("Tool '\(call.name)' not allowed in current phase", category: .ai)
            await emitToolError(callId: call.callId, message: "Tool '\(call.name)' is not available in the current phase")
            return
        }

        // Execute tool
        do {
            let result = try await toolExecutor.handleToolCall(call)
            await handleToolResult(result, callId: call.callId)
        } catch {
            Logger.error("Tool execution failed: \(error)", category: .ai)
            await emitToolError(callId: call.callId, message: "Tool execution failed: \(error.localizedDescription)")
        }
    }

    /// Handle tool execution result
    private func handleToolResult(_ result: ToolResult, callId: String) async {
        switch result {
        case .immediate(let output):
            // Tool completed immediately - send response to LLM
            await emitToolResponse(callId: callId, output: output)

        case .waiting(let message, let continuation):
            // Tool needs user input - store continuation and emit UI event
            pendingContinuations[continuation.id] = callId
            await emit(.toolContinuationNeeded(id: continuation.id, toolName: continuation.toolName))
            Logger.info("🔄 Tool waiting for user input: \(continuation.toolName)", category: .ai)

        case .error(let error):
            // Tool execution error
            var errorOutput = JSON()
            errorOutput["error"].string = error.localizedDescription
            errorOutput["status"].string = "error"
            await emitToolResponse(callId: callId, output: errorOutput)
        }
    }

    // MARK: - Continuation Management

    /// Resume a tool continuation with user input
    func resumeToolContinuation(id: UUID, userInput: JSON) async throws {
        guard let callId = pendingContinuations.removeValue(forKey: id) else {
            throw ToolError.invalidParameters("No pending continuation for id: \(id)")
        }

        // Resume the continuation
        do {
            let result = try await toolExecutor.resumeContinuation(id: id, with: userInput)
            await handleToolResult(result, callId: callId)
        } catch {
            Logger.error("Continuation resumption failed: \(error)", category: .ai)
            await emitToolError(callId: callId, message: "Continuation failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Event Emission

    /// Emit tool response to LLM
    private func emitToolResponse(callId: String, output: JSON) async {
        var payload = JSON()
        payload["callId"].string = callId
        payload["output"] = output

        await emit(.llmToolResponseMessage(payload: payload))
        Logger.info("📤 Tool response sent to LLM (call: \(callId.prefix(8)))", category: .ai)
    }

    /// Emit tool error
    private func emitToolError(callId: String, message: String) async {
        var errorOutput = JSON()
        errorOutput["error"].string = message
        errorOutput["status"].string = "error"
        await emitToolResponse(callId: callId, output: errorOutput)
    }
}
