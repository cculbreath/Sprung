//
//  SessionPersistenceService.swift
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
final class SessionPersistenceService {
    // MARK: - Dependencies
    private let eventBus: EventBus
    private let sessionStore: OnboardingSessionStore
    private let artifactRecordStore: ArtifactRecordStore

    // MARK: - State
    private(set) var currentSession: OnboardingSession?
    private var subscriptionTasks: [Task<Void, Never>] = []
    private var isActive = false

    // MARK: - Initialization
    init(
        eventBus: EventBus,
        sessionStore: OnboardingSessionStore,
        artifactRecordStore: ArtifactRecordStore
    ) {
        self.eventBus = eventBus
        self.sessionStore = sessionStore
        self.artifactRecordStore = artifactRecordStore
        Logger.info("SessionPersistenceService initialized", category: .ai)
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

        Logger.info("SessionPersistenceService started", category: .ai)
    }

    // MARK: - Event Handlers

    private func handleLLMEvent(_ event: OnboardingEvent) {
        guard let session = currentSession else { return }

        switch event {
        // ConversationLog is the single source of truth for message persistence
        case .llm(.conversationEntryAppended(let entry)):
            persistConversationEntry(session: session, entry: entry)

        case .llm(.toolResultFilled(let callId, let status)):
            updateConversationEntryToolResult(session: session, callId: callId, status: status)

        default:
            break
        }
    }

    private func handleArtifactEvent(_ event: OnboardingEvent) {
        guard let session = currentSession else { return }

        switch event {
        case .artifact(.recordProduced(let record)):
            // Persist to SwiftData when artifact is produced
            persistArtifact(session: session, record: record)

        case .artifact(.metadataUpdated(let artifact)):
            // Update metadata when artifact is updated
            updateArtifactMetadata(record: artifact)

        default:
            break
        }
    }

    private func handlePhaseEvent(_ event: OnboardingEvent) {
        guard let session = currentSession else { return }

        switch event {
        case .phase(.transitionApplied(let phase, _)):
            sessionStore.updatePhase(session, phase: phase)

        default:
            break
        }
    }

    private func handleObjectiveEvent(_ event: OnboardingEvent) {
        guard let session = currentSession else { return }

        switch event {
        case .objective(.statusChanged(let id, _, let newStatus, _, _, _, _)):
            sessionStore.updateObjective(session, objectiveId: id, status: newStatus)

        default:
            break
        }
    }

    private func handleToolEvent(_ event: OnboardingEvent) {
        guard let session = currentSession else { return }

        switch event {
        case .tool(.todoListUpdated(let todoListJSON)):
            sessionStore.updateTodoList(session, todoListJSON: todoListJSON)
            Logger.debug("💾 Persisted todo list: \(todoListJSON.count) chars", category: .ai)

        default:
            break
        }
    }

    private func handleStateEvent(_ event: OnboardingEvent) {
        guard let session = currentSession else { return }

        switch event {
        case .state(.applicantProfileStored(let profile)):
            sessionStore.updateApplicantProfile(session, profileJSON: profile.rawString())

        case .state(.skeletonTimelineStored(let timeline)):
            sessionStore.updateSkeletonTimeline(session, timelineJSON: timeline.rawString())

        case .state(.enabledSectionsUpdated(let sections)):
            sessionStore.updateEnabledSections(session, sections: sections)

        case .state(.dossierNotesUpdated(let notes)):
            sessionStore.updateDossierNotes(session, notes: notes.isEmpty ? nil : notes)

        case .state(.documentCollectionActiveChanged(let isActive)):
            sessionStore.updateDocumentCollectionActive(session, isActive: isActive)

        case .state(.timelineEditorActiveChanged(let isActive)):
            sessionStore.updateTimelineEditorActive(session, isActive: isActive)

        default:
            break
        }
    }

