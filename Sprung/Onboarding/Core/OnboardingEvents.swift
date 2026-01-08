//
//  OnboardingEvents.swift
//  Sprung
//
//  Event-driven architecture for the onboarding system.
//  Replaces the 13+ callback struct with clean, unidirectional events.
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
/// All events that can occur during the onboarding interview
enum OnboardingEvent {
    // MARK: - Processing State
    case processingStateChanged(Bool, statusMessage: String? = nil)
    // MARK: - Messages
    case streamingMessageBegan(id: UUID, text: String, statusMessage: String? = nil)
    case streamingMessageUpdated(id: UUID, delta: String, statusMessage: String? = nil)
    case streamingMessageFinalized(id: UUID, finalText: String, toolCalls: [OnboardingMessage.ToolCallInfo]? = nil, statusMessage: String? = nil)
    // MARK: - Status Updates
    case waitingStateChanged(String?, statusMessage: String? = nil)
    case pendingExtractionUpdated(OnboardingPendingExtraction?, statusMessage: String? = nil)
    case errorOccurred(String)
    // MARK: - Batch Upload State
    case batchUploadStarted(expectedCount: Int) // emitted when batch document upload begins
    case batchUploadCompleted // emitted when batch document upload finishes

    // MARK: - Extraction State (Non-Blocking)
    /// Extraction in progress (PDF processing, git analysis) - does NOT block chat input
    /// Unlike processingStateChanged, this allows dossier questions during extraction "dead time"
    case extractionStateChanged(Bool, statusMessage: String? = nil)
    // MARK: - Data Storage
    case applicantProfileStored(JSON)
    case skeletonTimelineStored(JSON)
    case enabledSectionsUpdated(Set<String>)
    case documentCollectionActiveChanged(Bool)
    case timelineEditorActiveChanged(Bool)
    // MARK: - Tool Execution
    case toolCallRequested(ToolCall, statusMessage: String? = nil)
    // MARK: - Tool UI Requests
    case choicePromptRequested(prompt: OnboardingChoicePrompt)
    case choicePromptCleared
    case uploadRequestPresented(request: OnboardingUploadRequest)
    case uploadRequestCancelled(id: UUID)
    case validationPromptRequested(prompt: OnboardingValidationPrompt)
    case validationPromptCleared
    case applicantProfileIntakeRequested
    case applicantProfileIntakeCleared
    case sectionToggleRequested(request: OnboardingSectionToggleRequest)
    case sectionToggleCleared
    // Upload completion (generic)
    case uploadCompleted(files: [ProcessedUploadInfo], requestKind: String, callId: String?, metadata: JSON)
    // Artifact pipeline (tool → state → SwiftData persistence)
    case artifactRecordProduced(record: JSON)  // emitted when a tool returns an artifact_record
    case artifactMetadataUpdateRequested(artifactId: String, updates: JSON) // emitted when LLM requests metadata update
    case artifactMetadataUpdated(artifact: JSON) // emitted after StateCoordinator updates metadata (includes full artifact)
    // MARK: - Knowledge Card Operations
    case knowledgeCardPersisted(card: JSON) // emitted when a knowledge card is approved and persisted

    // MARK: - Phase 3 Operations
    case writingSamplePersisted(sample: JSON) // emitted when a writing sample is persisted
    case candidateDossierPersisted(dossier: JSON) // emitted when final candidate dossier is persisted
    case experienceDefaultsGenerated(defaults: JSON) // emitted when LLM generates resume defaults from knowledge cards

    // MARK: - Voice Primer Operations
    case voicePrimerExtractionStarted(sampleCount: Int) // emitted when voice primer extraction begins
    case voicePrimerExtractionCompleted(primer: JSON) // emitted when voice primer extraction succeeds
    case voicePrimerExtractionFailed(error: String) // emitted when voice primer extraction fails

    // MARK: - Card Generation Workflow
    /// UI emits when user clicks "Done with Uploads" button to trigger merge
    case doneWithUploadsClicked
    /// UI emits when user clicks "Approve & Create" button (approves card assignments)
    case generateCardsButtonClicked
    /// Emitted when card inventory merge completes
    case mergeComplete(cardCount: Int, gapCount: Int)
    /// Emitted when todo list is updated (for persistence)
    case todoListUpdated(todoListJSON: String)

