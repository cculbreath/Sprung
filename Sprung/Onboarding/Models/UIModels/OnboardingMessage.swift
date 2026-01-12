import Foundation

/// Role of a message in the onboarding chat interface
enum OnboardingMessageRole: String, Codable {
    case user
    case assistant
    case system
    /// Inline system note displayed between bubbles (italic, no bubble, emoji prefix)
    case systemNote
}

/// Represents a message in the onboarding chat interface
struct OnboardingMessage: Identifiable, Codable {
    let id: UUID
    let role: OnboardingMessageRole
    var text: String
    let timestamp: Date
    let isSystemGenerated: Bool  // True for app-generated trigger messages
    var toolCalls: [ToolCallInfo]?  // Tool calls made in this message (for assistant messages)
    var isQueued: Bool  // True when message is queued but not yet sent to LLM

    /// Represents a tool call and its result (paired storage for Anthropic compatibility)
    struct ToolCallInfo: Codable {
        let id: String
        let name: String
        let arguments: String
        /// The tool result output (filled in when the result arrives)
        /// nil means the result hasn't been received yet
        var result: String?

        /// Whether this tool call has received its result
        var isComplete: Bool { result != nil }

        init(id: String, name: String, arguments: String, result: String? = nil) {
            self.id = id
            self.name = name
            self.arguments = arguments
            self.result = result
        }
    }

    init(
        id: UUID = UUID(),
        role: OnboardingMessageRole,
        text: String,
        timestamp: Date = Date(),
        isSystemGenerated: Bool = false,
        toolCalls: [ToolCallInfo]? = nil,
        isQueued: Bool = false
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.timestamp = timestamp
        self.isSystemGenerated = isSystemGenerated
        self.toolCalls = toolCalls
        self.isQueued = isQueued
    }

    // MARK: - Tool Result Pairing

    /// Whether all tool calls in this message have received their results
    var allToolCallsComplete: Bool {
        guard let toolCalls = toolCalls, !toolCalls.isEmpty else { return true }
        return toolCalls.allSatisfy { $0.isComplete }
    }

    /// Get IDs of tool calls that haven't received results yet
    var pendingToolCallIds: [String] {
        guard let toolCalls = toolCalls else { return [] }
        return toolCalls.filter { !$0.isComplete }.map { $0.id }
    }

    /// Update a tool call with its result
    /// - Returns: true if the tool call was found and updated
    mutating func setToolResult(callId: String, result: String) -> Bool {
        guard var toolCalls = toolCalls,
              let index = toolCalls.firstIndex(where: { $0.id == callId }) else {
            return false
        }
        toolCalls[index].result = result
        self.toolCalls = toolCalls
        return true
    }
}
