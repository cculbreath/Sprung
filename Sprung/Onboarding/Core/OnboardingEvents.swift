//
//  OnboardingEvents.swift
//  Sprung
//
//  Event-driven architecture for the onboarding system.
//  Events are grouped into nested enums by topic for better organization.
//
import Foundation
import SwiftyJSON

// MARK: - Supporting Types

/// Information about a processed upload file
struct ProcessedUploadInfo {
    let storageURL: URL
    let contentType: String?
    let filename: String
}

/// LLM status for status events
enum LLMStatus: String {
    case busy
    case idle
    case error
}

// MARK: - OnboardingEvent (Grouped by Topic)

/// All events that can occur during the onboarding interview, grouped by topic.
enum OnboardingEvent {
    // MARK: - Event Groups

    /// LLM and streaming events
    case llm(LLMEvent)

    /// Processing state and extraction events
    case processing(ProcessingEvent)

    /// Tool UI prompt events (choice, upload, validation)
    case toolpane(ToolpaneEvent)

    /// Artifact and upload events
    case artifact(ArtifactEvent)

    /// Data storage and state events
    case state(StateEvent)

    /// Phase transition events
    case phase(PhaseEvent)

    /// Objective status events
    case objective(ObjectiveEvent)

    /// Tool execution events
    case tool(ToolEvent)

    /// Timeline operations events
    case timeline(TimelineEvent)
}

// MARK: - LLM Events

extension OnboardingEvent {
    /// Events related to LLM communication, streaming, and conversation log
    enum LLMEvent: Sendable {
        // Streaming messages
        case streamingMessageBegan(id: UUID, text: String, statusMessage: String? = nil)
        case streamingMessageUpdated(id: UUID, delta: String, statusMessage: String? = nil)
        case streamingMessageFinalized(id: UUID, finalText: String, toolCalls: [OnboardingMessage.ToolCallInfo]? = nil, statusMessage: String? = nil)

        // Message lifecycle
        case chatboxUserMessageAdded(messageId: String)
        case userMessageFailed(messageId: String, originalText: String, error: String)
        case userMessageSent(messageId: String, payload: JSON, isSystemGenerated: Bool = false)
        case coordinatorMessageSent(messageId: String, payload: JSON)
        case sentToolResponseMessage(messageId: String, payload: JSON)

        // Message requests
        case sendUserMessage(payload: JSON, isSystemGenerated: Bool = false, chatboxMessageId: String? = nil, originalText: String? = nil)
        case sendCoordinatorMessage(payload: JSON)
        case toolResponseMessage(payload: JSON)

        // Queue operations
        case enqueueUserMessage(payload: JSON, isSystemGenerated: Bool, chatboxMessageId: String? = nil, originalText: String? = nil)
        case enqueueToolResponse(payload: JSON)

        // Batch operations
        case toolCallBatchStarted(expectedCount: Int, callIds: [String])
        case executeBatchedToolResponses(payloads: [JSON])

        // Execution events
        case executeUserMessage(payload: JSON, isSystemGenerated: Bool, chatboxMessageId: String? = nil, originalText: String? = nil, bundledCoordinatorMessages: [JSON] = [])
        case executeToolResponse(payload: JSON)
        case executeCoordinatorMessage(payload: JSON)
        case streamCompleted
        case cancelRequested

        // Status and usage
        case status(LLMStatus)
        case tokenUsageReceived(modelId: String, inputTokens: Int, outputTokens: Int, cachedTokens: Int, reasoningTokens: Int, source: UsageSource)

        // Conversation log
        case conversationEntryAppended(entry: ConversationEntry)
        case toolResultFilled(callId: String, status: String)
    }
}

// MARK: - Processing Events

extension OnboardingEvent {
    /// Events related to processing state, extraction, and git agent progress
    enum ProcessingEvent: Sendable {
        // Processing state
        case stateChanged(isProcessing: Bool, statusMessage: String? = nil)
        case waitingStateChanged(String?, statusMessage: String? = nil)
        case errorOccurred(String)

