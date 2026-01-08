//
//  ConversationEntryRecord.swift
//  Sprung
//
//  Persisted conversation entry for the ConversationLog architecture.
//  Unified message record supporting the slot-fill model.
//

import Foundation
import SwiftData

/// Persisted conversation entry for the new ConversationLog architecture.
/// Replaces OnboardingMessageRecord with clean slot-fill model.
@Model
class ConversationEntryRecord {
    var id: UUID
    /// Entry type: "user" or "assistant"
    var entryType: String
    /// Message text content
    var text: String
    /// For user entries: whether this was system-generated
    var isSystemGenerated: Bool?
    /// For assistant entries: serialized [ToolCallSlot] array as JSON
    var toolCallsJSON: String?
    /// When the entry was created
    var timestamp: Date
    /// Explicit ordering in the conversation sequence
    var sequenceIndex: Int

    var session: OnboardingSession?

    init(
        id: UUID = UUID(),
        entryType: String,
        text: String,
        isSystemGenerated: Bool? = nil,
        toolCallsJSON: String? = nil,
        timestamp: Date = Date(),
        sequenceIndex: Int = 0
    ) {
        self.id = id
        self.entryType = entryType
        self.text = text
        self.isSystemGenerated = isSystemGenerated
        self.toolCallsJSON = toolCallsJSON
        self.timestamp = timestamp
        self.sequenceIndex = sequenceIndex
    }

    /// Convert to ConversationEntry for ConversationLog restore
    func toConversationEntry() -> ConversationEntry? {
        switch entryType {
        case "user":
            return .user(
                id: id,
                text: text,
                isSystemGenerated: isSystemGenerated ?? false,
                timestamp: timestamp
            )
        case "assistant":
            var toolCalls: [ToolCallSlot]?
            if let json = toolCallsJSON,
               let data = json.data(using: .utf8) {
                toolCalls = try? JSONDecoder().decode([ToolCallSlot].self, from: data)
            }
            return .assistant(
                id: id,
                text: text,
                toolCalls: toolCalls,
                timestamp: timestamp
            )
        default:
            return nil
        }
    }

    /// Create from ConversationEntry
    static func from(_ entry: ConversationEntry, sequenceIndex: Int) -> ConversationEntryRecord {
        switch entry {
        case .user(let id, let text, let isSystemGenerated, let timestamp):
            return ConversationEntryRecord(
                id: id,
                entryType: "user",
                text: text,
                isSystemGenerated: isSystemGenerated,
                timestamp: timestamp,
                sequenceIndex: sequenceIndex
            )
        case .assistant(let id, let text, let toolCalls, let timestamp):
            var toolCallsJSON: String?
            if let calls = toolCalls,
               let data = try? JSONEncoder().encode(calls) {
                toolCallsJSON = String(data: data, encoding: .utf8)
            }
            return ConversationEntryRecord(
                id: id,
                entryType: "assistant",
                text: text,
                toolCallsJSON: toolCallsJSON,
                timestamp: timestamp,
                sequenceIndex: sequenceIndex
            )
        }
    }
}