    // MARK: - Git Agent Progress (multi-turn agent)
    case gitAgentTurnStarted(turn: Int, maxTurns: Int)
    case gitAgentToolExecuting(toolName: String, turn: Int)
    case gitAgentProgressUpdated(message: String, turn: Int)

    // MARK: - Timeline Operations
    case timelineCardCreated(card: JSON)
    case timelineCardUpdated(id: String, fields: JSON)
    case timelineCardDeleted(id: String, fromUI: Bool = false)
    case timelineCardsReordered(ids: [String])
    case timelineUIUpdateNeeded(timeline: JSON)  // Emitted AFTER repository update, signals UI to refresh
    // MARK: - Objective Management
    case objectiveStatusUpdateRequested(id: String, status: String, source: String?, notes: String?, details: [String: String]?)
    case objectiveStatusChanged(id: String, oldStatus: String?, newStatus: String, phase: String, source: String?, notes: String?, details: [String: String]?)
    // MARK: - State Management (§6 spec)
    case stateAllowedToolsUpdated(tools: Set<String>)
    // MARK: - LLM Topics (§6 spec)
    case chatboxUserMessageAdded(messageId: String)  // Emitted when chatbox adds message to transcript immediately
    case llmUserMessageFailed(messageId: String, originalText: String, error: String)  // Emitted when user message fails (timeout, network error)
    case llmUserMessageSent(messageId: String, payload: JSON, isSystemGenerated: Bool = false)
    case llmCoordinatorMessageSent(messageId: String, payload: JSON)
    case llmSentToolResponseMessage(messageId: String, payload: JSON)
    case llmSendUserMessage(payload: JSON, isSystemGenerated: Bool = false, chatboxMessageId: String? = nil, originalText: String? = nil, toolChoice: String? = nil)
    case llmSendCoordinatorMessage(payload: JSON)
    case llmToolResponseMessage(payload: JSON)
    case llmStatus(status: LLMStatus)
    // Stream request events (for enqueueing via StateCoordinator)
    case llmEnqueueUserMessage(payload: JSON, isSystemGenerated: Bool, chatboxMessageId: String? = nil, originalText: String? = nil, toolChoice: String? = nil)
    case llmEnqueueToolResponse(payload: JSON)
    // Parallel tool call batching - signals how many tool responses to collect before sending
    case llmToolCallBatchStarted(expectedCount: Int, callIds: [String])
    case llmExecuteBatchedToolResponses(payloads: [JSON])
    // Stream execution events (for serial processing via StateCoordinator)
    case llmExecuteUserMessage(payload: JSON, isSystemGenerated: Bool, chatboxMessageId: String? = nil, originalText: String? = nil, bundledCoordinatorMessages: [JSON] = [], toolChoice: String? = nil)
    case llmExecuteToolResponse(payload: JSON)
    case llmExecuteCoordinatorMessage(payload: JSON)
    case llmStreamCompleted  // Signal that a stream finished and queue can process next item
    // Token usage tracking
    case llmTokenUsageReceived(modelId: String, inputTokens: Int, outputTokens: Int, cachedTokens: Int, reasoningTokens: Int, source: UsageSource)
    // MARK: - Conversation Log Events
    case conversationEntryAppended(entry: ConversationEntry)  // New entry added to conversation log
    case toolResultFilled(callId: String, status: String)  // Tool result slot filled in last entry
    // MARK: - Phase Management (§6 spec)
    case phaseTransitionRequested(from: String, to: String, reason: String?)
    case phaseTransitionApplied(phase: String, timestamp: Date)
    // MARK: - Phase 3: Workflow Automation & Robustness
    case llmCancelRequested
    case skeletonTimelineReplaced(timeline: JSON, diff: TimelineDiff?, meta: JSON?)

