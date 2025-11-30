import Foundation
/// Manages LLM-specific state: allowed tools, response tracking, and model configuration.
/// Extracted from StateCoordinator to consolidate LLM state management.
actor LLMStateManager {
    // MARK: - State
    /// Currently allowed tool names for LLM calls
    private var allowedToolNames: Set<String> = []
    /// Last response ID from LLM (for conversation continuity)
    private var lastResponseId: String?
    /// Current model ID being used
    private var currentModelId: String = "gpt-5.1"
    /// Current tool pane card being displayed
    private var currentToolPaneCard: OnboardingToolPaneCard = .none
    // MARK: - Tool Names
    /// Get the current set of allowed tool names
    func getAllowedToolNames() -> Set<String> {
        allowedToolNames
    }
    /// Update the allowed tool names
    func setAllowedToolNames(_ tools: Set<String>) {
        allowedToolNames = tools
        Logger.info("🔧 Allowed tools updated in LLMStateManager: \(tools.count) tools", category: .ai)
    }
    // MARK: - Response Tracking
    /// Get the last response ID
    func getLastResponseId() -> String? {
        lastResponseId
    }
    /// Update conversation state with new response ID
    func updateConversationState(responseId: String) {
        lastResponseId = responseId
        Logger.debug("💬 Conversation state updated: \(responseId.prefix(8))", category: .ai)
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
    // MARK: - Tool Pane Card
    /// Get the current tool pane card
    func getCurrentToolPaneCard() -> OnboardingToolPaneCard {
        currentToolPaneCard
    }
    /// Set the current tool pane card
    func setToolPaneCard(_ card: OnboardingToolPaneCard) {
        currentToolPaneCard = card
    }
    // MARK: - Snapshot Support
    struct Snapshot: Codable {
        let lastResponseId: String?
        let currentModelId: String
        let currentToolPaneCard: OnboardingToolPaneCard
    }
    /// Create a snapshot of LLM state for persistence
    func createSnapshot() -> Snapshot {
        Snapshot(
            lastResponseId: lastResponseId,
            currentModelId: currentModelId,
            currentToolPaneCard: currentToolPaneCard
        )
    }
    /// Restore LLM state from a snapshot
    /// Note: We intentionally do NOT restore lastResponseId because the OpenAI Responses API
    /// requires linear conversation continuity. If the checkpoint was saved mid-tool-loop,
    /// restoring the response ID would cause "No tool output found" errors.
    /// Instead, we start a fresh API conversation and include conversation history in the context.
    func restoreFromSnapshot(_ snapshot: Snapshot) {
        // Intentionally clear lastResponseId to force fresh API conversation
        lastResponseId = nil
        currentModelId = snapshot.currentModelId
        currentToolPaneCard = snapshot.currentToolPaneCard
        Logger.info("📝 Checkpoint restore: cleared lastResponseId (starting fresh API conversation)", category: .ai)
        if currentToolPaneCard != .none {
            Logger.info("🎴 Restored ToolPane card: \(currentToolPaneCard.rawValue)", category: .ai)
        }
    }
    // MARK: - Reset
    /// Reset all LLM state to initial values
    func reset() {
        allowedToolNames = []
        lastResponseId = nil
        currentModelId = "gpt-5.1"
        currentToolPaneCard = .none
    }
}
