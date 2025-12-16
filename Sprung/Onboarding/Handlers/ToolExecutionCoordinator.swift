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
        // First, check if we're in a waiting state
        let waitingState = await stateCoordinator.waitingState
        if let waitingState = waitingState {
            // Allow timeline tools during validation state (for real-time card creation)
            let timelineTools = ["create_timeline_card", "update_timeline_card", "delete_timeline_card", "reorder_timeline_cards"]
            let isTimelineTool = timelineTools.contains(call.name)
            let isValidationState = waitingState == .validation
            let isExtractionState = waitingState == .extraction

            // Allow ALL tools during extraction state (for dossier question collection)
            if isExtractionState {
                Logger.info("✅ Tool '\(call.name)' allowed during extraction state (dossier collection)", category: .ai)
            } else if isTimelineTool && isValidationState {
                // Allow timeline tools during validation state
                Logger.info("✅ Timeline tool '\(call.name)' allowed during validation state", category: .ai)
            } else {
                // Block tools during other waiting states
                Logger.warning("🚫 Tool call '\(call.name)' blocked - system in waiting state: \(waitingState.rawValue)", category: .ai)
                await emitToolError(
                    callId: call.callId,
                    message: "Cannot execute tools while waiting for user input (state: \(waitingState.rawValue)). Please respond to the pending request first."
                )
                return
            }
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
            // DocumentArtifactMessenger will batch and send the extracted content to the LLM
            // No separate developer message needed - tool response + content message suffice
            if toolName == "extract_document", output["artifact_record"] != .null {
                await emit(.artifactRecordProduced(record: output["artifact_record"]))
            }
            // Determine reasoning effort for specific tools
            // GPT-5.1 supports: none, low, medium, high (not "minimal")
            // Hard tasks use elevated reasoning; all others use default from settings
            let hardTaskTools: Set<String> = [
                "submit_knowledge_card",
                "validate_applicant_profile",
                "display_knowledge_card_plan"
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

            // Tool completed - send response to LLM
            await emitToolResponse(callId: callId, output: output, reasoningEffort: reasoningEffort, nextRequiredTool: nextRequiredTool)

            // Special handling for bootstrap tools - remove from allowed tools after use
            if output["disable_after_use"].bool == true {
                if let name = toolName {
                    await stateCoordinator.excludeTool(name)
                    Logger.info("🚀 Bootstrap tool '\(name)' excluded from future tool calls", category: .ai)
                }
            }
        case .error(let error):
            // Tool execution error
            var errorOutput = JSON()
            errorOutput["error"].string = error.localizedDescription
            errorOutput["status"].string = "incomplete"
            await emitToolResponse(callId: callId, output: errorOutput)

        case .pendingUserAction:
            // Codex paradigm: UI tool presented, awaiting user action.
            // Don't send tool response yet - it will be sent when user acts.
            // Developer messages will be queued behind this pending tool.
            let pendingToolName = toolName ?? "unknown"

            // Check if there's already a pending UI tool call
            // If so, auto-complete this duplicate to prevent conversation sync errors
            // (The LLM sometimes issues parallel identical UI tool calls in a batch)
            if let existingPending = await stateCoordinator.getPendingUIToolCall() {
                Logger.warning("⚠️ Duplicate UI tool call detected: \(pendingToolName) (callId: \(callId.prefix(8))) while \(existingPending.toolName) (callId: \(existingPending.callId.prefix(8))) is already pending", category: .ai)

                // Auto-complete the duplicate with a success message
                var autoCompleteOutput = JSON()
                autoCompleteOutput["status"].string = "completed"
                autoCompleteOutput["message"].string = "Request already in progress - user is responding to the active prompt"
                await emitToolResponse(callId: callId, output: autoCompleteOutput)
                Logger.info("✅ Auto-completed duplicate UI tool call: \(pendingToolName) (callId: \(callId.prefix(8)))", category: .ai)
                return
            }

            await stateCoordinator.setPendingUIToolCall(callId: callId, toolName: pendingToolName)
            Logger.info("🎯 UI tool pending user action: \(pendingToolName) (callId: \(callId.prefix(8)))", category: .ai)
        }
    }
    // MARK: - Event Emission
    /// Emit tool response to LLM
    /// - Parameters:
    ///   - callId: The tool call ID
    ///   - output: The tool output JSON
    ///   - reasoningEffort: Optional reasoning effort level
    ///   - nextRequiredTool: Optional tool name to force as toolChoice (for chaining)
    private func emitToolResponse(callId: String, output: JSON, reasoningEffort: String? = nil, nextRequiredTool: String? = nil) async {
        var payload = JSON()
        payload["callId"].string = callId
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
    private func emitToolError(callId: String, message: String) async {
        var errorOutput = JSON()
        errorOutput["error"].string = message
        errorOutput["status"].string = "incomplete"
        await emitToolResponse(callId: callId, output: errorOutput)
    }
}
