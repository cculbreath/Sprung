//
//  DrainGate.swift
//  Sprung
//
//  Gate that controls when the UserActionQueue can drain.
//  Blocks draining during UI-blocking operations while allowing
//  background tool execution to proceed without blocking user input.
//

import Foundation

/// Reasons the queue drain is blocked
enum DrainBlockingReason: Hashable, Sendable {
    /// Streaming response in progress (text still arriving)
    case streamingResponse

    /// Tool execution in progress (background or UI)
    /// User can still TYPE messages (they queue), but delivery is held until tools complete
    case toolExecutionInProgress(callIds: Set<String>)

    /// UI tool awaiting user interaction (upload panel, option picker)
    case uiToolAwaitingDismissal(toolName: String)

    /// Waiting for LLM to acknowledge previous user message
    /// (prevents sending multiple messages before LLM responds)
    case awaitingLLMResponse
}

/// Gate that controls when queued user actions can be processed
@Observable
@MainActor
final class DrainGate {

    // MARK: - State

    private(set) var blockingReasons: Set<DrainBlockingReason> = []

    /// Whether the queue can drain (no blocking reasons)
    var canDrain: Bool { blockingReasons.isEmpty }

    /// Callback when gate opens (for triggering drain check)
    var onGateOpened: (() async -> Void)?

    // MARK: - Tools Classification

    /// Tools that block user input (require UI interaction)
    private static let uiBlockingTools: Set<String> = [
        "get_user_upload",
        "get_user_option",
        "present_user_option",
        "submit_for_validation",
        "get_applicant_profile",
        "configure_enabled_sections"
    ]

    /// Check if a tool should block user input
    static func isUIBlockingTool(_ toolName: String) -> Bool {
        uiBlockingTools.contains(toolName)
    }

    // MARK: - Block Management

    /// Add a blocking reason
    func addBlock(_ reason: DrainBlockingReason) {
        let inserted = blockingReasons.insert(reason).inserted
        if inserted {
            Logger.info("🚫 DrainGate: Added block - \(reason.description) (total: \(blockingReasons.count))", category: .ai)
        }
    }

    /// Remove a blocking reason and trigger drain check if gate opens
    func removeBlock(_ reason: DrainBlockingReason) {
        let removed = blockingReasons.remove(reason)
        if removed != nil {
            Logger.info("✅ DrainGate: Removed block - \(reason.description) (remaining: \(blockingReasons.count))", category: .ai)

            if canDrain {
                Logger.info("🚪 DrainGate: Gate opened, triggering drain check", category: .ai)
                Task {
                    await onGateOpened?()
                }
            }
        }
    }

    /// Clear all blocking reasons (e.g., on session reset)
    func clearAllBlocks() {
        let count = blockingReasons.count
        blockingReasons.removeAll()
        pendingToolCallIds.removeAll()
        toolNamesByCallId.removeAll()
        if count > 0 {
            Logger.info("🧹 DrainGate: Cleared \(count) block(s)", category: .ai)
        }
    }

    // MARK: - Tool Execution Tracking

    /// Currently pending tool call IDs
    private var pendingToolCallIds: Set<String> = []

    /// Maps call IDs to tool names for UI display
    private var toolNamesByCallId: [String: String] = [:]

    /// Background tools currently executing (for status bar display)
    /// Returns only non-UI-blocking tools
    var executingBackgroundTools: [(callId: String, toolName: String)] {
        pendingToolCallIds.compactMap { callId in
            guard let name = toolNamesByCallId[callId],
                  !Self.isUIBlockingTool(name) else { return nil }
            return (callId: callId, toolName: name)
        }
    }

    // MARK: - Convenience Methods

    /// Block for streaming response
    func blockForStreaming() {
        addBlock(.streamingResponse)
    }

    /// Unblock streaming response
    func unblockStreaming() {
        removeBlock(.streamingResponse)
    }

    /// Register a tool call with its name (called when tool.callRequested event is received)
    func registerToolCall(callId: String, toolName: String) {
        toolNamesByCallId[callId] = toolName
        Logger.debug("🔧 DrainGate: Registered tool '\(toolName)' (callId: \(callId.prefix(8)))", category: .ai)
    }

    /// Block for tool execution batch (called when tool calls are received)
    func blockForToolExecution(callIds: [String]) {
        pendingToolCallIds.formUnion(callIds)
        // Remove any existing tool execution block and add updated one
        blockingReasons = blockingReasons.filter {
            if case .toolExecutionInProgress = $0 { return false }
            return true
        }
        addBlock(.toolExecutionInProgress(callIds: pendingToolCallIds))
        Logger.info("🔧 DrainGate: Tool execution started for \(callIds.count) tool(s)", category: .ai)
    }

    /// Mark a tool call as completed
    func toolCallCompleted(callId: String) {
        pendingToolCallIds.remove(callId)
        toolNamesByCallId.removeValue(forKey: callId)
        // Remove old block
        blockingReasons = blockingReasons.filter {
            if case .toolExecutionInProgress = $0 { return false }
            return true
        }
        // Add updated block if still have pending tools
        if !pendingToolCallIds.isEmpty {
            addBlock(.toolExecutionInProgress(callIds: pendingToolCallIds))
        } else {
            Logger.info("✅ DrainGate: All tools completed (remaining blocks: \(blockingReasons.count))", category: .ai)
            // Only trigger drain check if gate is actually open (no other blocks)
            if canDrain {
                Logger.info("🚪 DrainGate: Gate opened, triggering drain check", category: .ai)
                Task {
                    await onGateOpened?()
                }
            }
        }
    }

    /// Block for UI tool (only if tool requires user interaction)
    func blockForUITool(_ toolName: String) {
        guard Self.isUIBlockingTool(toolName) else {
            Logger.debug("🔧 DrainGate: Tool '\(toolName)' is background, not UI-blocking", category: .ai)
            return
        }
        addBlock(.uiToolAwaitingDismissal(toolName: toolName))
    }

    /// Unblock UI tool
    func unblockUITool(_ toolName: String) {
        removeBlock(.uiToolAwaitingDismissal(toolName: toolName))
    }

    /// Block while awaiting LLM response
    func blockForLLMResponse() {
        addBlock(.awaitingLLMResponse)
    }

    /// Unblock after LLM responds
    func unblockLLMResponse() {
        removeBlock(.awaitingLLMResponse)
    }

    // MARK: - UI Display

    /// Human-readable description of why queue is blocked
    var blockingDescription: String? {
        guard !canDrain else { return nil }

        let descriptions = blockingReasons.map { $0.userFacingDescription }
        return descriptions.joined(separator: ", ")
    }
}

// MARK: - DrainBlockingReason Description

extension DrainBlockingReason {
    var description: String {
        switch self {
        case .streamingResponse:
            return "streamingResponse"
        case .toolExecutionInProgress(let callIds):
            return "toolExecutionInProgress(\(callIds.count) tools)"
        case .uiToolAwaitingDismissal(let toolName):
            return "uiToolAwaitingDismissal(\(toolName))"
        case .awaitingLLMResponse:
            return "awaitingLLMResponse"
        }
    }

    var userFacingDescription: String {
        switch self {
        case .streamingResponse:
            return "Waiting for response..."
        case .toolExecutionInProgress(let callIds):
            return "Processing \(callIds.count) task(s)..."
        case .uiToolAwaitingDismissal(let toolName):
            switch toolName {
            case "get_user_upload":
                return "Complete file upload first"
            case "get_user_option", "present_user_option":
                return "Make a selection first"
            default:
                return "Complete current action"
            }
        case .awaitingLLMResponse:
            return "Waiting for response..."
        }
    }
}
