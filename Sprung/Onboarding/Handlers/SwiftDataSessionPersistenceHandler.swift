//
//  SwiftDataSessionPersistenceHandler.swift
//  Sprung
//
//  Event-driven persistence handler for onboarding sessions using SwiftData.
//  Listens to relevant events and persists session state to stores.
//
import Foundation
import SwiftyJSON

/// Handles SwiftData persistence of onboarding session state.
/// Listens to events and persists messages, artifacts, objectives, and plan items.
@MainActor
final class SwiftDataSessionPersistenceHandler {
    // MARK: - Dependencies
    private let eventBus: EventCoordinator
    private let sessionStore: OnboardingSessionStore
    private let artifactRecordStore: ArtifactRecordStore

    // MARK: - State
    private(set) var currentSession: OnboardingSession?
    private var subscriptionTasks: [Task<Void, Never>] = []
    private var isActive = false

    // MARK: - Initialization
    init(
        eventBus: EventCoordinator,
        sessionStore: OnboardingSessionStore,
        artifactRecordStore: ArtifactRecordStore
    ) {
        self.eventBus = eventBus
        self.sessionStore = sessionStore
        self.artifactRecordStore = artifactRecordStore
        Logger.info("SwiftDataSessionPersistenceHandler initialized", category: .ai)
    }

    // MARK: - Session Lifecycle

    /// Start a new session or resume an existing one
    func startSession(resumeExisting: Bool) -> OnboardingSession {
        if resumeExisting, let existing = sessionStore.getActiveSession() {
            currentSession = existing
            sessionStore.touchSession(existing)
            Logger.info("Resuming existing session: \(existing.id)", category: .ai)
            return existing
        }

        // Create new session
        let session = sessionStore.createSession()
        currentSession = session
        Logger.info("Created new session: \(session.id)", category: .ai)
        return session
    }

    /// End the current session
    func endSession(markComplete: Bool = false) {
        guard let session = currentSession else { return }

        if markComplete {
            sessionStore.completeSession(session)
            Logger.info("Session completed: \(session.id)", category: .ai)
        } else {
            sessionStore.touchSession(session)
            Logger.info("Session paused: \(session.id)", category: .ai)
        }

        currentSession = nil
    }

    /// Delete a session and clear current session reference if it matches
    func deleteSession(_ session: OnboardingSession) {
        if currentSession?.id == session.id {
            currentSession = nil
        }
        sessionStore.deleteSession(session)
        Logger.info("Session deleted: \(session.id)", category: .ai)
    }

    /// Check if there's an active session to resume
    func hasActiveSession() -> Bool {
        sessionStore.getActiveSession() != nil
    }

    /// Get the active session without modifying it
    func getActiveSession() -> OnboardingSession? {
        sessionStore.getActiveSession()
    }

    // MARK: - Event Subscription

