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

        // Subscribe to LLM events (messages, previousResponseId)
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
        case .llmUserMessageSent(let messageId, let payload, _):
            persistUserMessage(session: session, messageId: messageId, payload: payload)

        case .streamingMessageFinalized(let id, let finalText, let toolCalls, _):
            persistAssistantMessage(session: session, id: id, finalText: finalText, toolCalls: toolCalls)

        case .llmResponseIdUpdated(let responseId):
            sessionStore.updatePreviousResponseId(session, responseId: responseId)

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

        case .excludedCardIdsChanged(let excludedIds):
            sessionStore.updateExcludedCardIds(session, excludedIds: excludedIds)

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

    private func persistUserMessage(session: OnboardingSession, messageId: String, payload: JSON) {
        guard let text = payload["text"].string else {
            Logger.warning("Cannot persist user message: missing text", category: .ai)
            return
        }

        let id = UUID(uuidString: messageId) ?? UUID()
        let isSystemGenerated = payload["isSystemGenerated"].boolValue

        _ = sessionStore.addMessage(
            session,
            id: id,
            role: "user",
            text: text,
            isSystemGenerated: isSystemGenerated
        )

        Logger.debug("Persisted user message: \(messageId)", category: .ai)
    }

    private func persistAssistantMessage(
        session: OnboardingSession,
        id: UUID,
        finalText: String,
        toolCalls: [OnboardingMessage.ToolCallInfo]?
    ) {
        var toolCallsJSON: String?
        if let calls = toolCalls, !calls.isEmpty {
            if let data = try? JSONEncoder().encode(calls) {
                toolCallsJSON = String(data: data, encoding: .utf8)
            }
        }

        _ = sessionStore.addMessage(
            session,
            id: id,
            role: "assistant",
            text: finalText,
            toolCallsJSON: toolCallsJSON
        )

        // Batch save after message is added
        sessionStore.saveMessages()

        Logger.debug("Persisted assistant message: \(id)", category: .ai)
    }

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
        let cardInventoryJSON = record["card_inventory"].string
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
            cardInventoryJSON: cardInventoryJSON,
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
        if let cardInventoryJSON = record["card_inventory"].string {
            artifact.cardInventoryJSON = cardInventoryJSON
        }
        // Update full metadata JSON
        artifact.metadataJSON = record.rawString()

        artifactRecordStore.updateArtifact(artifact)
        Logger.debug("Updated artifact metadata: \(artifact.filename)", category: .ai)
    }

    // MARK: - Session Restore

    /// Restore session state to in-memory stores
    func restoreSession(_ session: OnboardingSession, to chatStore: ChatTranscriptStore) async {
        // Restore messages
        let messages = sessionStore.restoreMessages(session)
        await chatStore.restoreMessages(messages)

        // Restore previousResponseId
        if let responseId = session.previousResponseId {
            await chatStore.setPreviousResponseId(responseId)
        }

        Logger.info("Restored session state: \(messages.count) messages", category: .ai)
    }

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

    /// Get restored merged inventory
    func getRestoredMergedInventory(_ session: OnboardingSession) -> MergedCardInventory? {
        guard let jsonString = sessionStore.getMergedInventory(session),
              let data = jsonString.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(MergedCardInventory.self, from: data)
    }

    /// Get restored excluded card IDs
    func getRestoredExcludedCardIds(_ session: OnboardingSession) -> Set<String> {
        sessionStore.getExcludedCardIds(session)
    }

    /// Get restored document collection active state
    func getRestoredDocumentCollectionActive(_ session: OnboardingSession) -> Bool {
        sessionStore.getDocumentCollectionActive(session)
    }

    /// Get restored timeline editor active state
    func getRestoredTimelineEditorActive(_ session: OnboardingSession) -> Bool {
        sessionStore.getTimelineEditorActive(session)
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
        json["has_card_inventory"].bool = record.hasCardInventory
        json["card_inventory"].string = record.cardInventoryJSON
        if let metadataJSON = record.metadataJSON,
           let data = metadataJSON.data(using: .utf8),
           let metadata = try? JSON(data: data) {
            json["metadata"] = metadata
        }
        return json
    }
}
