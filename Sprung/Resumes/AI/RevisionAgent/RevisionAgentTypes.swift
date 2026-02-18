import Foundation
import SwiftOpenAI

// MARK: - Agent Status

enum RevisionAgentStatus: Equatable {
    case idle
    case running
    case completed
    case failed(String)
    case cancelled
}

// MARK: - Agent Error

enum RevisionAgentError: LocalizedError {
    case noLLMFacade
    case modelNotConfigured
    case maxTurnsExceeded
    case agentDidNotComplete
    case invalidToolCall(String)
    case toolExecutionFailed(String)
    case timeout
    case workspaceError(String)
    case pdfRenderFailed(String)

    var errorDescription: String? {
        switch self {
        case .noLLMFacade:
            return "LLM service is not available"
        case .modelNotConfigured:
            return "Resume revision model is not configured in Settings"
        case .maxTurnsExceeded:
            return "Agent exceeded maximum number of turns without completing"
        case .agentDidNotComplete:
            return "Agent stopped without calling complete_revision"
        case .invalidToolCall(let msg):
            return "Invalid tool call: \(msg)"
        case .toolExecutionFailed(let msg):
            return "Tool execution failed: \(msg)"
        case .timeout:
            return "Agent timed out"
        case .workspaceError(let msg):
            return "Workspace error: \(msg)"
        case .pdfRenderFailed(let msg):
            return "PDF render failed: \(msg)"
        }
    }
}

// MARK: - Revision Message (for UI)

struct RevisionMessage: Identifiable {
    let id = UUID()
    let role: RevisionMessageRole
    let content: String
    let timestamp = Date()
}

enum RevisionMessageRole {
    case assistant
    case user
    case toolActivity(String) // tool name
}

// MARK: - Stream Result

/// Accumulated output from a single stream processing turn.
struct RevisionAgentStreamResult {
    var textBlocks: [AnthropicContentBlock] = []
    var toolCallBlocks: [AnthropicContentBlock] = []
    var toolCalls: [RevisionStreamProcessor.ToolCallInfo] = []
}