        // Extraction state (non-blocking)
        case extractionStateChanged(inProgress: Bool, statusMessage: String? = nil)
        case pendingExtractionUpdated(OnboardingPendingExtraction?, statusMessage: String? = nil)

        // Batch upload state
        case batchUploadStarted(expectedCount: Int)
        case batchUploadCompleted

        // Git agent progress
        case gitAgentTurnStarted(turn: Int, maxTurns: Int)
        case gitAgentToolExecuting(toolName: String, turn: Int)
        case gitAgentProgressUpdated(message: String, turn: Int)
    }
}

// MARK: - Toolpane Events

extension OnboardingEvent {
    /// Events related to tool UI prompts (choice, upload, validation, etc.)
    enum ToolpaneEvent: Sendable {
        // Choice prompts
        case choicePromptRequested(prompt: OnboardingChoicePrompt)
        case choicePromptCleared

        // Upload requests
        case uploadRequestPresented(request: OnboardingUploadRequest)
        case uploadRequestCancelled(id: UUID)

        // Validation prompts
        case validationPromptRequested(prompt: OnboardingValidationPrompt)
        case validationPromptCleared

        // Profile intake
        case applicantProfileIntakeRequested
        case applicantProfileIntakeCleared

        // Section toggle
        case sectionToggleRequested(request: OnboardingSectionToggleRequest)
        case sectionToggleCleared
    }
}

// MARK: - Artifact Events

extension OnboardingEvent {
    /// Events related to artifacts, uploads, and knowledge extraction
    enum ArtifactEvent: Sendable {
        // Upload completion
        case uploadCompleted(files: [ProcessedUploadInfo], requestKind: String, callId: String?, metadata: JSON)

        // Artifact pipeline
        case recordProduced(record: JSON)
        case metadataUpdateRequested(artifactId: String, updates: JSON)
        case metadataUpdated(artifact: JSON)

        // Knowledge cards
        case knowledgeCardPersisted(card: JSON)

        // Card generation workflow
        case doneWithUploadsClicked
        case generateCardsButtonClicked
        case mergeComplete(cardCount: Int, gapCount: Int)

        // Phase 3 artifacts
        case writingSamplePersisted(sample: JSON)
        case candidateDossierPersisted(dossier: JSON)
        case experienceDefaultsGenerated(defaults: JSON)

        // Voice primer
        case voicePrimerExtractionStarted(sampleCount: Int)
        case voicePrimerExtractionCompleted(primer: JSON)
        case voicePrimerExtractionFailed(error: String)
    }
}

// MARK: - State Events

extension OnboardingEvent {
    /// Events related to state storage and allowed tools
    enum StateEvent: Sendable {
        // Data storage
        case applicantProfileStored(JSON)
        case skeletonTimelineStored(JSON)
        case enabledSectionsUpdated(Set<String>)

        // UI state
        case documentCollectionActiveChanged(Bool)
        case timelineEditorActiveChanged(Bool)

        // Allowed tools
        case allowedToolsUpdated(tools: Set<String>)
    }
}

// MARK: - Phase Events

extension OnboardingEvent {
    /// Events related to phase transitions
    enum PhaseEvent: Sendable {
        case transitionRequested(from: String, to: String, reason: String?)
        case transitionApplied(phase: String, timestamp: Date)
    }
}

// MARK: - Objective Events

extension OnboardingEvent {
    /// Events related to objective status changes
    enum ObjectiveEvent: Sendable {
        case statusUpdateRequested(id: String, status: String, source: String?, notes: String?, details: [String: String]?)
        case statusChanged(id: String, oldStatus: String?, newStatus: String, phase: String, source: String?, notes: String?, details: [String: String]?)
    }
}

// MARK: - Tool Events

extension OnboardingEvent {
    /// Events related to tool execution
    enum ToolEvent: Sendable {
        case callRequested(ToolCall, statusMessage: String? = nil)
        case todoListUpdated(todoListJSON: String)
    }
}

// MARK: - Timeline Events

