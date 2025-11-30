import Foundation
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
    /// Set the last clean response ID (for restore)
    func setLastCleanResponseId(_ responseId: String?) {
        lastCleanResponseId = responseId
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
        let lastCleanResponseId: String?  // Only store clean response ID (safe to restore from)
        let currentModelId: String
        let currentToolPaneCard: OnboardingToolPaneCard
    }
    /// Create a snapshot of LLM state for persistence
    func createSnapshot() -> Snapshot {
        Snapshot(
            lastCleanResponseId: lastCleanResponseId,  // Store clean ID, not potentially mid-tool-loop ID
            currentModelId: currentModelId,
            currentToolPaneCard: currentToolPaneCard
        )
    }
    /// Restore LLM state from a snapshot
    /// Uses lastCleanResponseId which points to a response with no pending tool calls,
    /// allowing the conversation to continue from server-side context.
    func restoreFromSnapshot(_ snapshot: Snapshot) {
        // Restore from clean response ID (safe to continue from)
        lastResponseId = snapshot.lastCleanResponseId
        lastCleanResponseId = snapshot.lastCleanResponseId
        currentModelId = snapshot.currentModelId
        currentToolPaneCard = snapshot.currentToolPaneCard
        if let responseId = lastResponseId {
            Logger.info("📝 Checkpoint restore: using clean response ID \(responseId.prefix(8))...", category: .ai)
        } else {
            Logger.info("📝 Checkpoint restore: no clean response ID, will start fresh", category: .ai)
        }
        if currentToolPaneCard != .none {
            Logger.info("🎴 Restored ToolPane card: \(currentToolPaneCard.rawValue)", category: .ai)
        }
    }
    // MARK: - Reset
    /// Reset all LLM state to initial values
    func reset() {
        allowedToolNames = []
        lastResponseId = nil
        lastCleanResponseId = nil
        currentModelId = "gpt-5.1"
        currentToolPaneCard = .none
    }
}