    /// Start listening to events for persistence
    func start() {
        guard !isActive else { return }
        isActive = true

        // Subscribe to LLM events (messages, tool results)
        let llmTask = Task { [weak self] in
            guard let self else { return }
            for await event in await self.eventBus.stream(topic: .llm) {
                if Task.isCancelled { break }
                self.handleLLMEvent(event)
            }
        }
        subscriptionTasks.append(llmTask)

        // Subscribe to artifact events
        let artifactTask = Task { [weak self] in
            guard let self else { return }
            for await event in await self.eventBus.stream(topic: .artifact) {
                if Task.isCancelled { break }
                self.handleArtifactEvent(event)
            }
        }
        subscriptionTasks.append(artifactTask)

        // Subscribe to phase events
        let phaseTask = Task { [weak self] in
            guard let self else { return }
            for await event in await self.eventBus.stream(topic: .phase) {
                if Task.isCancelled { break }
                self.handlePhaseEvent(event)
            }
        }
        subscriptionTasks.append(phaseTask)

        // Subscribe to objective events
        let objectiveTask = Task { [weak self] in
            guard let self else { return }
            for await event in await self.eventBus.stream(topic: .objective) {
                if Task.isCancelled { break }
                self.handleObjectiveEvent(event)
            }
        }
        subscriptionTasks.append(objectiveTask)

        // Subscribe to tool events (for plan items)
        let toolTask = Task { [weak self] in
            guard let self else { return }
            for await event in await self.eventBus.stream(topic: .tool) {
                if Task.isCancelled { break }
                self.handleToolEvent(event)
            }
        }
        subscriptionTasks.append(toolTask)

        // Subscribe to state events (for timeline, profile, sections)
        let stateTask = Task { [weak self] in
            guard let self else { return }
            for await event in await self.eventBus.stream(topic: .state) {
                if Task.isCancelled { break }
                self.handleStateEvent(event)
            }
        }
        subscriptionTasks.append(stateTask)

        // Subscribe to timeline events
        let timelineTask = Task { [weak self] in
            guard let self else { return }
            for await event in await self.eventBus.stream(topic: .timeline) {
                if Task.isCancelled { break }
                self.handleTimelineEvent(event)
            }
        }
        subscriptionTasks.append(timelineTask)

        Logger.info("SwiftDataSessionPersistenceHandler started", category: .ai)
    }

    /// Stop listening to events
    func stop() {
        guard isActive else { return }
        isActive = false

        for task in subscriptionTasks {
            task.cancel()
        }
        subscriptionTasks.removeAll()

        Logger.info("SwiftDataSessionPersistenceHandler stopped", category: .ai)
    }

    // MARK: - Event Handlers

    private func handleLLMEvent(_ event: OnboardingEvent) {
        guard let session = currentSession else { return }

        switch event {
        // ConversationLog is the single source of truth for message persistence
        case .conversationEntryAppended(let entry):
            persistConversationEntry(session: session, entry: entry)

        case .toolResultFilled(let callId, let status):
            updateConversationEntryToolResult(session: session, callId: callId, status: status)

        default:
            break
        }
    }

    private func handleArtifactEvent(_ event: OnboardingEvent) {
        guard let session = currentSession else { return }

        switch event {
        case .artifactRecordProduced(let record):
            // Persist to SwiftData when artifact is produced
            persistArtifact(session: session, record: record)

        case .artifactMetadataUpdated(let artifact):
            // Update metadata when artifact is updated
            updateArtifactMetadata(record: artifact)

        default:
            break
        }
    }

    private func handlePhaseEvent(_ event: OnboardingEvent) {
        guard let session = currentSession else { return }

        switch event {
        case .phaseTransitionApplied(let phase, _):
            sessionStore.updatePhase(session, phase: phase)

        default:
            break
        }
    }

    private func handleObjectiveEvent(_ event: OnboardingEvent) {
        guard let session = currentSession else { return }

        switch event {
        case .objectiveStatusChanged(let id, _, let newStatus, _, _, _, _):
            sessionStore.updateObjective(session, objectiveId: id, status: newStatus)

        default:
            break
        }
    }

    private func handleToolEvent(_ event: OnboardingEvent) {
        guard let session = currentSession else { return }

        switch event {
        case .mergedInventoryStored(let inventoryJSON):
            sessionStore.updateMergedInventory(session, inventoryJSON: inventoryJSON)

        case .todoListUpdated(let todoListJSON):
            sessionStore.updateTodoList(session, todoListJSON: todoListJSON)
            Logger.debug("💾 Persisted todo list: \(todoListJSON.count) chars", category: .ai)

        default:
            break
        }
    }

    private func handleStateEvent(_ event: OnboardingEvent) {
        guard let session = currentSession else { return }

        switch event {
        case .applicantProfileStored(let profile):
            sessionStore.updateApplicantProfile(session, profileJSON: profile.rawString())

        case .skeletonTimelineStored(let timeline):
            sessionStore.updateSkeletonTimeline(session, timelineJSON: timeline.rawString())

        case .enabledSectionsUpdated(let sections):
            sessionStore.updateEnabledSections(session, sections: sections)

        case .documentCollectionActiveChanged(let isActive):
            sessionStore.updateDocumentCollectionActive(session, isActive: isActive)

        case .timelineEditorActiveChanged(let isActive):
            sessionStore.updateTimelineEditorActive(session, isActive: isActive)

        default:
            break
        }
    }

