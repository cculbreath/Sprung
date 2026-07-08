import Foundation
import SwiftyJSON

/// Manages LLM-specific state: allowed tools, model configuration, and UI tool coordination.
actor LLMSessionState {
    // MARK: - State

    /// Current model ID being used (set via setModelId when interview starts)
    private var currentModelId: String = ""

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

    // MARK: - Coordinator Message Queuing (Codex Paradigm)
    // Coordinator (developer) messages are queued and bundled with the next user message.
    // NOTE: Pending UI tool state is now tracked by OperationTracker, not here.

    /// Queued coordinator messages waiting for next user message
    private var queuedCoordinatorMessages: [JSON] = []

    // MARK: - Tool Names

    /// Update the allowed tool names
    func setAllowedToolNames(_ tools: Set<String>) {
        Logger.info("🔧 Allowed tools updated: \(tools.count) tools", category: .ai)
    }

    // MARK: - Model Configuration

    /// Set the model ID
    func setModelId(_ modelId: String) {
        currentModelId = modelId
        Logger.info("🔧 Model ID set to: \(modelId)", category: .ai)
    }

    /// Set whether to use flex processing tier
    func setUseFlexProcessing(_ enabled: Bool) {
        useFlexProcessing = enabled
        Logger.info("🔧 Flex processing \(enabled ? "enabled" : "disabled")", category: .ai)
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

    // MARK: - Coordinator Message Queue Management

    /// Queue a coordinator message to be bundled with next user message
    func queueCoordinatorMessage(_ payload: JSON) {
        queuedCoordinatorMessages.append(payload)
        let title = payload["title"].stringValue
        Logger.debug("📥 Coordinator message queued (pending UI tool): \(title)", category: .ai)
    }

    /// Drain queued coordinator messages (call after UI tool output is sent)
    func drainQueuedCoordinatorMessages() -> [JSON] {
        let messages = queuedCoordinatorMessages
        queuedCoordinatorMessages = []
        if !messages.isEmpty {
            Logger.info("📤 Flushing \(messages.count) queued coordinator message(s)", category: .ai)
        }
        return messages
    }

    /// Remove queued coordinator messages for a specific objective
    func clearQueuedMessagesForObjective(_ objectiveId: String) {
        let before = queuedCoordinatorMessages.count
        queuedCoordinatorMessages.removeAll { payload in
            payload["details"]["objective"].stringValue == objectiveId
        }
        let removed = before - queuedCoordinatorMessages.count
        if removed > 0 {
            Logger.info("🗑️ Cleared \(removed) queued coordinator message(s) for objective: \(objectiveId)", category: .ai)
        }
    }

    // MARK: - Pending Tool Response Tracking (Retry Mechanism)

    /// Store pending tool response payload(s) before sending
    func setPendingToolResponses(_ payloads: [JSON]) {
        pendingToolResponsePayloads = payloads
        pendingToolResponseRetryCount = 0
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
            pendingToolResponsePayloads = []
            pendingToolResponseRetryCount = 0
            return nil
        }
        Logger.info("🔄 Retry attempt \(pendingToolResponseRetryCount)/\(maxPendingToolResponseRetries) for pending tool responses", category: .ai)
        return pendingToolResponsePayloads
    }

    /// Get the current retry count for pending tool responses
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

    // MARK: - Reset

    /// Reset all LLM state to initial values
    func reset() {
        currentModelId = ""
        currentToolPaneCard = .none
        pendingToolResponsePayloads = []
        pendingToolResponseRetryCount = 0
        queuedCoordinatorMessages = []
    }
}
