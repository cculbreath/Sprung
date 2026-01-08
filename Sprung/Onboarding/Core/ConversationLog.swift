//
//  ConversationLog.swift
//  Sprung
//
//  Single source of truth for conversation state. Append-only sequence
//  with gated user message appending. Tool call slots are filled as
//  results arrive; user messages are blocked until all slots are filled.
//
//  Key invariants:
//  - At most ONE entry (the last) can have nil tool result slots
//  - User messages cannot append until all slots are filled
//  - On interrupt, pending slots are filled with synthetic results
//

import Foundation

// MARK: - Data Types

/// Tool call with result slot
struct ToolCall: Sendable, Codable {
    let callId: String
    let name: String
    let arguments: String
    var result: String?
    var status: ToolCallStatus

    var isResolved: Bool { result != nil }

    init(callId: String, name: String, arguments: String, result: String? = nil, status: ToolCallStatus = .pending) {
        self.callId = callId
        self.name = name
        self.arguments = arguments
        self.result = result
        self.status = status
    }
}

/// Tool call resolution status
enum ToolCallStatus: String, Sendable, Codable {
    case pending     // Awaiting result
    case completed   // Tool finished successfully
    case cancelled   // User interrupted
    case failed      // Tool threw error
}

/// Conversation entry (user or assistant message)
enum ConversationEntry: Identifiable, Sendable {
    case user(id: UUID, text: String, isSystemGenerated: Bool, timestamp: Date)
    case assistant(id: UUID, text: String, toolCalls: [ToolCall]?, timestamp: Date)

    var id: UUID {
        switch self {
        case .user(let id, _, _, _): return id
        case .assistant(let id, _, _, _): return id
        }
    }

    var timestamp: Date {
        switch self {
        case .user(_, _, _, let ts): return ts
        case .assistant(_, _, _, let ts): return ts
        }
    }

    var text: String {
        switch self {
        case .user(_, let text, _, _): return text
        case .assistant(_, let text, _, _): return text
        }
    }

    var isUser: Bool {
        if case .user = self { return true }
        return false
    }

    var isAssistant: Bool {
        if case .assistant = self { return true }
        return false
    }
}

// MARK: - ConversationLog Actor

