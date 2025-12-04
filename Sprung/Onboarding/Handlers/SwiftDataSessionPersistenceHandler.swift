//
//  SwiftDataSessionPersistenceHandler.swift
//  Sprung
//
//  Event-driven persistence handler for onboarding sessions using SwiftData.
//  Listens to relevant events and persists session state to OnboardingSessionStore.
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
    private let chatTranscriptStore: ChatTranscriptStore

    // MARK: - State
    private(set) var currentSession: OnboardingSession?
    private var subscriptionTasks: [Task<Void, Never>] = []
    private var isActive = false

    // MARK: - Initialization
    init(
        eventBus: EventCoordinator,
        sessionStore: OnboardingSessionStore,
        chatTranscriptStore: ChatTranscriptStore
    ) {
        self.eventBus = eventBus
        self.sessionStore = sessionStore
        self.chatTranscriptStore = chatTranscriptStore
        Logger.info("💾 SwiftDataSessionPersistenceHandler initialized", category: .ai)
    }

    // MARK: - Session Lifecycle

    /// Start a new session or resume an existing one
    func startSession(resumeExisting: Bool) -> OnboardingSession {
        if resumeExisting, let existing = sessionStore.getActiveSession() {
            currentSession = existing
            sessionStore.touchSession(existing)
            Logger.info("💾 Resuming existing session: \(existing.id)", category: .ai)
            return existing
        }

        // Create new session
        let session = sessionStore.createSession()
        currentSession = session
        Logger.info("💾 Created new session: \(session.id)", category: .ai)
        return session
    }

    /// End the current session
    func endSession(markComplete: Bool = false) {
        guard let session = currentSession else { return }

        if markComplete {
            sessionStore.completeSession(session)
            Logger.info("💾 Session completed: \(session.id)", category: .ai)
        } else {
            sessionStore.touchSession(session)
            Logger.info("💾 Session paused: \(session.id)", category: .ai)
        }

        currentSession = nil
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

        Logger.info("▶️ SwiftDataSessionPersistenceHandler started", category: .ai)
    }

    /// Stop listening to events
    func stop() {
        guard isActive else { return }
        isActive = false

        for task in subscriptionTasks {
            task.cancel()
        }
        subscriptionTasks.removeAll()

        Logger.info("⏹️ SwiftDataSessionPersistenceHandler stopped", category: .ai)
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
        case .artifactRecordPersisted(let record):
            persistArtifact(session: session, record: record)

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
        case .knowledgeCardPlanUpdated(let items, _, _):
            sessionStore.setPlanItems(session, items: items)

        case .planItemStatusChangeRequested(let itemId, let status):
            sessionStore.updatePlanItemStatus(session, itemId: itemId, status: status)

        default:
            break
        }
    }

    // MARK: - Persistence Methods

    private func persistUserMessage(session: OnboardingSession, messageId: String, payload: JSON) {
        guard let text = payload["text"].string else {
            Logger.warning("💾 Cannot persist user message: missing text", category: .ai)
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

        Logger.debug("💾 Persisted user message: \(messageId)", category: .ai)
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

        Logger.debug("💾 Persisted assistant message: \(id)", category: .ai)
    }

    private func persistArtifact(session: OnboardingSession, record: JSON) {
        let sourceType = record["source_type"].stringValue
        let filename = record["filename"].stringValue
        let extractedContent = record["extracted_text"].stringValue
        let sourceHash = record["source_hash"].string
        let metadataJSON = record["metadata"].rawString()
        let planItemId = record["plan_item_id"].string

        // Check if artifact already exists
        if sessionStore.findExistingArtifact(session, filename: filename, hash: sourceHash) != nil {
            Logger.debug("💾 Artifact already exists, skipping: \(filename)", category: .ai)
            return
        }

        _ = sessionStore.addArtifact(
            session,
            sourceType: sourceType,
            sourceFilename: filename,
            extractedContent: extractedContent,
            sourceHash: sourceHash,
            metadataJSON: metadataJSON,
            planItemId: planItemId
        )

        Logger.info("💾 Persisted artifact: \(filename)", category: .ai)
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

        Logger.info("💾 Restored session state: \(messages.count) messages", category: .ai)
    }

    /// Get restored plan items for UI
    func getRestoredPlanItems(_ session: OnboardingSession) -> [KnowledgeCardPlanItem] {
        sessionStore.restorePlanItems(session)
    }

    /// Get restored objective statuses
    func getRestoredObjectiveStatuses(_ session: OnboardingSession) -> [String: String] {
        sessionStore.restoreObjectiveStatuses(session)
    }
}
