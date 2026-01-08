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
        case .toolCallRequested(let call, _):
            await handleToolCall(call)
        default:
            break
        }
    }
    // MARK: - Tool Execution
    /// Execute a tool call
    private func handleToolCall(_ call: ToolCall) async {
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
            // No separate developer message needed - tool response + content message suffice
            if toolName == "extract_document", output["artifact_record"] != .null {
                await emit(.artifactRecordProduced(record: output["artifact_record"]))
            }
            // Determine reasoning effort for specific tools
            // Hard tasks use elevated reasoning; all others use default from settings
            let hardTaskTools: Set<String> = [
                "validate_applicant_profile"
            ]
            let reasoningEffort: String? = {
                if let name = toolName, hardTaskTools.contains(name) {
                    return UserDefaults.standard.string(forKey: "onboardingInterviewHardTaskReasoningEffort") ?? "medium"
                }
                // All other tools use default reasoning (nil = LLMMessenger applies default from settings)
                return nil
            }()

            // Check for toolChoice chaining (next_required_tool forces the LLM to call a specific tool)
            let nextRequiredTool = output["next_required_tool"].string

            // Tool completed - send response to LLM (slot already filled above)
            await emitToolResponse(callId: callId, toolName: toolName, output: output, reasoningEffort: reasoningEffort, nextRequiredTool: nextRequiredTool)

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

            // Tool execution error
            var errorOutput = JSON()
            errorOutput["error"].string = error.localizedDescription
            errorOutput["status"].string = "incomplete"
            let errorOutputString = errorOutput.rawString() ?? "{}"

            // Fill ConversationLog slot with error result
            if let name = toolName {
                await stateCoordinator.addCompletedToolResult(callId: callId, toolName: name, output: errorOutputString)
            }

            await emitToolResponse(callId: callId, toolName: toolName, output: errorOutput)

        case .pendingUserAction:
            // Codex paradigm: UI tool presented, awaiting user action.
            // Don't send tool response yet - it will be sent when user acts.
            // Developer messages will be queued behind this pending tool.
            let pendingToolName = toolName ?? "unknown"

            // Check if there's already a pending UI tool call
            // If so, return incomplete status - don't lie about completion
            // (The LLM sometimes issues parallel identical UI tool calls in a batch)
            if let existingPending = await stateCoordinator.getPendingUIToolCall() {
                Logger.warning("⚠️ Duplicate UI tool call detected: \(pendingToolName) (callId: \(callId.prefix(8))) while \(existingPending.toolName) (callId: \(existingPending.callId.prefix(8))) is already pending", category: .ai)

                // Mark this duplicate operation as cancelled
                await operation.cancel(reason: "Duplicate UI tool call")

                // Return incomplete - be honest that this duplicate wasn't processed
                var output = JSON()
                output["status"].string = "incomplete"
                output["error"].string = "Duplicate request - \(existingPending.toolName) is already awaiting user response. Wait for user to complete the active prompt."
                await emitToolResponse(callId: callId, toolName: pendingToolName, output: output)
                Logger.info("⚠️ Duplicate UI tool call returned incomplete: \(pendingToolName)", category: .ai)
                return
            }

            // Set operation to awaiting user state
            // The UI dismiss handler will be set by the tool pane when it presents the UI
            await operation.setAwaitingUser()

            await stateCoordinator.setPendingUIToolCall(callId: callId, toolName: pendingToolName)
            Logger.info("🎯 UI tool pending user action: \(pendingToolName) (callId: \(callId.prefix(8)))", category: .ai)
        }
    }
    // MARK: - Event Emission
    /// Emit tool response to LLM
    /// - Parameters:
    ///   - callId: The tool call ID
    ///   - toolName: The tool name (for result storage)
    ///   - output: The tool output JSON
    ///   - reasoningEffort: Optional reasoning effort level
    ///   - nextRequiredTool: Optional tool name to force as toolChoice (for chaining)
    private func emitToolResponse(callId: String, toolName: String? = nil, output: JSON, reasoningEffort: String? = nil, nextRequiredTool: String? = nil) async {
        var payload = JSON()
        payload["callId"].string = callId
        if let name = toolName {
            payload["toolName"].string = name
        }
        payload["output"] = output
        if let effort = reasoningEffort {
            payload["reasoningEffort"].string = effort
        }
        if let nextTool = nextRequiredTool {
            payload["toolChoice"].string = nextTool
            Logger.info("🔗 Tool chaining: next required tool = \(nextTool)", category: .ai)
        }
        await emit(.llmToolResponseMessage(payload: payload))
        Logger.info("📤 Tool response sent to LLM (call: \(callId.prefix(8)))", category: .ai)
        Logger.debug("📤 Full tool response payload: callId=\(callId), output=\(output)", category: .ai)
    }
    /// Emit tool error
    private func emitToolError(callId: String, toolName: String, message: String) async {
        var errorOutput = JSON()
        errorOutput["error"].string = message
        errorOutput["status"].string = "incomplete"
        await emitToolResponse(callId: callId, toolName: toolName, output: errorOutput)
    }
}
