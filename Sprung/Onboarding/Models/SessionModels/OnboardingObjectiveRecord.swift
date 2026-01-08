//
//  OnboardingObjectiveRecord.swift
//  Sprung
//
//  Persisted objective status for session restore.
//

import Foundation
import SwiftData

/// Persisted objective status for session restore.
@Model
class OnboardingObjectiveRecord {
    var objectiveId: String
    /// Status: "pending", "in_progress", "completed", "skipped"
    var status: String
    /// When the status was last updated
    var updatedAt: Date

    var session: OnboardingSession?

    init(
        objectiveId: String,
        status: String = "pending",
        updatedAt: Date = Date()
    ) {
        self.objectiveId = objectiveId
        self.status = status
        self.updatedAt = updatedAt
    }
}