    private func handleTimelineEvent(_ event: OnboardingEvent) {
        guard let session = currentSession else { return }

        switch event {
        case .skeletonTimelineReplaced(let timeline, _, _):
            sessionStore.updateSkeletonTimeline(session, timelineJSON: timeline.rawString())

        case .timelineUIUpdateNeeded(let timeline):
            // Persist timeline when individual cards are created/updated/deleted
            sessionStore.updateSkeletonTimeline(session, timelineJSON: timeline.rawString())
            Logger.debug("Persisted timeline after card update (\(timeline["experiences"].array?.count ?? 0) cards)", category: .ai)

        default:
            break
        }
    }

    // MARK: - Persistence Methods

    private func persistArtifact(session: OnboardingSession, record: JSON) {
        let artifactIdString = record["id"].string
        let sourceType = record["source_type"].stringValue
        let filename = record["filename"].stringValue
        let extractedContent = record["extracted_text"].stringValue
        let sha256 = record["source_hash"].string
        let contentType = record["content_type"].string
        let sizeInBytes = record["size_bytes"].intValue
        let summary = record["summary"].string
        let briefDescription = record["brief_description"].string
        let title = record["title"].string ?? record["metadata"]["title"].string
        let skillsJSON = record["skills"].string
        let narrativeCardsJSON = record["narrative_cards"].string
        // Persist the full record JSON for metadata
        let metadataJSON = record.rawString()
        let rawFileRelativePath = record["raw_file_path"].string
        let planItemId = record["plan_item_id"].string

        // Check if this is a promoted artifact (already exists with this ID globally)
        if let existingId = artifactIdString,
           artifactRecordStore.artifact(byIdString: existingId) != nil {
            // Artifact was promoted - already in SwiftData, skip re-add
            Logger.debug("Artifact already persisted (promoted): \(filename)", category: .ai)
            return
        }

        // Check if artifact already exists in this session by hash
        if let hash = sha256,
           artifactRecordStore.existingArtifact(in: session, filename: filename, sha256: hash) != nil {
            Logger.debug("Artifact already exists in session, skipping: \(filename)", category: .ai)
            return
        }

        _ = artifactRecordStore.addArtifact(
            to: session,
            sourceType: sourceType,
            filename: filename,
            extractedContent: extractedContent,
            sha256: sha256,
            contentType: contentType,
            sizeInBytes: sizeInBytes,
            summary: summary,
            briefDescription: briefDescription,
            title: title,
            skillsJSON: skillsJSON,
            narrativeCardsJSON: narrativeCardsJSON,
            metadataJSON: metadataJSON,
            rawFileRelativePath: rawFileRelativePath,
            planItemId: planItemId
        )

        Logger.info("Persisted artifact: \(filename)", category: .ai)
    }

    private func updateArtifactMetadata(record: JSON) {
        guard let idString = record["id"].string,
              let artifact = artifactRecordStore.artifact(byIdString: idString) else {
            Logger.warning("Cannot update artifact metadata: artifact not found", category: .ai)
            return
        }

        // Update fields from JSON
        if let summary = record["summary"].string {
            artifact.summary = summary
        }
        if let briefDescription = record["brief_description"].string {
            artifact.briefDescription = briefDescription
        }
        if let title = record["title"].string ?? record["metadata"]["title"].string {
            artifact.title = title
        }
        if let skillsJSON = record["skills"].string {
            artifact.skillsJSON = skillsJSON
        }
        if let narrativeCardsJSON = record["narrative_cards"].string {
            artifact.narrativeCardsJSON = narrativeCardsJSON
        }
        // Update full metadata JSON
        artifact.metadataJSON = record.rawString()

        artifactRecordStore.updateArtifact(artifact)
        Logger.debug("Updated artifact metadata: \(artifact.filename)", category: .ai)
    }