    /// Concise log description that avoids logging full JSON payloads
    var logDescription: String {
        switch self {
        // Events with large payloads - show just the event name or key info
        case .llmSendUserMessage(_, let isSystemGenerated, _, _, _):
            return "llmSendUserMessage(isSystemGenerated: \(isSystemGenerated))"
        case .llmEnqueueUserMessage(_, let isSystemGenerated, _, _, _):
            return "llmEnqueueUserMessage(isSystemGenerated: \(isSystemGenerated))"
        case .llmExecuteUserMessage(_, let isSystemGenerated, _, _, _, _):
            return "llmExecuteUserMessage(isSystemGenerated: \(isSystemGenerated))"
        case .llmToolResponseMessage:
            return "llmToolResponseMessage"
        case .llmEnqueueToolResponse:
            return "llmEnqueueToolResponse"
        case .llmExecuteToolResponse:
            return "llmExecuteToolResponse"
        case .llmSendCoordinatorMessage:
            return "llmSendCoordinatorMessage"
        case .llmExecuteCoordinatorMessage:
            return "llmExecuteCoordinatorMessage"
        case .llmSentToolResponseMessage(let messageId, _):
            return "llmSentToolResponseMessage(messageId: \(messageId.prefix(8))...)"
        case .llmUserMessageSent(let messageId, _, let isSystemGenerated):
            return "llmUserMessageSent(messageId: \(messageId.prefix(8))..., isSystemGenerated: \(isSystemGenerated))"
        case .llmCoordinatorMessageSent(let messageId, _):
            return "llmCoordinatorMessageSent(messageId: \(messageId.prefix(8))...)"
        case .llmExecuteBatchedToolResponses(let payloads):
            return "llmExecuteBatchedToolResponses(count: \(payloads.count))"
        case .streamingMessageFinalized(let id, let finalText, let toolCalls, _):
            let textPreview = finalText.prefix(50).replacingOccurrences(of: "\n", with: " ")
            return "streamingMessageFinalized(id: \(id), text: \"\(textPreview)...\", toolCalls: \(toolCalls?.count ?? 0))"
        case .streamingMessageUpdated(let id, _, _):
            return "streamingMessageUpdated(id: \(id))"
        case .toolCallRequested(let toolCall, _):
            return "toolCallRequested(name: \(toolCall.name))"
        case .artifactRecordProduced:
            return "artifactRecordProduced"
        case .artifactMetadataUpdateRequested(let artifactId, _):
            return "artifactMetadataUpdateRequested(artifactId: \(artifactId.prefix(8))...)"
        case .artifactMetadataUpdated:
            return "artifactMetadataUpdated"
        case .knowledgeCardPersisted:
            return "knowledgeCardPersisted"
        case .skeletonTimelineReplaced:
            return "skeletonTimelineReplaced"
        case .applicantProfileStored:
            return "applicantProfileStored"
        case .skeletonTimelineStored:
            return "skeletonTimelineStored"
        case .experienceDefaultsGenerated:
            return "experienceDefaultsGenerated"
        case .uploadCompleted(let files, let requestKind, _, _):
            return "uploadCompleted(files: \(files.count), kind: \(requestKind))"
        case .timelineCardCreated:
            return "timelineCardCreated"
        case .timelineCardUpdated(let id, _):
            return "timelineCardUpdated(id: \(id.prefix(8))...)"
        case .timelineUIUpdateNeeded:
            return "timelineUIUpdateNeeded"
        case .writingSamplePersisted:
            return "writingSamplePersisted"
        case .candidateDossierPersisted:
            return "candidateDossierPersisted"
        case .conversationEntryAppended(let entry):
            return "conversationEntryAppended(\(entry.isUser ? "user" : "assistant"), id: \(entry.id))"
        case .toolResultFilled(let callId, let status):
            return "toolResultFilled(callId: \(callId.prefix(8))..., status: \(status))"
        // Events with minimal payloads - use default description
        default:
            return String(describing: self)
        }
    }
}
enum LLMStatus: String {
    case busy
    case idle
    case error
}
/// Event topics for routing (spec §6)
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
/// Event bus that manages event distribution using AsyncStream
actor EventCoordinator {
    // Broadcast continuations: each topic has multiple subscriber continuations
    private var subscriberContinuations: [EventTopic: [UUID: AsyncStream<OnboardingEvent>.Continuation]] = [:]
    #if DEBUG
    // Event history for debugging (debug builds only)
    private var eventHistory: [OnboardingEvent] = []
    private let maxHistorySize = 1000  // Reduced from 10,000 to limit memory usage
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
    /// Each subscriber gets their own stream that receives ALL events for the topic
    func stream(topic: EventTopic) -> AsyncStream<OnboardingEvent> {
        let subscriberId = UUID()
        let stream = AsyncStream<OnboardingEvent>(bufferingPolicy: .bufferingNewest(50)) { continuation in
            Task { [weak self] in
                // Register this continuation for the topic
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
    /// Uses unbounded buffer to ensure critical events are never dropped
    /// during high-traffic periods (e.g., LLM streaming generates hundreds of delta events)
    func streamAll() -> AsyncStream<OnboardingEvent> {
        let subscriberId = UUID()
        let stream = AsyncStream<OnboardingEvent>(bufferingPolicy: .unbounded) { continuation in
            Task { [weak self] in
                // Register this continuation for ALL topics
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
        let topic = extractTopic(from: event)
        #if DEBUG
        // Log the event (debug builds only)
        logEvent(event)
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
            // Log delivery for timelineUIUpdateNeeded to trace the issue
            if case .timelineUIUpdateNeeded = event {
                Logger.info("[EventBus] Delivering timelineUIUpdateNeeded to \(subscriberCount) subscriber(s) on topic: \(topic)", category: .ai)
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
        if case .streamingMessageUpdated(let id, let delta, let statusMessage) = event {
            // Same message as previous streaming update?
            if lastStreamingMessageId == id {
                // Consolidate: increment counter and accumulate chars
                consolidatedStreamingUpdates += 1
                consolidatedStreamingChars += delta.count
                // Replace the last event with updated consolidation
                if let lastIndex = eventHistory.lastIndex(where: {
                    if case .streamingMessageUpdated(let lastId, _, _) = $0 {
                        return lastId == id
                    }
                    return false
                }) {
                    // Create consolidated event showing total updates and chars
                    let consolidatedEvent = OnboardingEvent.streamingMessageUpdated(
                        id: id,
                        delta: "[\(consolidatedStreamingUpdates) updates, \(consolidatedStreamingChars) chars total]",
                        statusMessage: statusMessage
                    )
                    eventHistory[lastIndex] = consolidatedEvent
                }
                return
            } else {
                // Different message - flush previous consolidation state and start new
                lastStreamingMessageId = id
                consolidatedStreamingUpdates = 1
                consolidatedStreamingChars = delta.count
                // Fall through to append this first update
            }
        } else {
            // Not a streaming update - reset consolidation state
            lastStreamingMessageId = nil
            consolidatedStreamingUpdates = 0
            consolidatedStreamingChars = 0
        }
        eventHistory.append(event)
        if eventHistory.count > maxHistorySize {
            eventHistory.removeFirst(eventHistory.count - maxHistorySize)
        }
    }
    #endif

    /// Extract topic from event type
    private func extractTopic(from event: OnboardingEvent) -> EventTopic {
        switch event {
        // LLM events
        case .chatboxUserMessageAdded, .llmUserMessageFailed, .llmUserMessageSent, .llmCoordinatorMessageSent, .llmSentToolResponseMessage,
             .llmSendUserMessage, .llmSendCoordinatorMessage, .llmToolResponseMessage, .llmStatus,
             .llmEnqueueUserMessage, .llmEnqueueToolResponse,
             .llmToolCallBatchStarted, .llmExecuteBatchedToolResponses,
             .llmExecuteUserMessage, .llmExecuteToolResponse, .llmExecuteCoordinatorMessage, .llmStreamCompleted,
             .llmCancelRequested, .llmTokenUsageReceived,
             .streamingMessageBegan, .streamingMessageUpdated, .streamingMessageFinalized,
             .conversationEntryAppended, .toolResultFilled:
            return .llm
        // State events
        case .stateAllowedToolsUpdated,
             .applicantProfileStored, .skeletonTimelineStored, .enabledSectionsUpdated,
             .documentCollectionActiveChanged, .timelineEditorActiveChanged:
            return .state
        // Phase events
        case .phaseTransitionRequested, .phaseTransitionApplied:
            return .phase
        // Objective events
        case .objectiveStatusUpdateRequested, .objectiveStatusChanged:
            return .objective
        // Tool events
        case .toolCallRequested, .todoListUpdated:
            return .tool
        // Artifact events
        case .uploadCompleted,
             .artifactRecordProduced,
             .artifactMetadataUpdateRequested, .artifactMetadataUpdated,
             .knowledgeCardPersisted,
             .doneWithUploadsClicked, .generateCardsButtonClicked, .mergeComplete,
             .writingSamplePersisted, .candidateDossierPersisted, .experienceDefaultsGenerated,
             .voicePrimerExtractionStarted, .voicePrimerExtractionCompleted, .voicePrimerExtractionFailed:
            return .artifact
        // Git Agent Progress (treated as processing)
        case .gitAgentTurnStarted, .gitAgentToolExecuting, .gitAgentProgressUpdated:
            return .processing
        // Toolpane events
        case .choicePromptRequested, .choicePromptCleared, .uploadRequestPresented,
             .uploadRequestCancelled, .validationPromptRequested, .validationPromptCleared,
             .applicantProfileIntakeRequested, .applicantProfileIntakeCleared,
             .sectionToggleRequested, .sectionToggleCleared:
            return .toolpane
        // Timeline events
        case .timelineCardCreated, .timelineCardUpdated, .timelineCardDeleted, .timelineCardsReordered,
             .skeletonTimelineReplaced, .timelineUIUpdateNeeded:
            return .timeline
        // Processing events
        case .processingStateChanged, .waitingStateChanged,
             .pendingExtractionUpdated, .errorOccurred, .batchUploadStarted, .batchUploadCompleted,
             .extractionStateChanged:
            return .processing
        }
    }
    #if DEBUG
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
    // MARK: - Private
    #if DEBUG
    // swiftlint:disable:next function_body_length
    private func logEvent(_ event: OnboardingEvent) {
        let description: String
        switch event {
        case .processingStateChanged(let processing, let statusMessage):
            let statusInfo = statusMessage.map { " - \($0)" } ?? ""
            description = "Processing: \(processing)\(statusInfo)"
        case .streamingMessageBegan(_, _, let statusMessage):
            let statusInfo = statusMessage.map { " - \($0)" } ?? ""
            description = "Streaming began\(statusInfo)"
        case .streamingMessageUpdated(_, _, let statusMessage):
            let statusInfo = statusMessage.map { " - \($0)" } ?? ""
            description = "Streaming update\(statusInfo)"
        case .streamingMessageFinalized(_, _, _, let statusMessage):
            let statusInfo = statusMessage.map { " - \($0)" } ?? ""
            description = "Streaming finalized\(statusInfo)"
        case .waitingStateChanged(let state, let statusMessage):
            let statusInfo = statusMessage.map { " - \($0)" } ?? ""
            description = "Waiting: \(state ?? "nil")\(statusInfo)"
        case .pendingExtractionUpdated(let extraction, let statusMessage):
            let statusInfo = statusMessage.map { " - \($0)" } ?? ""
            description = "Pending extraction: \(extraction?.title ?? "nil")\(statusInfo)"
        case .errorOccurred(let error):
            description = "Error: \(error)"
        case .batchUploadStarted(let expectedCount):
            description = "Batch upload started: expecting \(expectedCount) document(s)"
        case .batchUploadCompleted:
            description = "Batch upload completed"
        case .extractionStateChanged(let inProgress, let statusMessage):
            let statusInfo = statusMessage.map { " - \($0)" } ?? ""
            description = "Extraction: \(inProgress ? "started" : "completed")\(statusInfo)"
        case .applicantProfileStored:
            description = "Profile stored"
        case .skeletonTimelineStored:
            description = "Timeline stored"
        case .enabledSectionsUpdated:
            description = "Sections updated"
        case .documentCollectionActiveChanged(let isActive):
            description = "Document collection \(isActive ? "activated" : "deactivated")"
        case .timelineEditorActiveChanged(let isActive):
            description = "Timeline editor \(isActive ? "activated" : "deactivated")"
        case .toolCallRequested(_, let statusMessage):
            let statusInfo = statusMessage.map { " - \($0)" } ?? ""
            description = "Tool call requested\(statusInfo)"
        case .choicePromptRequested:
            description = "Choice prompt requested"
        case .choicePromptCleared:
            description = "Choice prompt cleared"
        case .uploadRequestPresented:
            description = "Upload request presented"
        case .uploadRequestCancelled:
            description = "Upload request cancelled"
        case .validationPromptRequested:
            description = "Validation prompt requested"
        case .validationPromptCleared:
            description = "Validation prompt cleared"
        case .applicantProfileIntakeRequested:
            description = "Profile intake requested"
        case .applicantProfileIntakeCleared:
            description = "Profile intake cleared"
        case .sectionToggleRequested:
            description = "Section toggle requested"
        case .sectionToggleCleared:
            description = "Section toggle cleared"
        case .artifactRecordProduced(let record):
            description = "Artifact record produced: \(record["id"].stringValue)"
        case .artifactMetadataUpdateRequested(let artifactId, let updates):
            description = "Artifact metadata update requested: \(artifactId) (\(updates.dictionaryValue.keys.count) fields)"
        case .artifactMetadataUpdated(let artifact):
            description = "Artifact metadata updated: \(artifact["id"].stringValue)"
        case .knowledgeCardPersisted(let card):
            description = "Knowledge card persisted: \(card["title"].stringValue)"
        case .writingSamplePersisted(let sample):
            description = "Writing sample persisted: \(sample["name"].stringValue)"
        case .candidateDossierPersisted:
            description = "Candidate dossier persisted"
        case .experienceDefaultsGenerated(let defaults):
            let workCount = defaults["work"].arrayValue.count
            let skillsCount = defaults["skills"].arrayValue.count
            description = "Experience defaults generated (\(workCount) work, \(skillsCount) skills)"
        case .voicePrimerExtractionStarted(let sampleCount):
            description = "Voice primer extraction started from \(sampleCount) sample(s)"
        case .voicePrimerExtractionCompleted:
            description = "Voice primer extraction completed"
        case .voicePrimerExtractionFailed(let error):
            description = "Voice primer extraction failed: \(error)"
        case .doneWithUploadsClicked:
            description = "Done with uploads clicked - triggering merge"
        case .generateCardsButtonClicked:
            description = "Generate cards button clicked"
        case .mergeComplete(let cardCount, let gapCount):
            description = "Merge complete: \(cardCount) cards, \(gapCount) gaps"
        case .gitAgentTurnStarted(let turn, let maxTurns):
            description = "Git agent turn \(turn)/\(maxTurns) started"
        case .gitAgentToolExecuting(let toolName, let turn):
            description = "Git agent executing \(toolName) (turn \(turn))"
        case .gitAgentProgressUpdated(let message, let turn):
            description = "Git agent (turn \(turn)): \(message)"
        case .timelineCardCreated:
            description = "Timeline card created"
        case .timelineCardUpdated(let id, _):
            description = "Timeline card \(id) updated"
        case .timelineCardDeleted(let id, let fromUI):
            description = "Timeline card \(id) deleted\(fromUI ? " (from UI)" : "")"
        case .timelineCardsReordered:
            description = "Timeline cards reordered"
        case .timelineUIUpdateNeeded:
            description = "Timeline UI update needed"
        case .objectiveStatusUpdateRequested(let id, let status, _, _, _):
            description = "Objective update requested: \(id) → \(status)"
        case .objectiveStatusChanged(let id, let oldStatus, let newStatus, _, let source, _, _):
            let sourceInfo = source.map { " (source: \($0))" } ?? ""
            let oldInfo = oldStatus.map { "\($0) → " } ?? ""
            description = "Objective \(id): \(oldInfo)\(newStatus)\(sourceInfo)"
        case .stateAllowedToolsUpdated(let tools):
            description = "Allowed tools updated (\(tools.count) tools)"
        case .chatboxUserMessageAdded:
            description = "Chatbox user message added"
        case .llmUserMessageFailed(let messageId, _, let error):
            description = "LLM user message failed: \(messageId.prefix(8))... - \(error.prefix(50))"
        case .llmUserMessageSent:
            description = "LLM user message sent"
        case .llmCoordinatorMessageSent:
            description = "LLM coordinator message sent"
        case .llmSentToolResponseMessage:
            description = "LLM tool response sent"
        case .llmSendUserMessage:
            description = "LLM send user message requested"
        case .llmSendCoordinatorMessage:
            description = "LLM send coordinator message requested"
        case .llmToolResponseMessage:
            description = "LLM tool response requested"
        case .llmEnqueueUserMessage(_, let isSystemGenerated, let chatboxMessageId, _, let toolChoice):
            let chatboxInfo = chatboxMessageId.map { " chatbox:\($0.prefix(8))..." } ?? ""
            let toolInfo = toolChoice.map { " toolChoice:\($0)" } ?? ""
            description = "LLM enqueue user message (system: \(isSystemGenerated)\(chatboxInfo)\(toolInfo))"
        case .llmEnqueueToolResponse:
            description = "LLM enqueue tool response"
        case .llmToolCallBatchStarted(let expectedCount, _):
            description = "LLM tool call batch started (expecting \(expectedCount) responses)"
        case .llmExecuteBatchedToolResponses(let payloads):
            description = "LLM execute batched tool responses (\(payloads.count) responses)"
        case .llmExecuteUserMessage(_, let isSystemGenerated, let chatboxMessageId, _, let bundledCoordMsgs, let toolChoice):
            let chatboxInfo = chatboxMessageId.map { " chatbox:\($0.prefix(8))..." } ?? ""
            let bundledInfo = bundledCoordMsgs.isEmpty ? "" : " +\(bundledCoordMsgs.count) coord msgs"
            let toolInfo = toolChoice.map { " toolChoice:\($0)" } ?? ""
            description = "LLM execute user message (system: \(isSystemGenerated)\(chatboxInfo)\(bundledInfo)\(toolInfo))"
        case .llmExecuteToolResponse:
            description = "LLM execute tool response"
        case .llmExecuteCoordinatorMessage:
            description = "LLM execute coordinator message"
        case .llmStreamCompleted:
            description = "LLM stream completed"
        case .llmStatus(let status):
            description = "LLM status: \(status.rawValue)"
        case .phaseTransitionRequested(let from, let to, _):
            description = "Phase transition requested: \(from) → \(to)"
        case .phaseTransitionApplied(let phase, _):
            description = "Phase transition applied: \(phase)"
        case .llmCancelRequested:
            description = "LLM cancel requested"
        case .skeletonTimelineReplaced(_, let diff, _):
            if let diff = diff {
                description = "Skeleton timeline replaced (\(diff.summary))"
            } else {
                description = "Skeleton timeline replaced"
            }
        case .uploadCompleted(let files, let requestKind, _, _):
            description = "Upload completed: \(files.count) file(s), kind: \(requestKind)"
        case .conversationEntryAppended(let entry):
            description = "Conversation entry appended: \(entry.isUser ? "user" : "assistant") (\(entry.id))"
        case .toolResultFilled(let callId, let status):
            description = "Tool result filled: \(callId.prefix(8))... (\(status))"
        case .llmTokenUsageReceived(let modelId, let inputTokens, let outputTokens, let cachedTokens, _, let source):
            let cachedStr = cachedTokens > 0 ? ", cached: \(cachedTokens)" : ""
            description = "Token usage [\(source.displayName)]: \(modelId) - in: \(inputTokens), out: \(outputTokens)\(cachedStr)"
        case .todoListUpdated(let todoListJSON):
            description = "Todo list updated: \(todoListJSON.count) chars"
        }
        Logger.debug("[Event] \(description)", category: .ai)
    }
    #endif
}
/// Protocol for components that can emit events
protocol OnboardingEventEmitter {
    var eventBus: EventCoordinator { get }
}
/// Extension to make event emission convenient
extension OnboardingEventEmitter {
    func emit(_ event: OnboardingEvent) async {
        await eventBus.publish(event)
    }
}
// Tool call structure now uses the one from ToolProtocol.swift
// MARK: - TimelineDiff Summary Extension
/// Extension to provide a summary string for the detailed TimelineDiff type
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