/// Single source of truth for conversation state
actor ConversationLog {

    // MARK: - State

    private(set) var entries: [ConversationEntry] = []
    private let operations: OperationTracker
    private let eventBus: EventCoordinator

    // MARK: - Initialization

    init(operations: OperationTracker, eventBus: EventCoordinator) {
        self.operations = operations
        self.eventBus = eventBus
        Logger.info("ConversationLog initialized", category: .ai)
    }

    // MARK: - Queries

    /// Check if the last assistant entry has unresolved tool calls
    var hasPendingToolCalls: Bool {
        guard case .assistant(_, _, let toolCalls?, _) = entries.last else {
            return false
        }
        return toolCalls.contains { !$0.isResolved }
    }

    /// Get IDs of unresolved tool calls in last entry
    var pendingToolCallIds: [String] {
        guard case .assistant(_, _, let toolCalls?, _) = entries.last else {
            return []
        }
        return toolCalls.filter { !$0.isResolved }.map { $0.callId }
    }

    /// Get count of entries
    var count: Int { entries.count }

    /// Get all entries (for serialization)
    func getAllEntries() -> [ConversationEntry] {
        entries
    }

    // MARK: - User Message (Gated)

    /// Append user message - fills pending tool slots first if needed
    /// This is the gating mechanism that ensures the log is always valid
    func appendUser(text: String, isSystemGenerated: Bool) async {
        // If there are pending tool calls, resolve them first
        if hasPendingToolCalls {
            let pendingIds = pendingToolCallIds
            Logger.info("ConversationLog: Gating user message, filling \(pendingIds.count) pending slots", category: .ai)

            // Cancel any running operations
            for callId in pendingIds {
                await operations.cancel(callId: callId, reason: "User interrupted")
            }

            // Fill slots with results (real from completed ops, synthetic from cancelled)
            for callId in pendingIds {
                if let result = await operations.getResult(callId: callId) {
                    setToolResult(callId: callId, output: result, status: .cancelled)
                } else {
                    // No operation found, use generic cancelled result
                    setToolResult(callId: callId, output: #"{"status":"cancelled","reason":"User interrupted"}"#, status: .cancelled)
                }
            }
        }

        // Now safe to append user message
        let entry = ConversationEntry.user(
            id: UUID(),
            text: text,
            isSystemGenerated: isSystemGenerated,
            timestamp: Date()
        )
        entries.append(entry)

        Logger.info("ConversationLog: Appended user message (total: \(entries.count))", category: .ai)

        // Publish event for persistence
        await eventBus.publish(.conversationEntryAppended(entry: entry))
    }

    // MARK: - Assistant Message

    /// Append assistant message with optional tool calls (slots start as nil)
    func appendAssistant(id: UUID, text: String, toolCalls: [ToolCallInfo]?) {
        let calls = toolCalls?.map { info in
            ToolCall(
                callId: info.id,
                name: info.name,
                arguments: info.arguments,
                result: nil,
                status: .pending
            )
        }

        let entry = ConversationEntry.assistant(
            id: id,
            text: text,
            toolCalls: calls,
            timestamp: Date()
        )
        entries.append(entry)

        let toolCount = calls?.count ?? 0
        Logger.info("ConversationLog: Appended assistant message with \(toolCount) tool call(s)", category: .ai)

        // Publish event for persistence
        Task {
            await eventBus.publish(.conversationEntryAppended(entry: entry))
        }
    }

    // MARK: - Tool Result (Slot Fill)

    /// Fill a tool result slot in the last assistant entry
    func setToolResult(callId: String, output: String, status: ToolCallStatus = .completed) {
        guard case .assistant(let id, let text, var toolCalls?, let timestamp) = entries.last,
              let index = toolCalls.firstIndex(where: { $0.callId == callId }) else {
            Logger.warning("ConversationLog: Tool result for unknown call \(callId.prefix(8))", category: .ai)
            return
        }

        // Fill the slot
        toolCalls[index].result = output
        toolCalls[index].status = status

        // Replace last entry with updated version
        entries[entries.count - 1] = .assistant(
            id: id,
            text: text,
            toolCalls: toolCalls,
            timestamp: timestamp
        )

        Logger.debug("ConversationLog: Filled tool slot \(callId.prefix(8)) (\(status))", category: .ai)

        // Publish event for persistence update
        Task {
            await eventBus.publish(.toolResultFilled(callId: callId, status: status.rawValue))
        }
    }

    /// Check if all tool calls in last entry are resolved
    var allToolCallsResolved: Bool {
        guard case .assistant(_, _, let toolCalls?, _) = entries.last else {
            return true  // No tools means resolved
        }
        return toolCalls.allSatisfy { $0.isResolved }
    }

    // MARK: - Persistence Support

    /// Restore entries from persistence
    func restore(entries: [ConversationEntry]) {
        self.entries = entries
        Logger.info("ConversationLog: Restored \(entries.count) entries", category: .ai)

        // Note: If last entry has unfilled tool slots, they'll be filled
        // with synthetic results on next user message (self-healing)
        if hasPendingToolCalls {
            Logger.warning("ConversationLog: Restored with \(pendingToolCallIds.count) pending tool calls (will heal on next user message)", category: .ai)
        }
    }

    /// Reset all state
    func reset() {
        entries.removeAll()
        Logger.info("ConversationLog: Reset", category: .ai)
    }

    // MARK: - UI Compatibility

    /// Convert entries to OnboardingMessage format for UI display
    /// This bridges ConversationLog to the existing UI layer
    func getMessagesForUI() -> [OnboardingMessage] {
        entries.compactMap { entry -> OnboardingMessage? in
            switch entry {
            case .user(let id, let text, let isSystemGenerated, let timestamp):
                return OnboardingMessage(
                    id: id,
                    role: .user,
                    text: text,
                    timestamp: timestamp,
                    isSystemGenerated: isSystemGenerated
                )
            case .assistant(let id, let text, let toolCalls, let timestamp):
                let uiToolCalls = toolCalls?.map { call in
                    OnboardingMessage.ToolCallInfo(
                        id: call.callId,
                        name: call.name,
                        arguments: call.arguments,
                        result: call.result
                    )
                }
                return OnboardingMessage(
                    id: id,
                    role: .assistant,
                    text: text,
                    timestamp: timestamp,
                    toolCalls: uiToolCalls
                )
            }
        }
    }
}

// MARK: - ToolCallInfo (for stream adapter)

/// Minimal tool call info from stream parsing
struct ToolCallInfo: Sendable {
    let id: String
    let name: String
    let arguments: String
}
