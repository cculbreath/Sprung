//
//  OnboardingPlanItemRecord.swift
//  Sprung
//
//  Persisted knowledge card plan item for phase 2 UI restore.
//

import Foundation
import SwiftData

/// Persisted knowledge card plan item for phase 2 UI restore.
@Model
class OnboardingPlanItemRecord {
    var itemId: String
    /// Display title
    var title: String
    /// Type: "job", "skill", "education", "project"
    var type: String
    /// Description text (named to avoid conflict with built-in description)
    var descriptionText: String?
    /// Status: "pending", "in_progress", "completed", "skipped"
    var status: String
    /// Associated timeline entry ID (if linked)
    var timelineEntryId: String?

    var session: OnboardingSession?

    init(
        itemId: String,
        title: String,
        type: String,
        descriptionText: String? = nil,
        status: String = "pending",
        timelineEntryId: String? = nil
    ) {
        self.itemId = itemId
        self.title = title
        self.type = type
        self.descriptionText = descriptionText
        self.status = status
        self.timelineEntryId = timelineEntryId
    }
}