extension OnboardingEvent {
    /// Events related to timeline operations
    enum TimelineEvent: Sendable {
        case cardCreated(card: JSON)
        case cardUpdated(id: String, fields: JSON)
        case cardDeleted(id: String, fromUI: Bool = false)
        case cardsReordered(ids: [String])
        case uiUpdateNeeded(timeline: JSON)
        case skeletonReplaced(timeline: JSON, diff: TimelineDiff?, meta: JSON?)
    }
}

// MARK: - Event Topics

/// Event topics for routing
enum EventTopic: String, CaseIterable {
    case llm = "LLM"
    case toolpane = "Toolpane"
    case artifact = "Artifact"
    case userInput = "UserInput"
    case state = "State"
    case phase = "Phase"
    case objective = "Objective"
    case tool = "Tool"
    case timeline = "Timeline"
    case processing = "Processing"
}

// MARK: - OnboardingEvent Helpers

extension OnboardingEvent {
    /// Extract the topic from the event
    var topic: EventTopic {
        switch self {
        case .llm: return .llm
        case .processing: return .processing
        case .toolpane: return .toolpane
        case .artifact: return .artifact
        case .state: return .state
        case .phase: return .phase
        case .objective: return .objective
        case .tool: return .tool
        case .timeline: return .timeline
        }
    }

    /// Concise log description that avoids logging full JSON payloads
    var logDescription: String {
        switch self {
        case .llm(let event):
            return event.logDescription
        case .processing(let event):
            return event.logDescription
        case .toolpane(let event):
            return event.logDescription
        case .artifact(let event):
            return event.logDescription
        case .state(let event):
            return event.logDescription
        case .phase(let event):
            return event.logDescription
        case .objective(let event):
            return event.logDescription
        case .tool(let event):
            return event.logDescription
        case .timeline(let event):
            return event.logDescription
        }
    }
}

// MARK: - Nested Event Log Descriptions

extension OnboardingEvent.LLMEvent {
    var logDescription: String {
        switch self {
        case .streamingMessageBegan(let id, _, let statusMessage):
            let statusInfo = statusMessage.map { " - \($0)" } ?? ""
            return "llm.streamingMessageBegan(id: \(id))\(statusInfo)"
        case .streamingMessageUpdated(let id, _, let statusMessage):
            let statusInfo = statusMessage.map { " - \($0)" } ?? ""
            return "llm.streamingMessageUpdated(id: \(id))\(statusInfo)"
        case .streamingMessageFinalized(let id, let finalText, let toolCalls, _):
            let textPreview = finalText.prefix(50).replacingOccurrences(of: "\n", with: " ")
            return "llm.streamingMessageFinalized(id: \(id), text: \"\(textPreview)...\", toolCalls: \(toolCalls?.count ?? 0))"
        case .chatboxUserMessageAdded(let messageId):
            return "llm.chatboxUserMessageAdded(\(messageId.prefix(8))...)"
        case .userMessageFailed(let messageId, _, let error):
            return "llm.userMessageFailed(\(messageId.prefix(8))..., error: \(error.prefix(50)))"
        case .userMessageSent(let messageId, _, let isSystemGenerated):
            return "llm.userMessageSent(\(messageId.prefix(8))..., isSystemGenerated: \(isSystemGenerated))"
        case .coordinatorMessageSent(let messageId, _):
            return "llm.coordinatorMessageSent(\(messageId.prefix(8))...)"
        case .sentToolResponseMessage(let messageId, _):
            return "llm.sentToolResponseMessage(\(messageId.prefix(8))...)"
        case .sendUserMessage(_, let isSystemGenerated, _, _):
            return "llm.sendUserMessage(isSystemGenerated: \(isSystemGenerated))"
        case .sendCoordinatorMessage:
            return "llm.sendCoordinatorMessage"
        case .toolResponseMessage:
            return "llm.toolResponseMessage"
        case .enqueueUserMessage(_, let isSystemGenerated, let chatboxId, _):
            let chatboxInfo = chatboxId.map { " chatbox:\($0.prefix(8))..." } ?? ""
            return "llm.enqueueUserMessage(system: \(isSystemGenerated)\(chatboxInfo))"
        case .enqueueToolResponse:
            return "llm.enqueueToolResponse"
        case .toolCallBatchStarted(let expectedCount, _):
            return "llm.toolCallBatchStarted(expecting \(expectedCount))"
        case .executeBatchedToolResponses(let payloads):
            return "llm.executeBatchedToolResponses(count: \(payloads.count))"
        case .executeUserMessage(_, let isSystemGenerated, let chatboxId, _, let bundled):
            let chatboxInfo = chatboxId.map { " chatbox:\($0.prefix(8))..." } ?? ""
            let bundledInfo = bundled.isEmpty ? "" : " +\(bundled.count) coord msgs"
            return "llm.executeUserMessage(system: \(isSystemGenerated)\(chatboxInfo)\(bundledInfo))"
        case .executeToolResponse:
            return "llm.executeToolResponse"
        case .executeCoordinatorMessage:
            return "llm.executeCoordinatorMessage"
        case .streamCompleted:
            return "llm.streamCompleted"
        case .cancelRequested:
            return "llm.cancelRequested"
        case .status(let status):
            return "llm.status(\(status.rawValue))"
        case .tokenUsageReceived(let modelId, let input, let output, let cached, _, let source):
            let cachedStr = cached > 0 ? ", cached: \(cached)" : ""
            return "llm.tokenUsage[\(source.displayName)]: \(modelId) - in: \(input), out: \(output)\(cachedStr)"
        case .conversationEntryAppended(let entry):
            return "llm.conversationEntryAppended(\(entry.isUser ? "user" : "assistant"), id: \(entry.id))"
        case .toolResultFilled(let callId, let status):
            return "llm.toolResultFilled(\(callId.prefix(8))..., status: \(status))"
        }
    }
}

