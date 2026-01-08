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

// MARK: - Tool Coordination Records

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

// MARK: - Conversation Entry Record (ConversationLog persistence)

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
