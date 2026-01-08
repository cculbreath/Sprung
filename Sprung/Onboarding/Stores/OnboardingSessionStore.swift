//
//  OnboardingSessionStore.swift
//  Sprung
//
//  Manages SwiftData persistence for onboarding sessions.
//  Enables resume functionality by persisting session state and messages.
//
//  Note: Artifact management has been moved to ArtifactRecordStore.
//
import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class OnboardingSessionStore: SwiftDataStore {
    // Note: Using unowned is safe here because:
    // 1. The ModelContext is owned by the SwiftData container at the app level
    // 2. OnboardingSessionStore is created at app startup and persists for app lifetime
    // 3. All access is @MainActor isolated
    // If crashes occur during app teardown, consider the app's deinit order.
    private(set) unowned var modelContext: ModelContext

    init(context: ModelContext) {
        modelContext = context
        Logger.info("OnboardingSessionStore initialized", category: .ai)
    }

    // MARK: - Session Management

    /// Get the most recent incomplete session (for resume)
    func getActiveSession() -> OnboardingSession? {
        var descriptor = FetchDescriptor<OnboardingSession>(
            predicate: #Predicate { !$0.isComplete },
            sortBy: [SortDescriptor(\.lastActiveAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }

    /// Get all sessions (for history/debugging)
    func getAllSessions() -> [OnboardingSession] {
        let descriptor = FetchDescriptor<OnboardingSession>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Create a new session
    func createSession(phase: String = "phase1_core_facts") -> OnboardingSession {
        let session = OnboardingSession(phase: phase)
        modelContext.insert(session)
        saveContext()
        Logger.info("Created new onboarding session: \(session.id)", category: .ai)
        return session
    }

    /// Update session's last active timestamp
    func touchSession(_ session: OnboardingSession) {
        session.lastActiveAt = Date()
        saveContext()
    }

    /// Update session phase
    func updatePhase(_ session: OnboardingSession, phase: String) {
        session.phase = phase
        session.lastActiveAt = Date()
        saveContext()
        Logger.info("Session phase updated to: \(phase)", category: .ai)
    }

    /// Mark session as complete
    func completeSession(_ session: OnboardingSession) {
        session.isComplete = true
        session.lastActiveAt = Date()
        saveContext()
        Logger.info("Session marked complete: \(session.id)", category: .ai)
    }

    /// Delete a session and all related data
    func deleteSession(_ session: OnboardingSession) {
        modelContext.delete(session)
        saveContext()
        Logger.info("Deleted session: \(session.id)", category: .ai)
    }

    // MARK: - Objective Management

    /// Update or create objective status
    func updateObjective(_ session: OnboardingSession, objectiveId: String, status: String) {
        if let existing = session.objectives.first(where: { $0.objectiveId == objectiveId }) {
            existing.status = status
            existing.updatedAt = Date()
        } else {
            let record = OnboardingObjectiveRecord(objectiveId: objectiveId, status: status)
            record.session = session
            session.objectives.append(record)
            modelContext.insert(record)
        }
        session.lastActiveAt = Date()
        saveContext()
    }

    /// Get all objectives for a session
    func getObjectives(_ session: OnboardingSession) -> [OnboardingObjectiveRecord] {
        session.objectives
    }

    // MARK: - Message Management

    /// Add a message record
    func addMessage(
        _ session: OnboardingSession,
        id: UUID = UUID(),
        role: String,
        text: String,
        isSystemGenerated: Bool = false,
        toolCallsJSON: String? = nil
    ) -> OnboardingMessageRecord {
        let record = OnboardingMessageRecord(
            id: id,
            role: role,
            text: text,
            isSystemGenerated: isSystemGenerated,
            toolCallsJSON: toolCallsJSON
        )
        record.session = session
        session.messages.append(record)
        modelContext.insert(record)
        // Don't call saveContext on every message - batch saves handled by caller
        return record
    }

    /// Update a message (for streaming finalization)
    func updateMessage(_ record: OnboardingMessageRecord, text: String, toolCallsJSON: String? = nil) {
        record.text = text
        if let json = toolCallsJSON {
            record.toolCallsJSON = json
        }
        // Don't save on every update during streaming
    }

    /// Get messages for a session (sorted by timestamp)
    func getMessages(_ session: OnboardingSession) -> [OnboardingMessageRecord] {
        session.messages.sorted { $0.timestamp < $1.timestamp }
    }

    /// Batch save messages (call after streaming completes)
    func saveMessages() {
        saveContext()
    }

    /// Batch save conversation entries (new architecture)
    func saveConversationEntries() {
        saveContext()
    }

    /// Update a message's toolCallsJSON by message ID (for tool result pairing)
    func updateMessageToolCalls(_ session: OnboardingSession, messageId: UUID, toolCallsJSON: String) {
        guard let record = session.messages.first(where: { $0.id == messageId }) else {
            Logger.warning("Cannot update message toolCalls: message \(messageId) not found in session", category: .ai)
            return
        }
        record.toolCallsJSON = toolCallsJSON
        saveContext()
        Logger.debug("💾 Updated toolCallsJSON for message \(messageId)", category: .ai)
    }

    // MARK: - Restore Helpers

    /// Convert stored messages to OnboardingMessage models
    func restoreMessages(_ session: OnboardingSession) -> [OnboardingMessage] {
        getMessages(session).map { record in
            let role: OnboardingMessageRole
            switch record.role {
            case "user": role = .user
            case "assistant": role = .assistant
            default: role = .system
            }

            var toolCalls: [OnboardingMessage.ToolCallInfo]?
            if let json = record.toolCallsJSON,
               let data = json.data(using: .utf8),
               let decoded = try? JSONDecoder().decode([OnboardingMessage.ToolCallInfo].self, from: data) {
                toolCalls = decoded
            }

            return OnboardingMessage(
                id: record.id,
                role: role,
                text: record.text,
                timestamp: record.timestamp,
                isSystemGenerated: record.isSystemGenerated,
                toolCalls: toolCalls
            )
        }
    }

    /// Convert stored objectives to dictionary
    func restoreObjectiveStatuses(_ session: OnboardingSession) -> [String: String] {
        Dictionary(uniqueKeysWithValues: getObjectives(session).map { ($0.objectiveId, $0.status) })
    }

    // MARK: - Timeline and Profile Management

    /// Update skeleton timeline JSON
    func updateSkeletonTimeline(_ session: OnboardingSession, timelineJSON: String?) {
        session.skeletonTimelineJSON = timelineJSON
        session.lastActiveAt = Date()
        saveContext()
        Logger.debug("Session skeleton timeline updated", category: .ai)
    }

    /// Get skeleton timeline JSON
    func getSkeletonTimeline(_ session: OnboardingSession) -> String? {
        session.skeletonTimelineJSON
    }

    /// Update applicant profile JSON
    func updateApplicantProfile(_ session: OnboardingSession, profileJSON: String?) {
        session.applicantProfileJSON = profileJSON
        session.lastActiveAt = Date()
        saveContext()
        Logger.debug("Session applicant profile updated", category: .ai)
    }

    /// Get applicant profile JSON
    func getApplicantProfile(_ session: OnboardingSession) -> String? {
        session.applicantProfileJSON
    }

    /// Update enabled sections
    func updateEnabledSections(_ session: OnboardingSession, sections: Set<String>) {
        session.enabledSectionsCSV = sections.sorted().joined(separator: ",")
        session.lastActiveAt = Date()
        saveContext()
        Logger.debug("Session enabled sections updated: \(sections.count) sections", category: .ai)
    }

    /// Get enabled sections
    func getEnabledSections(_ session: OnboardingSession) -> Set<String> {
        guard let csv = session.enabledSectionsCSV, !csv.isEmpty else {
            return []
        }
        return Set(csv.split(separator: ",").map { String($0) })
    }

    // MARK: - Merged Inventory Management

    /// Update merged card inventory JSON (expensive Gemini call result)
    func updateMergedInventory(_ session: OnboardingSession, inventoryJSON: String?) {
        session.mergedInventoryJSON = inventoryJSON
        session.lastActiveAt = Date()
        saveContext()
        Logger.info("Persisted merged card inventory (\(inventoryJSON?.count ?? 0) chars)", category: .ai)
    }

    /// Get merged inventory JSON
    func getMergedInventory(_ session: OnboardingSession) -> String? {
        session.mergedInventoryJSON
    }

    // MARK: - Todo List Management

    /// Update todo list JSON (LLM task tracking)
    func updateTodoList(_ session: OnboardingSession, todoListJSON: String?) {
        session.todoListJSON = todoListJSON
        session.lastActiveAt = Date()
        saveContext()
        Logger.debug("Persisted todo list (\(todoListJSON?.count ?? 0) chars)", category: .ai)
    }

    /// Get todo list JSON
    func getTodoList(_ session: OnboardingSession) -> String? {
        session.todoListJSON
    }

    // MARK: - UI State Management

    /// Update document collection active state
    func updateDocumentCollectionActive(_ session: OnboardingSession, isActive: Bool) {
        session.isDocumentCollectionActive = isActive
        session.lastActiveAt = Date()
        saveContext()
        Logger.debug("Session document collection active: \(isActive)", category: .ai)
    }

    /// Get document collection active state
    func getDocumentCollectionActive(_ session: OnboardingSession) -> Bool {
        session.isDocumentCollectionActive ?? false
    }

    /// Update timeline editor active state
    func updateTimelineEditorActive(_ session: OnboardingSession, isActive: Bool) {
        session.isTimelineEditorActive = isActive
        session.lastActiveAt = Date()
        saveContext()
        Logger.debug("Session timeline editor active: \(isActive)", category: .ai)
    }

    /// Get timeline editor active state
    func getTimelineEditorActive(_ session: OnboardingSession) -> Bool {
        session.isTimelineEditorActive ?? false
    }
}