extension OnboardingEvent.ProcessingEvent {
    var logDescription: String {
        switch self {
        case .stateChanged(let isProcessing, let statusMessage):
            let statusInfo = statusMessage.map { " - \($0)" } ?? ""
            return "processing.stateChanged(\(isProcessing))\(statusInfo)"
        case .waitingStateChanged(let state, let statusMessage):
            let statusInfo = statusMessage.map { " - \($0)" } ?? ""
            return "processing.waitingStateChanged(\(state ?? "nil"))\(statusInfo)"
        case .errorOccurred(let error):
            return "processing.errorOccurred(\(error.prefix(50)))"
        case .extractionStateChanged(let inProgress, let statusMessage):
            let statusInfo = statusMessage.map { " - \($0)" } ?? ""
            return "processing.extractionStateChanged(\(inProgress))\(statusInfo)"
        case .pendingExtractionUpdated(let extraction, let statusMessage):
            let statusInfo = statusMessage.map { " - \($0)" } ?? ""
            return "processing.pendingExtractionUpdated(\(extraction?.title ?? "nil"))\(statusInfo)"
        case .batchUploadStarted(let expectedCount):
            return "processing.batchUploadStarted(expecting \(expectedCount))"
        case .batchUploadCompleted:
            return "processing.batchUploadCompleted"
        case .gitAgentTurnStarted(let turn, let maxTurns):
            return "processing.gitAgentTurnStarted(\(turn)/\(maxTurns))"
        case .gitAgentToolExecuting(let toolName, let turn):
            return "processing.gitAgentToolExecuting(\(toolName), turn \(turn))"
        case .gitAgentProgressUpdated(let message, let turn):
            return "processing.gitAgentProgress(turn \(turn)): \(message.prefix(50))"
        }
    }
}

extension OnboardingEvent.ToolpaneEvent {
    var logDescription: String {
        switch self {
        case .choicePromptRequested:
            return "toolpane.choicePromptRequested"
        case .choicePromptCleared:
            return "toolpane.choicePromptCleared"
        case .uploadRequestPresented:
            return "toolpane.uploadRequestPresented"
        case .uploadRequestCancelled(let id):
            return "toolpane.uploadRequestCancelled(\(id))"
        case .validationPromptRequested:
            return "toolpane.validationPromptRequested"
        case .validationPromptCleared:
            return "toolpane.validationPromptCleared"
        case .applicantProfileIntakeRequested:
            return "toolpane.applicantProfileIntakeRequested"
        case .applicantProfileIntakeCleared:
            return "toolpane.applicantProfileIntakeCleared"
        case .sectionToggleRequested:
            return "toolpane.sectionToggleRequested"
        case .sectionToggleCleared:
            return "toolpane.sectionToggleCleared"
        }
    }
}