    private func handleTimelineEvent(_ event: OnboardingEvent) {
        guard let session = currentSession else { return }

        switch event {
        case .timeline(.skeletonReplaced(let timeline, _, _)):
            sessionStore.updateSkeletonTimeline(session, timelineJSON: timeline.rawString())

        case .timeline(.uiUpdateNeeded(let timeline)):
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
        let sourceType = record["sourceType"].stringValue
        let filename = record["filename"].stringValue
        let extractedContent = record["extractedText"].stringValue
        // `processDocument` writes the content hash under "sha256"; reading the wrong
        // key here disabled hash dedup entirely (the cause of duplicate rows on
        // re-ingest), so resumes must match by it to replace rather than duplicate.
        let sha256 = record["sha256"].string
        let contentType = record["contentType"].string
        let sizeInBytes = record["sizeBytes"].intValue
        let summary = record["summary"].string
        let briefDescription = record["briefDescription"].string
        let title = record["title"].string ?? record["metadata"]["title"].string
        let skillsJSON = record["skills"].string
        let narrativeCardsJSON = record["narrativeCards"].string
        // Intermediate representation (PDF transcription or git digest) — mapped
        // generically so any source that produces one persists it identically.
        let intermediateRepresentationJSON = record["intermediateRepresentation"].string
        // Persist the record JSON for metadata, but DROP the intermediate
        // representation: it has its own column, and a transcription/digest can be
        // large — keeping it here too would double its storage.
        var metadataRecord = record
        metadataRecord.dictionaryObject?.removeValue(forKey: "intermediateRepresentation")
        let metadataJSON = metadataRecord.rawString()
        let rawFileRelativePath = record["rawFilePath"].string
        let planItemId = record["planItemId"].string

        // Check if this is a promoted artifact (already exists with this ID globally)
        if let existingId = artifactIdString,
           artifactRecordStore.artifact(byIdString: existingId) != nil {
            // Artifact was promoted - already in SwiftData, skip re-add
            Logger.debug("Artifact already persisted (promoted): \(filename)", category: .ai)
            return
        }

        // Re-ingest / resume: an artifact with this content already exists in the
        // session. Update it in place so a more-complete re-run REPLACES the prior
        // partial record instead of inserting a duplicate (which would double-count
        // knowledge cards). reanalyzeFromIR already merged prior + reran passes, so
        // the incoming record is the authoritative, most-complete version.
        if let hash = sha256,
           let existing = artifactRecordStore.existingArtifact(in: session, filename: filename, sha256: hash) {
            artifactRecordStore.updateArtifactContent(
                existing,
                extractedContent: extractedContent,
                summary: summary,
                briefDescription: briefDescription,
                title: title,
                skillsJSON: skillsJSON,
                narrativeCardsJSON: narrativeCardsJSON,
                intermediateRepresentationJSON: intermediateRepresentationJSON,
                metadataJSON: metadataJSON
            )
            Logger.info("Artifact re-processed, updated in place: \(filename)", category: .ai)
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
            intermediateRepresentationJSON: intermediateRepresentationJSON,
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
        if let briefDescription = record["briefDescription"].string {
            artifact.briefDescription = briefDescription
        }
        if let title = record["title"].string ?? record["metadata"]["title"].string {
            artifact.title = title
        }
        if let skillsJSON = record["skills"].string {
            artifact.skillsJSON = skillsJSON
        }
        if let narrativeCardsJSON = record["narrativeCards"].string {
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
                  let toolCalls = try? JSONDecoder().decode([ToolCallSlot].self, from: data) else {
                return false
            }
            return toolCalls.contains { $0.callId == callId }
        }) else {
            Logger.warning("Cannot update tool result - entry not found for call \(callId.prefix(8))", category: .ai)
            return
        }

        // Decode, update, and re-encode tool calls. Missing JSON or a call that
        // isn't in this record are legitimate no-ops; a decode/encode FAILURE is
        // not — it silently leaves the persisted status stale, so log it loudly.
        guard let data = record.toolCallsJSON?.data(using: .utf8) else { return }
        do {
            var toolCalls = try JSONDecoder().decode([ToolCallSlot].self, from: data)
            guard let index = toolCalls.firstIndex(where: { $0.callId == callId }) else {
                return
            }

            // The result is already set in ConversationLog - we need to sync it
            // For now, just mark that the status changed (the result will be synced on session restore)
            toolCalls[index].status = ToolCallStatus(rawValue: status) ?? .completed

            let newData = try JSONEncoder().encode(toolCalls)
            guard let newJSON = String(data: newData, encoding: .utf8) else {
                Logger.error("Tool result status update dropped for \(callId.prefix(8)) — UTF-8 encoding of tool calls failed", category: .ai)
                return
            }
            record.toolCallsJSON = newJSON
            sessionStore.saveConversationEntries()
            Logger.debug("💾 Updated tool result status: \(callId.prefix(8)) → \(status)", category: .ai)
        } catch {
            Logger.error("Tool result status update dropped for \(callId.prefix(8)) — decode/encode failed: \(error.localizedDescription)", category: .ai)
        }
    }

    // MARK: - Session Restore

    /// Get restored objective statuses
    func getRestoredObjectiveStatuses(_ session: OnboardingSession) -> [String: String] {
        sessionStore.restoreObjectiveStatuses(session)
    }

    /// Get restored artifacts as JSON for restoring to ArtifactRepository
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

    /// Get restored dossier WIP notes
    func getRestoredDossierNotes(_ session: OnboardingSession) -> String? {
        sessionStore.getDossierNotes(session)
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

    /// Find a `get_user_option` choice prompt that was still awaiting the user when
    /// the session was last closed, reconstructed from the persisted tool arguments.
    ///
    /// On restore the conversation log strips the unresolved tool_use to satisfy the
    /// Anthropic "every tool_use needs a tool_result" invariant (see
    /// `ConversationLog.removeOrphanedToolCalls`), so the card would otherwise vanish.
    /// We read the *raw* persisted entries (pre-strip) here so resume can re-surface it.
    /// Returns nil when no choice prompt was pending.
    func findUnresolvedChoicePrompt(in session: OnboardingSession) -> OnboardingChoicePrompt? {
        let entries = session.conversationEntries
            .sorted { $0.sequenceIndex < $1.sequenceIndex }
            .compactMap { $0.toConversationEntry() }

        // Inspect ONLY the most recent conversational turn (skipping trailing UI-only
        // system notes). A choice prompt is still awaiting the user only if its tool_use
        // is the last thing that happened. After resume, the answer comes back as a new
        // user turn — it never back-fills the stripped slot — so the persisted slot stays
        // "unresolved" permanently. Scanning all of history would re-surface a prompt the
        // user already answered on a later turn.
        guard let lastEntry = entries.last(where: { !$0.isSystemNote }),
              case .assistant(_, _, let toolCalls?, _) = lastEntry,
              let slot = toolCalls.first(where: {
                  $0.name == OnboardingToolName.getUserOption.rawValue && !$0.isResolved
              }) else {
            return nil
        }
        guard let data = slot.arguments.data(using: .utf8),
              let json = try? JSON(data: data),
              let prompt = try? GetUserOptionArguments(json: json).toChoicePrompt() else {
            Logger.warning("⚠️ Unresolved get_user_option found on resume but its arguments could not be parsed", category: .ai)
            return nil
        }
        return prompt
    }

    /// Convert an ArtifactRecord to JSON format
    private func artifactRecordToJSON(_ record: ArtifactRecord) -> JSON {
        var json = JSON()
        json["id"].string = record.id.uuidString
        json["sourceType"].string = record.sourceType
        json["filename"].string = record.filename
        json["extractedText"].string = record.extractedContent
        json["sourceHash"].string = record.sha256
        json["rawFilePath"].string = record.rawFileRelativePath
        json["planItemId"].string = record.planItemId
        json["ingestedAt"].string = ISO8601DateFormatter().string(from: record.ingestedAt)
        json["isArchived"].bool = record.isArchived
        json["contentType"].string = record.contentType
        json["sizeBytes"].int = record.sizeInBytes
        json["summary"].string = record.summary
        json["briefDescription"].string = record.briefDescription
        json["title"].string = record.title
        json["hasSkills"].bool = record.hasSkills
        json["hasNarrativeCards"].bool = record.hasNarrativeCards
        json["skills"].string = record.skillsJSON
        json["narrativeCards"].string = record.narrativeCardsJSON
        if let metadataJSON = record.metadataJSON,
           let data = metadataJSON.data(using: .utf8),
           let metadata = try? JSON(data: data) {
            json["metadata"] = metadata
        }
        return json
    }
}