    // MARK: - ConversationLog Persistence (New Architecture)

    /// Persist a ConversationEntry to SwiftData
    private func persistConversationEntry(session: OnboardingSession, entry: ConversationEntry) {
        // Calculate sequence index
        let sequenceIndex = session.conversationEntries.count

        let record = ConversationEntryRecord.from(entry, sequenceIndex: sequenceIndex)
        record.session = session
        session.conversationEntries.append(record)

        sessionStore.saveConversationEntries()

        Logger.debug("💾 Persisted conversation entry: \(entry.isUser ? "user" : "assistant") (seq: \(sequenceIndex))", category: .ai)
    }

    /// Update a tool result in a persisted ConversationEntry
    private func updateConversationEntryToolResult(session: OnboardingSession, callId: String, status: String) {
        // Find the last assistant entry that contains this tool call
        guard let record = session.conversationEntries.last(where: { entry in
            guard entry.entryType == "assistant",
                  let toolCallsJSON = entry.toolCallsJSON,
                  let data = toolCallsJSON.data(using: .utf8),
                  let toolCalls = try? JSONDecoder().decode([ToolCall].self, from: data) else {
                return false
            }
            return toolCalls.contains { $0.callId == callId }
        }) else {
            Logger.warning("Cannot update tool result - entry not found for call \(callId.prefix(8))", category: .ai)
            return
        }

        // Decode, update, and re-encode tool calls
        guard let data = record.toolCallsJSON?.data(using: .utf8),
              var toolCalls = try? JSONDecoder().decode([ToolCall].self, from: data),
              let index = toolCalls.firstIndex(where: { $0.callId == callId }) else {
            return
        }

        // The result is already set in ConversationLog - we need to sync it
        // For now, just mark that the status changed (the result will be synced on session restore)
        toolCalls[index].status = ToolCallStatus(rawValue: status) ?? .completed

        if let newData = try? JSONEncoder().encode(toolCalls),
           let newJSON = String(data: newData, encoding: .utf8) {
            record.toolCallsJSON = newJSON
            sessionStore.saveConversationEntries()
            Logger.debug("💾 Updated tool result status: \(callId.prefix(8)) → \(status)", category: .ai)
        }
    }

    // MARK: - Session Restore

    /// Get restored objective statuses
    func getRestoredObjectiveStatuses(_ session: OnboardingSession) -> [String: String] {
        sessionStore.restoreObjectiveStatuses(session)
    }

    /// Get restored artifacts as JSON for restoring to ArtifactRepository (legacy support)
    func getRestoredArtifacts(_ session: OnboardingSession) -> [JSON] {
        artifactRecordStore.artifacts(for: session).map { artifactRecordToJSON($0) }
    }

    /// Get restored skeleton timeline JSON
    func getRestoredSkeletonTimeline(_ session: OnboardingSession) -> JSON? {
        guard let jsonString = sessionStore.getSkeletonTimeline(session),
              let data = jsonString.data(using: .utf8) else {
            return nil
        }
        return try? JSON(data: data)
    }

    /// Get restored applicant profile JSON
    func getRestoredApplicantProfile(_ session: OnboardingSession) -> JSON? {
        guard let jsonString = sessionStore.getApplicantProfile(session),
              let data = jsonString.data(using: .utf8) else {
            return nil
        }
        return try? JSON(data: data)
    }

    /// Get restored enabled sections
    func getRestoredEnabledSections(_ session: OnboardingSession) -> Set<String> {
        sessionStore.getEnabledSections(session)
    }

