//
//  OnboardingSessionModels.swift
//  Sprung
//
//  SwiftData models for persisting onboarding session state across app restarts.
//  Enables resume functionality without re-ingesting artifacts.
//
import Foundation
import SwiftData

// MARK: - Session Checkpoint

/// Root model for an onboarding session. One per onboarding attempt.
/// Stores the OpenAI thread reference and overall session state.
@Model
class OnboardingSession {
    var id: UUID
    /// OpenAI Responses API thread reference (valid for ~30 days)
    var previousResponseId: String?
    /// Current interview phase (InterviewPhase.rawValue)
    var phase: String
    /// When the session was started
    var startedAt: Date
    /// Last activity timestamp
    var lastActiveAt: Date
    /// Whether the interview has been completed
    var isComplete: Bool
    /// Skeleton timeline JSON (for restoring timeline state)
    var skeletonTimelineJSON: String?
    /// Applicant profile JSON (for restoring profile state)
    var applicantProfileJSON: String?
    /// Enabled sections as comma-separated string
    var enabledSectionsCSV: String?

    // MARK: - Relationships
    @Relationship(deleteRule: .cascade, inverse: \OnboardingObjectiveRecord.session)
    var objectives: [OnboardingObjectiveRecord] = []

    @Relationship(deleteRule: .cascade, inverse: \OnboardingArtifactRecord.session)
    var artifacts: [OnboardingArtifactRecord] = []

    @Relationship(deleteRule: .cascade, inverse: \OnboardingMessageRecord.session)
    var messages: [OnboardingMessageRecord] = []

    @Relationship(deleteRule: .cascade, inverse: \OnboardingPlanItemRecord.session)
    var planItems: [OnboardingPlanItemRecord] = []

    init(
        id: UUID = UUID(),
        previousResponseId: String? = nil,
        phase: String = "phase1_core_facts",
        startedAt: Date = Date(),
        lastActiveAt: Date = Date(),
        isComplete: Bool = false,
        skeletonTimelineJSON: String? = nil,
        applicantProfileJSON: String? = nil,
        enabledSectionsCSV: String? = nil
    ) {
        self.id = id
        self.previousResponseId = previousResponseId
        self.phase = phase
        self.startedAt = startedAt
        self.lastActiveAt = lastActiveAt
        self.isComplete = isComplete
        self.skeletonTimelineJSON = skeletonTimelineJSON
        self.applicantProfileJSON = applicantProfileJSON
        self.enabledSectionsCSV = enabledSectionsCSV
    }
}

// MARK: - Objective Records

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

// MARK: - Artifact Records

/// Persisted artifact with extracted content.
/// Stores the LLM-enriched text so we don't need to re-process on resume.
@Model
class OnboardingArtifactRecord {
    var id: UUID
    /// Source type: "pdf", "git", "vcard", "image", "docx", etc.
    var sourceType: String
    /// Original filename for display
    var sourceFilename: String
    /// Hash of source content for detecting re-uploads
    var sourceHash: String?
    /// LLM-enriched/extracted text content
    var extractedContent: String
    /// Additional metadata as JSON (git analysis, page count, etc.)
    var metadataJSON: String?
    /// Path to raw source file on disk (for files that need to stay on disk)
    var rawFileRelativePath: String?
    /// When the artifact was ingested
    var ingestedAt: Date
    /// Linked plan item ID (if associated with a knowledge card plan item)
    var planItemId: String?

    var session: OnboardingSession?

    init(
        id: UUID = UUID(),
        sourceType: String,
        sourceFilename: String,
        sourceHash: String? = nil,
        extractedContent: String,
        metadataJSON: String? = nil,
        rawFileRelativePath: String? = nil,
        ingestedAt: Date = Date(),
        planItemId: String? = nil
    ) {
        self.id = id
        self.sourceType = sourceType
        self.sourceFilename = sourceFilename
        self.sourceHash = sourceHash
        self.extractedContent = extractedContent
        self.metadataJSON = metadataJSON
        self.rawFileRelativePath = rawFileRelativePath
        self.ingestedAt = ingestedAt
        self.planItemId = planItemId
    }
}

// MARK: - Message Records

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

// MARK: - Plan Item Records

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
