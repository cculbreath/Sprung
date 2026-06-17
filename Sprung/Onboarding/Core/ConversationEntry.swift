//
//  ConversationEntry.swift
//  Sprung
//
//  Pure value types for the conversation log: the entry enum and its
//  tool-call slot/status/info supporting types. Extracted from
//  ConversationLog.swift so the actor file holds only the actor.
//

import Foundation

// MARK: - Data Types

/// Tool call slot in conversation entry (tracks call ID, arguments, and result)
/// Named to avoid ambiguity with ToolProtocol.ToolCall used in events
struct ToolCallSlot: Sendable, Codable {
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

/// Conversation entry (user, assistant, or system note)
enum ConversationEntry: Identifiable, Sendable {
    case user(id: UUID, text: String, isSystemGenerated: Bool, timestamp: Date)
    case assistant(id: UUID, text: String, toolCalls: [ToolCallSlot]?, timestamp: Date)
    /// Inline system note displayed between bubbles (italic, no bubble, emoji prefix)
    /// Used to show coordinator messages, agent completions, etc. so user understands
    /// why the assistant is responding without explicit user input.
    case systemNote(id: UUID, text: String, timestamp: Date)

    var id: UUID {
        switch self {
        case .user(let id, _, _, _): return id
        case .assistant(let id, _, _, _): return id
        case .systemNote(let id, _, _): return id
        }
    }

    var timestamp: Date {
        switch self {
        case .user(_, _, _, let ts): return ts
        case .assistant(_, _, _, let ts): return ts
        case .systemNote(_, _, let ts): return ts
        }
    }

    var text: String {
        switch self {
        case .user(_, let text, _, _): return text
        case .assistant(_, let text, _, _): return text
        case .systemNote(_, let text, _): return text
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

    var isSystemNote: Bool {
        if case .systemNote = self { return true }
        return false
    }
}

// MARK: - ToolCallInfo (for stream adapter)

/// Minimal tool call info from stream parsing
struct ToolCallInfo: Sendable {
    let id: String
    let name: String
    let arguments: String
}