    /// Get restored aggregated narrative cards by aggregating from all session artifacts
    /// Note: Skills and narrative cards are stored per-document in artifacts
    func getRestoredAggregatedNarrativeCards(_ session: OnboardingSession) -> [KnowledgeCard] {
        var allCards: [KnowledgeCard] = []

        for artifact in artifactRecordStore.artifacts(for: session) {
            if let cards = artifact.narrativeCards {
                allCards.append(contentsOf: cards)
            }
        }

        if !allCards.isEmpty {
            Logger.info("📥 Restored \(allCards.count) narrative cards from \(artifactRecordStore.artifacts(for: session).count) artifacts", category: .ai)
        }

        return allCards
    }

    /// Get restored aggregated skill bank by aggregating skills from all session artifacts
    func getRestoredAggregatedSkillBank(_ session: OnboardingSession) -> SkillBank? {
        var allSkills: [Skill] = []
        var sourceDocumentIds: [String] = []

        for artifact in artifactRecordStore.artifacts(for: session) {
            if let skills = artifact.skills, !skills.isEmpty {
                allSkills.append(contentsOf: skills)
                sourceDocumentIds.append(artifact.id.uuidString)
            }
        }

        guard !allSkills.isEmpty else { return nil }

        Logger.info("📥 Restored \(allSkills.count) skills from \(sourceDocumentIds.count) artifacts", category: .ai)

        return SkillBank(
            skills: allSkills,
            generatedAt: Date(),
            sourceDocumentIds: sourceDocumentIds
        )
    }

    /// Get restored document collection active state
    func getRestoredDocumentCollectionActive(_ session: OnboardingSession) -> Bool {
        sessionStore.getDocumentCollectionActive(session)
    }

    /// Get restored timeline editor active state
    func getRestoredTimelineEditorActive(_ session: OnboardingSession) -> Bool {
        sessionStore.getTimelineEditorActive(session)
    }

    /// Get restored todo list JSON
    func getRestoredTodoList(_ session: OnboardingSession) -> String? {
        sessionStore.getTodoList(session)
    }

    // MARK: - ConversationLog Restore (New Architecture)

    /// Restore ConversationLog entries from SwiftData
    func restoreConversationLog(_ session: OnboardingSession, to conversationLog: ConversationLog) async {
        let entries = session.conversationEntries
            .sorted { $0.sequenceIndex < $1.sequenceIndex }
            .compactMap { $0.toConversationEntry() }

        await conversationLog.restore(entries: entries)
        Logger.info("📥 Restored \(entries.count) conversation entries to ConversationLog", category: .ai)
    }

    // MARK: - Archived Artifacts

    /// Get archived artifacts count (for UI visibility decisions)
    func getArchivedArtifactsCount() -> Int {
        artifactRecordStore.archivedArtifacts.count
    }

    /// Convert an ArtifactRecord to JSON format
    private func artifactRecordToJSON(_ record: ArtifactRecord) -> JSON {
        var json = JSON()
        json["id"].string = record.id.uuidString
        json["source_type"].string = record.sourceType
        json["filename"].string = record.filename
        json["extracted_text"].string = record.extractedContent
        json["source_hash"].string = record.sha256
        json["raw_file_path"].string = record.rawFileRelativePath
        json["plan_item_id"].string = record.planItemId
        json["ingested_at"].string = ISO8601DateFormatter().string(from: record.ingestedAt)
        json["is_archived"].bool = record.isArchived
        json["content_type"].string = record.contentType
        json["size_bytes"].int = record.sizeInBytes
        json["summary"].string = record.summary
        json["brief_description"].string = record.briefDescription
        json["title"].string = record.title
        json["has_skills"].bool = record.hasSkills
        json["has_narrative_cards"].bool = record.hasNarrativeCards
        json["skills"].string = record.skillsJSON
        json["narrative_cards"].string = record.narrativeCardsJSON
        if let metadataJSON = record.metadataJSON,
           let data = metadataJSON.data(using: .utf8),
           let metadata = try? JSON(data: data) {
            json["metadata"] = metadata
        }
        return json
    }
}
