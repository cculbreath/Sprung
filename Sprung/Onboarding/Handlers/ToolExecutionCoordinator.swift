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
    func startEventSubscriptions() async {
        Task {
            for await event in await eventBus.stream(topic: .tool) {
                await handleToolEvent(event)
            }
        }

        // Small delay to ensure stream is connected
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms

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
        // First, check if we're in a waiting state
        let waitingState = await stateCoordinator.waitingState
        if let waitingState = waitingState {
            Logger.warning("🚫 Tool call '\(call.name)' blocked - system in waiting state: \(waitingState.rawValue)", category: .ai)
            await emitToolError(
                callId: call.callId,
                message: "Cannot execute tools while waiting for user input (state: \(waitingState.rawValue)). Please respond to the pending request first."
            )
            return
        }

        // Validate against allowed tools
        let allowedTools = await stateCoordinator.getAllowedToolsForCurrentPhase()
        guard allowedTools.contains(call.name) else {
            Logger.warning("🚫 Tool '\(call.name)' not allowed in current phase", category: .ai)
            await emitToolError(callId: call.callId, message: "Tool '\(call.name)' is not available in the current phase")
            return
        }

        // Execute tool
        Logger.debug("🔧 Executing tool: \(call.name)", category: .ai)
        do {
            let result = try await toolExecutor.handleToolCall(call)
            await handleToolResult(result, callId: call.callId, toolName: call.name)
        } catch {
            Logger.error("Tool execution failed: \(error)", category: .ai)
            await emitToolError(callId: call.callId, message: "Tool execution failed: \(error.localizedDescription)")
        }
    }

    /// Handle tool execution result
    private func handleToolResult(_ result: ToolResult, callId: String, toolName: String?) async {
        switch result {
        case .immediate(let output):
            // Special handling for extract_document tool - emit artifact record produced event
            if toolName == "extract_document", output["artifact_record"] != .null {
                await emit(.artifactRecordProduced(record: output["artifact_record"]))

                // Optional: Emit developer message about artifact storage
                var devPayload = JSON()
                devPayload["text"].string = "Developer status: Artifact stored"
                let artifactId = output["artifact_record"]["id"].stringValue
                devPayload["details"] = JSON([
                    "artifact_id": artifactId,
                    "status": "stored"
                ])
                devPayload["payload"] = output["artifact_record"]
                await emit(.llmSendDeveloperMessage(payload: devPayload))
            }

            // Tool completed - send response to LLM
            await emitToolResponse(callId: callId, output: output)

        case .waiting(_, let continuation):
            // Tool needs user input - store continuation and emit UI event
            pendingContinuations[continuation.id] = callId

            // Emit UI-specific events based on the tool's UI request
            if let uiRequest = continuation.uiRequest {
                await emitUIRequest(uiRequest, continuationId: continuation.id)
            }

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
            await handleToolResult(result, callId: callId, toolName: nil)
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
        Logger.verbose("payload.callId: \(callId), payload.output: \(output)")
    }

    /// Emit tool error
    private func emitToolError(callId: String, message: String) async {
        var errorOutput = JSON()
        errorOutput["error"].string = message
        errorOutput["status"].string = "error"
        await emitToolResponse(callId: callId, output: errorOutput)
    }

    /// Emit UI request events based on tool's UI needs
    private func emitUIRequest(_ request: ToolUIRequest, continuationId: UUID) async {
        switch request {
        case .choicePrompt(let prompt):
            await emit(.choicePromptRequested(prompt: prompt, continuationId: continuationId))
            Logger.info("📋 Choice prompt requested", category: .ai)

        case .uploadRequest(let uploadRequest):
            await emit(.uploadRequestPresented(request: uploadRequest, continuationId: continuationId))
            Logger.info("📤 Upload request presented", category: .ai)

        case .validationPrompt(let validationPrompt):
            await emit(.validationPromptRequested(prompt: validationPrompt, continuationId: continuationId))
            Logger.info("✅ Validation prompt requested", category: .ai)

        case .applicantProfileIntake:
            await emit(.applicantProfileIntakeRequested(continuationId: continuationId))
            Logger.info("👤 Applicant profile intake requested", category: .ai)

        case .sectionToggle(let request):
            await emit(.sectionToggleRequested(request: request, continuationId: continuationId))
            Logger.info("🔀 Section toggle requested", category: .ai)
        }
    }
}
