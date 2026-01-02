import Foundation
import SwiftyJSON
/// Manages LLM-specific state: allowed tools, response tracking, and model configuration.
/// Extracted from StateCoordinator to consolidate LLM state management.
actor LLMStateManager {
    // MARK: - State
    /// Currently allowed tool names for LLM calls
    private var allowedToolNames: Set<String> = []
    /// Last response ID from LLM (for conversation continuity)
    private var lastResponseId: String?
    /// Last "clean" response ID (no pending tool calls) - safe to restore from
    private var lastCleanResponseId: String?
    /// Current model ID being used (reads from settings)
    private var currentModelId: String = OnboardingModelConfig.currentModelId
    /// Whether to use flex processing tier (50% cost savings, variable latency)
    private var useFlexProcessing: Bool = true
    /// Default reasoning effort level for LLM calls (none, minimal, low, medium, high)
    private var defaultReasoningEffort: String = "none"
    /// Current tool pane card being displayed
    private var currentToolPaneCard: OnboardingToolPaneCard = .none
    /// Pending tool response payloads that haven't been acknowledged yet
    /// Used for retry on stream errors
    private var pendingToolResponsePayloads: [JSON] = []
    /// Number of times we've retried pending tool responses (to prevent infinite loops)
    private var pendingToolResponseRetryCount: Int = 0
    /// Maximum retries for pending tool responses before giving up
    private let maxPendingToolResponseRetries: Int = 3

    /// Completed tool results that need to be included in conversation history
    /// Each entry is (callId, toolName, output) representing a successful tool execution
    /// Used by Anthropic backend which requires explicit history (no previous_response_id)
    private var completedToolResults: [(callId: String, toolName: String, output: String)] = []

    // MARK: - Pending UI Tool Call (Codex Paradigm)
    /// UI tools that present cards and await user action before responding.
    /// Based on Codex CLI paradigm: tool outputs must be sent before new LLM turns.
    /// When a UI tool is pending, developer messages are queued behind it.
    private var pendingUIToolCall: (callId: String, toolName: String)?

    /// Queued developer messages waiting for pending UI tool to complete
    private var queuedDeveloperMessages: [JSON] = []

    // MARK: - Pending Forced Tool Choice (Tool Chaining)
    /// One-shot override used to force the next LLM request to call a specific tool.
    /// This exists because developer messages may be queued behind pending UI tools; we still
    /// need the toolChoice to apply to the very next continuation request (often a tool output).
    private var pendingForcedToolChoice: String?

    // MARK: - Tool Names
    /// Update the allowed tool names
    func setAllowedToolNames(_ tools: Set<String>) {
        allowedToolNames = tools
        Logger.info("🔧 Allowed tools updated in LLMStateManager: \(tools.count) tools", category: .ai)
    }
    // MARK: - Response Tracking
    /// Get the last clean response ID (safe to restore from - no pending tool calls)
    func getLastCleanResponseId() -> String? {
        lastCleanResponseId
    }
    /// Update conversation state with new response ID
    /// - Parameters:
    ///   - responseId: The response ID from the completed response
    ///   - hadToolCalls: Whether this response included tool calls (if true, don't update clean ID)
    func updateConversationState(responseId: String, hadToolCalls: Bool = false) {
        lastResponseId = responseId
        if !hadToolCalls {
            lastCleanResponseId = responseId
            Logger.debug("💬 Clean response ID updated: \(responseId.prefix(8))", category: .ai)
        }
        Logger.debug("💬 Conversation state updated: \(responseId.prefix(8)), hadToolCalls: \(hadToolCalls)", category: .ai)
    }
    /// Set the last response ID (for restore)
    func setLastResponseId(_ responseId: String?) {
        lastResponseId = responseId
    }
    // MARK: - Model Configuration
    /// Get the current model ID
    func getCurrentModelId() -> String {
        currentModelId
    }
    /// Set the model ID
    func setModelId(_ modelId: String) {
        currentModelId = modelId
        Logger.info("🔧 Model ID set to: \(modelId)", category: .ai)
    }
    /// Get whether flex processing is enabled
    func getUseFlexProcessing() -> Bool {
        useFlexProcessing
    }
    /// Set whether to use flex processing tier
    func setUseFlexProcessing(_ enabled: Bool) {
        useFlexProcessing = enabled
        Logger.info("🔧 Flex processing \(enabled ? "enabled" : "disabled") (50% cost savings)", category: .ai)
    }
    /// Get the default reasoning effort level
    func getDefaultReasoningEffort() -> String {
        defaultReasoningEffort
    }
    /// Set the default reasoning effort level (none, low, medium, high)
    func setDefaultReasoningEffort(_ effort: String) {
        defaultReasoningEffort = effort
        Logger.info("🔧 Default reasoning effort set to: \(effort)", category: .ai)
    }
    // MARK: - Tool Pane Card
    /// Get the current tool pane card
    func getCurrentToolPaneCard() -> OnboardingToolPaneCard {
        currentToolPaneCard
    }
    /// Set the current tool pane card
    func setToolPaneCard(_ card: OnboardingToolPaneCard) {
        currentToolPaneCard = card
    }

    // MARK: - Pending UI Tool Call Management (Codex Paradigm)

    /// Set a UI tool as pending (awaiting user action)
    /// This gates new LLM turns until the user provides input
    func setPendingUIToolCall(callId: String, toolName: String) {
        pendingUIToolCall = (callId: callId, toolName: toolName)
        Logger.info("🎯 UI tool pending: \(toolName) (callId: \(callId.prefix(8)))", category: .ai)
    }

    /// Get the pending UI tool call info
    func getPendingUIToolCall() -> (callId: String, toolName: String)? {
        pendingUIToolCall
    }

    /// Clear the pending UI tool call (after user action sends tool output)
    func clearPendingUIToolCall() {
        if let pending = pendingUIToolCall {
            Logger.info("✅ UI tool cleared: \(pending.toolName) (callId: \(pending.callId.prefix(8)))", category: .ai)
        }
        pendingUIToolCall = nil
    }

    /// Queue a developer message while a UI tool is pending
    func queueDeveloperMessage(_ payload: JSON) {
        queuedDeveloperMessages.append(payload)
        let title = payload["title"].stringValue
        Logger.debug("📥 Developer message queued (pending UI tool): \(title)", category: .ai)
    }

    /// Drain queued developer messages (call after UI tool output is sent)
    func drainQueuedDeveloperMessages() -> [JSON] {
        let messages = queuedDeveloperMessages
        queuedDeveloperMessages = []
        if !messages.isEmpty {
            Logger.info("📤 Flushing \(messages.count) queued developer message(s)", category: .ai)
        }
        return messages
    }

    // MARK: - Forced Tool Choice Override
    func setPendingForcedToolChoice(_ toolName: String) {
        pendingForcedToolChoice = toolName
        Logger.info("🎯 Pending forced toolChoice set: \(toolName)", category: .ai)
    }

    /// Pop (return + clear) the pending forced tool choice.
    func popPendingForcedToolChoice() -> String? {
        defer { pendingForcedToolChoice = nil }
        return pendingForcedToolChoice
    }

    /// Remove queued developer messages for a specific objective (call when objective completes)
    func clearQueuedMessagesForObjective(_ objectiveId: String) {
        let before = queuedDeveloperMessages.count
        queuedDeveloperMessages.removeAll { payload in
            payload["details"]["objective"].stringValue == objectiveId
        }
        let removed = before - queuedDeveloperMessages.count
        if removed > 0 {
            Logger.info("🗑️ Cleared \(removed) queued developer message(s) for completed objective: \(objectiveId)", category: .ai)
        }
    }

    // MARK: - Pending Tool Response Tracking
    /// Store pending tool response payload(s) before sending
    /// These will be retried if a stream error occurs
    func setPendingToolResponses(_ payloads: [JSON]) {
        pendingToolResponsePayloads = payloads
        pendingToolResponseRetryCount = 0  // Reset retry count for new payloads
        let callIds = payloads.map { $0["callId"].stringValue.prefix(8) }.joined(separator: ", ")
        Logger.debug("📦 Pending tool responses set: \(payloads.count) payload(s) [\(callIds)]", category: .ai)
    }
    /// Get pending tool response payloads for retry, incrementing retry count
    /// Returns nil if max retries exceeded
    func getPendingToolResponsesForRetry() -> [JSON]? {
        guard !pendingToolResponsePayloads.isEmpty else { return nil }
        pendingToolResponseRetryCount += 1
        if pendingToolResponseRetryCount > maxPendingToolResponseRetries {
            Logger.error("❌ Max retries (\(maxPendingToolResponseRetries)) exceeded for pending tool responses", category: .ai)
            // Clear to prevent further retries
            pendingToolResponsePayloads = []
            pendingToolResponseRetryCount = 0
            return nil  // Signal that we should give up and revert
        }
        Logger.info("🔄 Retry attempt \(pendingToolResponseRetryCount)/\(maxPendingToolResponseRetries) for pending tool responses", category: .ai)
        return pendingToolResponsePayloads
    }
    /// Get the current retry count for pending tool responses (for exponential backoff calculation)
    func getPendingToolResponseRetryCount() -> Int {
        pendingToolResponseRetryCount
    }
    /// Clear pending tool responses (call after successful acknowledgment)
    func clearPendingToolResponses() {
        if !pendingToolResponsePayloads.isEmpty {
            Logger.debug("✅ Pending tool responses cleared (acknowledged)", category: .ai)
            pendingToolResponsePayloads = []
            pendingToolResponseRetryCount = 0
        }
    }

    // MARK: - Completed Tool Results (Anthropic History)

    /// Store a completed tool result for inclusion in conversation history
    /// Call this after a tool response is successfully sent to Anthropic
    func addCompletedToolResult(callId: String, toolName: String, output: String) {
        completedToolResults.append((callId: callId, toolName: toolName, output: output))
        Logger.debug("📝 Tool result stored for history: \(toolName) (callId: \(callId.prefix(8)))", category: .ai)
    }

    /// Get all completed tool results for building conversation history
    func getCompletedToolResults() -> [(callId: String, toolName: String, output: String)] {
        return completedToolResults
    }

    /// Clear completed tool results (call on session reset)
    func clearCompletedToolResults() {
        if !completedToolResults.isEmpty {
            Logger.debug("🗑️ Cleared \(completedToolResults.count) completed tool results", category: .ai)
            completedToolResults = []
        }
    }

    // MARK: - Reset
    /// Reset all LLM state to initial values
    func reset() {
        allowedToolNames = []
        lastResponseId = nil
        lastCleanResponseId = nil
        currentModelId = OnboardingModelConfig.currentModelId
        currentToolPaneCard = .none
        pendingToolResponsePayloads = []
        pendingToolResponseRetryCount = 0
        pendingUIToolCall = nil
        queuedDeveloperMessages = []
        completedToolResults = []
    }
}
