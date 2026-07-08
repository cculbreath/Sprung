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
final class OnboardingSessionStore {
    /// Weak reference to ModelContext to prevent crashes during container teardown.
    /// Operations gracefully fail if context is deallocated.
    private(set) weak var modelContext: ModelContext?

    init(context: ModelContext) {
        modelContext = context
        Logger.info("OnboardingSessionStore initialized", category: .ai)
    }

    // MARK: - Context Management

    /// Attempts to save the context, handling deallocated context gracefully.
    @discardableResult
    private func saveContext() -> Bool {
        guard let context = modelContext else {
            Logger.warning("ModelContext deallocated, skipping save", category: .storage)
            return false
        }
        do {
            try context.save()
            return true
        } catch {
            Logger.error("SwiftData save failed: \(error.localizedDescription)", category: .storage)
            SaveFailureToastThrottle.showIfNeeded()
            return false
        }
    }

    // MARK: - Session Management

    /// Get the most recent incomplete session (for resume)
    func getActiveSession() -> OnboardingSession? {
        guard let modelContext else { return nil }
        var descriptor = FetchDescriptor<OnboardingSession>(
            predicate: #Predicate { !$0.isComplete },
            sortBy: [SortDescriptor(\.lastActiveAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }

    /// Get all sessions (for history/debugging)
    func getAllSessions() -> [OnboardingSession] {
        guard let modelContext else { return [] }
        let descriptor = FetchDescriptor<OnboardingSession>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Create a new session
    func createSession(phase: String = "phase1_core_facts") -> OnboardingSession {
        let session = OnboardingSession(phase: phase)
        guard let modelContext else {
            Logger.warning("ModelContext deallocated, cannot insert session", category: .ai)
            return session
        }
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
        guard let modelContext else {
            Logger.warning("ModelContext deallocated, cannot delete session", category: .ai)
            return
        }
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
            if let modelContext {
                modelContext.insert(record)
            }
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
        if let modelContext {
            modelContext.insert(record)
        }
        // Don't call saveContext on every message - batch saves handled by caller
        return record
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

    // MARK: - Restore Helpers

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

    /// Update section configuration
    func updateSectionConfig(_ session: OnboardingSession, config: SectionConfig) {
        do {
            session.sectionConfigJSON = try config.toJSON()
            session.lastActiveAt = Date()
            saveContext()
            Logger.debug(
                "Session section config updated: \(config.enabledSections.count) sections, \(config.customFields.count) custom fields",
                category: .ai
            )
        } catch {
            Logger.error("Failed to encode section config: \(error)", category: .ai)
            ToastCenter.shared.show(.error("Couldn't save your section selection — \(error.localizedDescription)"))
        }
    }

    /// Get section configuration
    func getSectionConfig(_ session: OnboardingSession) -> SectionConfig {
        guard let json = session.sectionConfigJSON, !json.isEmpty else {
            return SectionConfig()
        }
        do {
            return try SectionConfig.from(json: json)
        } catch {
            Logger.error("Failed to decode section config: \(error)", category: .ai)
            ToastCenter.shared.show(.error("Section configuration appears corrupted and couldn't be loaded — your section selection may have reset. \(error.localizedDescription)"))
            return SectionConfig()
        }
    }

    /// Update enabled sections (convenience method that preserves custom fields)
    func updateEnabledSections(_ session: OnboardingSession, sections: Set<String>) {
        var config = getSectionConfig(session)
        config.enabledSections = sections
        updateSectionConfig(session, config: config)
    }

    /// Get enabled sections (convenience method)
    func getEnabledSections(_ session: OnboardingSession) -> Set<String> {
        getSectionConfig(session).enabledSections
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

    // MARK: - Dossier Notes Management

    /// Update dossier WIP notes (LLM scratchpad for interview)
    func updateDossierNotes(_ session: OnboardingSession, notes: String?) {
        session.dossierNotesJSON = notes
        session.lastActiveAt = Date()
        saveContext()
        Logger.debug("Persisted dossier notes (\(notes?.count ?? 0) chars)", category: .ai)
    }

    /// Get dossier notes
    func getDossierNotes(_ session: OnboardingSession) -> String? {
        session.dossierNotesJSON
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
