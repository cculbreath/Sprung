//
//  OnboardingMessageRecord.swift
//  Sprung
//
//  Legacy persisted chat message for session restore.
//  Retained for migration of existing sessions.
//

import Foundation
import SwiftData

/// Persisted chat message for session restore.
/// Stores enough context to rebuild conversation on resume.
@Model
class OnboardingMessageRecord {
    var id: UUID
    /// Role: "user", "assistant", "system"
    var role: String
    /// Message text content
    var text: String
    /// When the message was sent
    var timestamp: Date
    /// Whether this was an app-generated trigger message
    var isSystemGenerated: Bool
    /// Tool calls JSON (for assistant messages with tool calls)
    var toolCallsJSON: String?

    var session: OnboardingSession?

    init(
        id: UUID = UUID(),
        role: String,
        text: String,
        timestamp: Date = Date(),
        isSystemGenerated: Bool = false,
        toolCallsJSON: String? = nil
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.timestamp = timestamp
        self.isSystemGenerated = isSystemGenerated
        self.toolCallsJSON = toolCallsJSON
    }
}
