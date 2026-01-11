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
    let eventBus: EventCoordinator
    private let toolExecutor: ToolExecutor
    private let stateCoordinator: StateCoordinator
    private let ui: OnboardingUIState
    // MARK: - Initialization
    init(
        eventBus: EventCoordinator,
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
            await stateCoordinator.fillToolResponseSlot(
                callId: call.callId,
                result: "[Discarded - processing stopped]",
                status: .skipped
            )
            await emit(.tool(.resultEmitted(callId: call.callId, result: "[Discarded - processing stopped]", statusMessage: nil)))
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
                let result = try await toolExecutor.handleToolCall(call)
                await handleToolResult(result, callId: call.callId, toolName: call.name, operation: operation)
            } catch {
                Logger.error("Tool execution failed: \(error)", category: .ai)
                await operation.fail(error: error)
                await emitToolError(callId: call.callId, toolName: call.name, message: "Tool execution failed: \(error.localizedDescription)")
            }

        case .blocked(let reason):
            // Tool is blocked - emit error telling LLM to wait for user
            Logger.warning("🚫 Tool call '\(call.name)' blocked: \(reason)", category: .ai)
            await emitToolError(callId: call.callId, toolName: call.name, message: reason)
        }
    }
    /// Handle tool execution result
    private func handleToolResult(_ result: ToolResult, callId: String, toolName: String?, operation: ToolOperation) async {
        switch result {
        case .immediate(let output):
            let outputString = output.rawString() ?? "{}"
            // Mark operation as completed
            await operation.complete(output: outputString)

            // Fill ConversationLog slot immediately (enables batch send when all slots filled)
            if let name = toolName {
                await stateCoordinator.addCompletedToolResult(callId: callId, toolName: name, output: outputString)
            }

            // Special handling for extract_document tool - emit artifact record produced event
            // DocumentArtifactMessenger will batch and send the extracted content to the LLM
            if toolName == "extract_document", output["artifact_record"] != .null {
                await emit(.artifact(.recordProduced(record: output["artifact_record"])))
            }

            // Tool completed - send response to LLM (result already stored in ConversationLog above)
            await emitToolResponse(callId: callId, toolName: toolName)

            // Special handling for bootstrap tools - remove from allowed tools after use
            if output["disable_after_use"].bool == true {
                if let name = toolName {
                    await stateCoordinator.excludeTool(name)
                    Logger.info("🚀 Bootstrap tool '\(name)' excluded from future tool calls", category: .ai)
                }
            }
        case .error(let error):
            // Mark operation as failed
            await operation.fail(error: error)

            // Tool execution error - store in ConversationLog
            var errorOutput = JSON()
            errorOutput["error"].string = error.localizedDescription
            errorOutput["status"].string = "incomplete"
            let errorOutputString = errorOutput.rawString() ?? "{}"

            if let name = toolName {
                await stateCoordinator.addCompletedToolResult(callId: callId, toolName: name, output: errorOutputString)
            }

            await emitToolResponse(callId: callId, toolName: toolName)
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
    /// Emit tool error
    private func emitToolError(callId: String, toolName: String, message: String) async {
        var errorOutput = JSON()
        errorOutput["error"].string = message
        errorOutput["status"].string = "incomplete"
        let errorOutputString = errorOutput.rawString() ?? "{}"

        // Store in ConversationLog first, then emit response
        await stateCoordinator.addCompletedToolResult(callId: callId, toolName: toolName, output: errorOutputString)
        await emitToolResponse(callId: callId, toolName: toolName)
    }
}