extension OnboardingEvent.ArtifactEvent {
    var logDescription: String {
        switch self {
        case .uploadCompleted(let files, let requestKind, _, _):
            return "artifact.uploadCompleted(\(files.count) files, kind: \(requestKind))"
        case .recordProduced(let record):
            return "artifact.recordProduced(\(record["id"].stringValue.prefix(8))...)"
        case .metadataUpdateRequested(let artifactId, let updates):
            return "artifact.metadataUpdateRequested(\(artifactId.prefix(8))..., \(updates.dictionaryValue.keys.count) fields)"
        case .metadataUpdated(let artifact):
            return "artifact.metadataUpdated(\(artifact["id"].stringValue.prefix(8))...)"
        case .knowledgeCardPersisted(let card):
            return "artifact.knowledgeCardPersisted(\(card["title"].stringValue.prefix(30)))"
        case .doneWithUploadsClicked:
            return "artifact.doneWithUploadsClicked"
        case .generateCardsButtonClicked:
            return "artifact.generateCardsButtonClicked"
        case .mergeComplete(let cardCount, let gapCount):
            return "artifact.mergeComplete(\(cardCount) cards, \(gapCount) gaps)"
        case .writingSamplePersisted(let sample):
            return "artifact.writingSamplePersisted(\(sample["name"].stringValue.prefix(30)))"
        case .candidateDossierPersisted:
            return "artifact.candidateDossierPersisted"
        case .experienceDefaultsGenerated(let defaults):
            let workCount = defaults["work"].arrayValue.count
            let skillsCount = defaults["skills"].arrayValue.count
            return "artifact.experienceDefaultsGenerated(\(workCount) work, \(skillsCount) skills)"
        case .voicePrimerExtractionStarted(let sampleCount):
            return "artifact.voicePrimerExtractionStarted(\(sampleCount) samples)"
        case .voicePrimerExtractionCompleted:
            return "artifact.voicePrimerExtractionCompleted"
        case .voicePrimerExtractionFailed(let error):
            return "artifact.voicePrimerExtractionFailed(\(error.prefix(50)))"
        }
    }
}

extension OnboardingEvent.StateEvent {
    var logDescription: String {
        switch self {
        case .applicantProfileStored:
            return "state.applicantProfileStored"
        case .skeletonTimelineStored:
            return "state.skeletonTimelineStored"
        case .enabledSectionsUpdated(let sections):
            return "state.enabledSectionsUpdated(\(sections.count) sections)"
        case .documentCollectionActiveChanged(let isActive):
            return "state.documentCollectionActiveChanged(\(isActive))"
        case .timelineEditorActiveChanged(let isActive):
            return "state.timelineEditorActiveChanged(\(isActive))"
        case .allowedToolsUpdated(let tools):
            return "state.allowedToolsUpdated(\(tools.count) tools)"
        }
    }
}

extension OnboardingEvent.PhaseEvent {
    var logDescription: String {
        switch self {
        case .transitionRequested(let from, let to, _):
            return "phase.transitionRequested(\(from) → \(to))"
        case .transitionApplied(let phase, _):
            return "phase.transitionApplied(\(phase))"
        }
    }
}

extension OnboardingEvent.ObjectiveEvent {
    var logDescription: String {
        switch self {
        case .statusUpdateRequested(let id, let status, _, _, _):
            return "objective.statusUpdateRequested(\(id) → \(status))"
        case .statusChanged(let id, let oldStatus, let newStatus, _, let source, _, _):
            let sourceInfo = source.map { " (source: \($0))" } ?? ""
            let oldInfo = oldStatus.map { "\($0) → " } ?? ""
            return "objective.statusChanged(\(id): \(oldInfo)\(newStatus)\(sourceInfo))"
        }
    }
}

