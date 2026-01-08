//
//  PendingRecords.swift
//  Sprung
//
//  Tool coordination records for pending operations.
//

import Foundation
import SwiftData

// MARK: - Pending Tool Response Record

/// Pending tool response awaiting batch release.
/// Collected here until all tool calls in a batch are complete.
@Model
class PendingToolResponseRecord {
    var callId: String
    var toolName: String
    /// JSON string of the tool output
    var outputJSON: String
    var timestamp: Date

    var session: OnboardingSession?

    init(
        callId: String,
        toolName: String,
        outputJSON: String,
        timestamp: Date = Date()
    ) {
        self.callId = callId
        self.toolName = toolName
        self.outputJSON = outputJSON
        self.timestamp = timestamp
    }
}

// MARK: - Pending User Message Record

/// Pending user message queued while tool calls are unresolved.
/// System-generated messages wait here; chatbox messages bypass.
@Model
class PendingUserMessageRecord {
    var text: String
    var isSystemGenerated: Bool
    var timestamp: Date

    var session: OnboardingSession?

    init(
        text: String,
        isSystemGenerated: Bool,
        timestamp: Date = Date()
    ) {
        self.text = text
        self.isSystemGenerated = isSystemGenerated
        self.timestamp = timestamp
    }
}
