//
//  ToolExecutionCoordinator.swift
//  Sprung
//
//  Tool execution coordination (Spec §4.6)
//  Subscribes to tool call events and executes tools via ToolExecutor
//
import Foundation
import SwiftyJSON
/// Coordinates tool execution
/// Responsibilities (Spec §4.6):
/// - Subscribe to LLM.toolCallReceived events
/// - Validate tool names against State.allowedTools
/// - Execute tools via ToolExecutor
/// - Emit Tool.result and LLM.toolResponseMessage events
actor ToolExecutionCoordinator: OnboardingEventEmitter {
    // MARK: - Properties
    let eventBus: EventBus
    private let toolExecutor: ToolExecutor
    private let stateCoordinator: StateCoordinator
    private let ui: OnboardingUIState
    // MARK: - Initialization
    init(
        eventBus: EventBus,
        toolExecutor: ToolExecutor,
        stateCoordinator: StateCoordinator,
        ui: OnboardingUIState
    ) {
        self.eventBus = eventBus
        self.toolExecutor = toolExecutor
        self.stateCoordinator = stateCoordinator
        self.ui = ui
        Logger.info("🔧 ToolExecutionCoordinator initialized", category: .ai)
    }

    /// Install (or clear) the replay tool gateway on the underlying executor.
    /// During session replay, recorded tool results are served by callId and the
    /// real tools never execute.
    func setReplayToolGateway(_ gateway: ReplayToolGateway?) async {
        await toolExecutor.setReplayGateway(gateway)
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
        case .tool(.callRequested(let call, _)):
            await handleToolCall(call)
        default:
            break
        }
    }
    // MARK: - Tool Execution
    /// Execute a tool call
    private func handleToolCall(_ call: ToolCall) async {
        // Check if processing is stopped - discard tool call silently
        let isStopped = await MainActor.run { ui.isStopped }
        if isStopped {
            Logger.info("🛑 Tool call \(call.name) discarded (processing stopped)", category: .ai)
            // Fill a placeholder result so the conversation log doesn't have orphan tool calls
            await stateCoordinator.addCompletedToolResult(
                callId: call.callId,
                toolName: call.name,
                output: "[Discarded - processing stopped]"
            )
            return
        }

        // Validate tool availability using centralized gating logic
        let availability = await stateCoordinator.checkToolAvailability(call.name)

        switch availability {
        case .available:
            // Tool is available - proceed with execution
            Logger.debug("🔧 Executing tool: \(call.name)", category: .ai)

            // Create ToolOperation for lifecycle tracking
            let operation = ToolOperation(
                callId: call.callId,
                name: call.name,
                arguments: call.arguments.rawString() ?? "{}"
            )
            let tracker = await stateCoordinator.getOperationTracker()
            await tracker.register(operation)

            do {
                let executed = try await toolExecutor.handleToolCall(call)
                await handleToolResult(executed.result, callId: call.callId, toolName: call.name, operation: operation, mintedIds: executed.mintedIds)
            } catch {
                Logger.error("Tool execution failed: \(error)", category: .ai)
                await operation.fail(error: error)
                await emitToolFailure(
                    callId: call.callId,
                    toolName: call.name,
                    code: "tool_execution_failed",
                    reason: error.localizedDescription
                )
            }

        case .blocked(let reason):
            // Tool is blocked - structured result tells the LLM to wait for the user
            Logger.warning("🚫 Tool call '\(call.name)' blocked: \(reason)", category: .ai)
            await emitToolFailure(callId: call.callId, toolName: call.name, code: "tool_not_available", reason: reason)

        case .notAvailableYet(let reason):
            // Tool is in the phase schema (kept stable for prompt caching) but its
            // subphase conditions aren't met. Return a structured tool_result so
            // the model self-corrects instead of removing the tool from the schema.
            Logger.warning("⏳ Tool call '\(call.name)' not available yet: \(reason)", category: .ai)
            await emitToolFailure(callId: call.callId, toolName: call.name, code: "tool_not_available", reason: reason)
        }
    }
    /// Handle tool execution result. `mintedIds` are the determinism-seam ids the
    /// tool produced (teed to the tape so re-executable tools reproduce them on replay).
    private func handleToolResult(_ result: ToolResult, callId: String, toolName: String, operation: ToolOperation, mintedIds: [String]) async {
        switch result {
        case .immediate(let output):
            let outputString = output.rawString() ?? "{}"
            // Mark operation as completed
            await operation.complete(output: outputString)

            // Fill ConversationLog slot immediately (enables batch send when all slots filled)
            await stateCoordinator.addCompletedToolResult(callId: callId, toolName: toolName, output: outputString, mintedIds: mintedIds)

            // Special handling for extract_document tool - emit artifact record produced event
            // DocumentArtifactMessenger will batch and send the extracted content to the LLM
            if toolName == "extract_document", output["artifactRecord"] != .null {
                await emit(.artifact(.recordProduced(record: output["artifactRecord"])))
            }

            // Tool completed - send response to LLM (result already stored in ConversationLog above)
            await emitToolResponse(callId: callId, toolName: toolName)

            // Special handling for bootstrap tools - remove from allowed tools after use
            if output["disableAfterUse"].bool == true {
                await stateCoordinator.excludeTool(toolName)
                Logger.info("🚀 Bootstrap tool '\(toolName)' excluded from future tool calls", category: .ai)
            }
        case .error(let error):
            // Mark operation as failed
            await operation.fail(error: error)

            // Tool execution error - structured result stored in ConversationLog
            await emitToolFailure(
                callId: callId,
                toolName: toolName,
                code: "tool_execution_failed",
                reason: error.localizedDescription
            )
        }
    }
    // MARK: - Event Emission
    /// Emit tool response to LLM
    /// - Parameters:
    ///   - callId: The tool call ID
    ///   - toolName: The tool name (for logging)
    private func emitToolResponse(callId: String, toolName: String? = nil) async {
        var payload = JSON()
        payload["callId"].string = callId
        if let name = toolName {
            payload["toolName"].string = name
        }
        await emit(.llm(.toolResponseMessage(payload: payload)))
        Logger.info("📤 Tool response sent to LLM (call: \(callId.prefix(8)))", category: .ai)
    }
    /// Store a structured tool-failure result and notify the LLM.
    ///
    /// ONE machine-readable schema for every failure shape: {"error":<code>,"reason":<message>}
    /// (compact serialization, no "status" key). Codes:
    /// - "tool_not_available"   — tool is blocked or its subphase conditions aren't met
    /// - "tool_execution_failed" — the tool ran and threw / returned an error
    private func emitToolFailure(callId: String, toolName: String, code: String, reason: String) async {
        var output = JSON()
        output["error"].string = code
        output["reason"].string = reason
        let outputString = output.rawString(.utf8, options: [.sortedKeys]) ?? #"{"error":"\#(code)"}"#

        // Store in ConversationLog first, then emit response
        await stateCoordinator.addCompletedToolResult(callId: callId, toolName: toolName, output: outputString)
        await emitToolResponse(callId: callId, toolName: toolName)
    }
}