extension OnboardingEvent.ToolEvent {
    var logDescription: String {
        switch self {
        case .callRequested(let toolCall, _):
            return "tool.callRequested(\(toolCall.name))"
        case .todoListUpdated(let json):
            return "tool.todoListUpdated(\(json.count) chars)"
        }
    }
}

extension OnboardingEvent.TimelineEvent {
    var logDescription: String {
        switch self {
        case .cardCreated:
            return "timeline.cardCreated"
        case .cardUpdated(let id, _):
            return "timeline.cardUpdated(\(id.prefix(8))...)"
        case .cardDeleted(let id, let fromUI):
            return "timeline.cardDeleted(\(id.prefix(8))...\(fromUI ? " fromUI" : ""))"
        case .cardsReordered(let ids):
            return "timeline.cardsReordered(\(ids.count) cards)"
        case .uiUpdateNeeded:
            return "timeline.uiUpdateNeeded"
        case .skeletonReplaced(_, let diff, _):
            if let diff = diff {
                return "timeline.skeletonReplaced(\(diff.summary))"
            }
            return "timeline.skeletonReplaced"
        }
    }
}

// MARK: - EventCoordinator

/// Event bus that manages event distribution using AsyncStream
actor EventCoordinator {
    // Broadcast continuations: each topic has multiple subscriber continuations
    private var subscriberContinuations: [EventTopic: [UUID: AsyncStream<OnboardingEvent>.Continuation]] = [:]

    #if DEBUG
    // Event history for debugging (debug builds only)
    private var eventHistory: [OnboardingEvent] = []
    private let maxHistorySize = 1000

    // Streaming consolidation state
    private var lastStreamingMessageId: UUID?
    private var consolidatedStreamingUpdates = 0
    private var consolidatedStreamingChars = 0

    // Metrics
    private var metrics = EventMetrics()
    #endif

    struct EventMetrics {
        var publishedCount: [EventTopic: Int] = [:]
        var lastPublishTime: [EventTopic: Date] = [:]
    }

    init() {
        // Initialize subscriber dictionaries for each topic
        for topic in EventTopic.allCases {
            subscriberContinuations[topic] = [:]
            #if DEBUG
            metrics.publishedCount[topic] = 0
            #endif
        }
        Logger.info("📡 EventCoordinator initialized with AsyncStream broadcast architecture", category: .ai)
    }

    deinit {
        // Clean up all continuations
        for continuations in subscriberContinuations.values {
            for continuation in continuations.values {
                continuation.finish()
            }
        }
    }

    /// Subscribe to events for a specific topic
    func stream(topic: EventTopic) -> AsyncStream<OnboardingEvent> {
        let subscriberId = UUID()
        let stream = AsyncStream<OnboardingEvent>(bufferingPolicy: .bufferingNewest(50)) { continuation in
            Task { [weak self] in
                await self?.registerSubscriber(subscriberId, continuation: continuation, for: topic)
            }
            continuation.onTermination = { [weak self] _ in
                Task { [weak self] in
                    await self?.unregisterSubscriber(subscriberId, for: topic)
                }
            }
        }
        Logger.debug("[EventBus] Subscriber \(subscriberId) connected to topic: \(topic.rawValue)", category: .ai)
        return stream
    }

    private func registerSubscriber(_ id: UUID, continuation: AsyncStream<OnboardingEvent>.Continuation, for topic: EventTopic) {
        subscriberContinuations[topic, default: [:]][id] = continuation
    }

    private func unregisterSubscriber(_ id: UUID, for topic: EventTopic) {
        subscriberContinuations[topic]?[id] = nil
    }

    /// Subscribe to all events (for compatibility/debugging)
    func streamAll() -> AsyncStream<OnboardingEvent> {
        let subscriberId = UUID()
        let stream = AsyncStream<OnboardingEvent>(bufferingPolicy: .unbounded) { continuation in
            Task { [weak self] in
                for topic in EventTopic.allCases {
                    await self?.registerSubscriber(subscriberId, continuation: continuation, for: topic)
                }
            }
            continuation.onTermination = { [weak self] _ in
                Task { [weak self] in
                    for topic in EventTopic.allCases {
                        await self?.unregisterSubscriber(subscriberId, for: topic)
                    }
                }
            }
        }
        Logger.debug("[EventBus] Subscriber \(subscriberId) connected to ALL topics", category: .ai)
        return stream
    }

    /// Publish an event to its appropriate topic
    func publish(_ event: OnboardingEvent) async {
        let topic = event.topic

        #if DEBUG
        // Log the event (debug builds only)
        Logger.debug("[Event] \(event.logDescription)", category: .ai)

        // Update metrics
        metrics.publishedCount[topic, default: 0] += 1
        metrics.lastPublishTime[topic] = Date()

        // Add to history with streaming event consolidation
        addToHistoryWithConsolidation(event)
        #endif

        // Broadcast to ALL subscriber continuations for this topic
        if let continuations = subscriberContinuations[topic] {
            #if DEBUG
            let subscriberCount = continuations.count
            if case .timeline(.uiUpdateNeeded) = event {
                Logger.info("[EventBus] Delivering timeline.uiUpdateNeeded to \(subscriberCount) subscriber(s)", category: .ai)
            }
            #endif
            for continuation in continuations.values {
                continuation.yield(event)
            }
        } else {
            #if DEBUG
            Logger.warning("[EventBus] No subscribers for topic: \(topic)", category: .ai)
            #endif
        }
    }

    #if DEBUG
    /// Add event to history with consolidation of streaming delta events
    private func addToHistoryWithConsolidation(_ event: OnboardingEvent) {
        // Check if this is a streaming message update
        if case .llm(.streamingMessageUpdated(let id, let delta, let statusMessage)) = event {
            if lastStreamingMessageId == id {
                consolidatedStreamingUpdates += 1
                consolidatedStreamingChars += delta.count
                if let lastIndex = eventHistory.lastIndex(where: {
                    if case .llm(.streamingMessageUpdated(let lastId, _, _)) = $0 {
                        return lastId == id
                    }
                    return false
                }) {
                    let consolidatedEvent = OnboardingEvent.llm(.streamingMessageUpdated(
                        id: id,
                        delta: "[\(consolidatedStreamingUpdates) updates, \(consolidatedStreamingChars) chars total]",
                        statusMessage: statusMessage
                    ))
                    eventHistory[lastIndex] = consolidatedEvent
                }
                return
            } else {
                lastStreamingMessageId = id
                consolidatedStreamingUpdates = 1
                consolidatedStreamingChars = delta.count
            }
        } else {
            lastStreamingMessageId = nil
            consolidatedStreamingUpdates = 0
            consolidatedStreamingChars = 0
        }

        eventHistory.append(event)
        if eventHistory.count > maxHistorySize {
            eventHistory.removeFirst(eventHistory.count - maxHistorySize)
        }
    }

    /// Get metrics for monitoring (debug builds only)
    func getMetrics() -> EventMetrics {
        metrics
    }

    /// Get recent event history (debug builds only)
    func getRecentEvents(count: Int = 10) -> [OnboardingEvent] {
        Array(eventHistory.suffix(count))
    }

    /// Clear event history (debug builds only)
    func clearHistory() {
        eventHistory.removeAll()
    }
    #endif
}

// MARK: - OnboardingEventEmitter Protocol

/// Protocol for components that can emit events
protocol OnboardingEventEmitter {
    var eventBus: EventCoordinator { get }
}

extension OnboardingEventEmitter {
    func emit(_ event: OnboardingEvent) async {
        await eventBus.publish(event)
    }
}

// MARK: - TimelineDiff Summary Extension

extension TimelineDiff {
    var summary: String {
        var parts: [String] = []
        if !added.isEmpty { parts.append("\(added.count) added") }
        if !removed.isEmpty { parts.append("\(removed.count) removed") }
        if !updated.isEmpty { parts.append("\(updated.count) updated") }
        if reordered { parts.append("reordered") }
        return parts.isEmpty ? "no changes" : parts.joined(separator: ", ")
    }
}
