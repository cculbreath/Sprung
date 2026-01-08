//
//  OnboardingSession.swift
//  Sprung
//
//  Primary session model for onboarding interview state persistence.
//

import Foundation
import SwiftData

/// Root model for an onboarding session. One per onboarding attempt.
/// Stores overall session state and conversation history.
@Model
class OnboardingSession {
    var id: UUID
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
    /// Merged card inventory JSON (expensive Gemini call result)
    var mergedInventoryJSON: String?
    /// Whether document collection UI was active (for session restore)
    var isDocumentCollectionActive: Bool?
    /// Whether timeline editor was active (for session restore)
    var isTimelineEditorActive: Bool?
    /// Todo list JSON (for restoring LLM task tracking state)
    var todoListJSON: String?

    // MARK: - Relationships
    @Relationship(deleteRule: .cascade, inverse: \OnboardingObjectiveRecord.session)
    var objectives: [OnboardingObjectiveRecord] = []

    // Note: .nullify keeps artifacts when session is deleted (they become archived)
    @Relationship(deleteRule: .nullify, inverse: \ArtifactRecord.session)
    var artifacts: [ArtifactRecord] = []

    @Relationship(deleteRule: .cascade, inverse: \OnboardingMessageRecord.session)
    var messages: [OnboardingMessageRecord] = []

    @Relationship(deleteRule: .cascade, inverse: \OnboardingPlanItemRecord.session)
    var planItems: [OnboardingPlanItemRecord] = []

    // MARK: - Tool Coordination (Single Source of Truth)

    @Relationship(deleteRule: .cascade, inverse: \PendingToolResponseRecord.session)
    var pendingToolResponses: [PendingToolResponseRecord] = []

    @Relationship(deleteRule: .cascade, inverse: \PendingUserMessageRecord.session)
    var pendingUserMessages: [PendingUserMessageRecord] = []

    // MARK: - Conversation Log (New Architecture)

    @Relationship(deleteRule: .cascade, inverse: \ConversationEntryRecord.session)
    var conversationEntries: [ConversationEntryRecord] = []

    /// Expected number of tool responses in current batch (transient, reset on load)
    var expectedToolResponseCount: Int = 0

    /// Comma-separated tool call IDs in current batch
    var currentBatchCallIdsCSV: String?

    /// Comma-separated tool call IDs for UI tools awaiting user action
    var pendingUIToolCallIdsCSV: String?

    /// Currently pending UI tool call ID (single tool awaiting user action)
    var pendingUIToolCallId: String?

    /// Currently pending UI tool name
    var pendingUIToolName: String?

    init(
        id: UUID = UUID(),
        phase: String = "phase1_core_facts",
        startedAt: Date = Date(),
        lastActiveAt: Date = Date(),
        isComplete: Bool = false,
        skeletonTimelineJSON: String? = nil,
        applicantProfileJSON: String? = nil,
        enabledSectionsCSV: String? = nil,
        mergedInventoryJSON: String? = nil,
        isDocumentCollectionActive: Bool? = nil,
        isTimelineEditorActive: Bool? = nil,
        todoListJSON: String? = nil
    ) {
        self.id = id
        self.phase = phase
        self.startedAt = startedAt
        self.lastActiveAt = lastActiveAt
        self.isComplete = isComplete
        self.skeletonTimelineJSON = skeletonTimelineJSON
        self.applicantProfileJSON = applicantProfileJSON
        self.enabledSectionsCSV = enabledSectionsCSV
        self.mergedInventoryJSON = mergedInventoryJSON
        self.isDocumentCollectionActive = isDocumentCollectionActive
        self.isTimelineEditorActive = isTimelineEditorActive
        self.todoListJSON = todoListJSON
    }

    // MARK: - Tool Coordination Computed Properties

    /// Current batch call IDs as a Set
    var currentBatchCallIds: Set<String> {
        get {
            guard let csv = currentBatchCallIdsCSV, !csv.isEmpty else { return [] }
            return Set(csv.split(separator: ",").map { String($0) })
        }
        set {
            currentBatchCallIdsCSV = newValue.isEmpty ? nil : newValue.sorted().joined(separator: ",")
        }
    }

    /// Pending UI tool call IDs as a Set
    var pendingUIToolCallIds: Set<String> {
        get {
            guard let csv = pendingUIToolCallIdsCSV, !csv.isEmpty else { return [] }
            return Set(csv.split(separator: ",").map { String($0) })
        }
        set {
            pendingUIToolCallIdsCSV = newValue.isEmpty ? nil : newValue.sorted().joined(separator: ",")
        }
    }

    /// Check if there's a pending UI tool in the current batch
    var hasPendingUIToolInBatch: Bool {
        !currentBatchCallIds.intersection(pendingUIToolCallIds).isEmpty
    }

    /// Reset transient tool coordination state (called on session load)
    func resetTransientToolState() {
        expectedToolResponseCount = 0
        currentBatchCallIdsCSV = nil
        // Note: pendingUIToolCallIds and pendingToolResponses may need to persist
        // depending on whether we want to resume mid-tool-batch
    }
}
