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
    case streamingMessageBegan(id: UUID, text: String, reasoningExpected: Bool, statusMessage: String? = nil)
    case streamingMessageUpdated(id: UUID, delta: String, statusMessage: String? = nil)
    case streamingMessageFinalized(id: UUID, finalText: String, toolCalls: [OnboardingMessage.ToolCallInfo]? = nil, statusMessage: String? = nil)

    // MARK: - Status Updates
    case streamingStatusUpdated(String?, statusMessage: String? = nil)
    case waitingStateChanged(String?, statusMessage: String? = nil)
    case pendingExtractionUpdated(OnboardingPendingExtraction?, statusMessage: String? = nil)
    case errorOccurred(String)

    // MARK: - Data Storage
    case applicantProfileStored(JSON)
    case skeletonTimelineStored(JSON)
    case enabledSectionsUpdated(Set<String>)
    case checkpointRequested

    // MARK: - Tool Execution
    case toolCallRequested(ToolCall, statusMessage: String? = nil)
    case toolCallCompleted(id: UUID, result: JSON, statusMessage: String? = nil)

    // MARK: - Tool UI Requests
    case choicePromptRequested(prompt: OnboardingChoicePrompt)
    case choicePromptCleared
    case uploadRequestPresented(request: OnboardingUploadRequest)
    case uploadRequestCancelled(id: UUID)
    case validationPromptRequested(prompt: OnboardingValidationPrompt)
    case validationPromptCleared
    case applicantProfileIntakeRequested
    case applicantProfileIntakeCleared
    case profileSummaryUpdateRequested(profile: JSON)
    case profileSummaryDismissRequested
    case sectionToggleRequested(request: OnboardingSectionToggleRequest)
    case sectionToggleCleared
    case toolPaneCardRestored(OnboardingToolPaneCard)
    case phaseAdvanceRequested(request: OnboardingPhaseAdvanceRequest)
    case phaseAdvanceDismissed
    case phaseAdvanceApproved(request: OnboardingPhaseAdvanceRequest)
    case phaseAdvanceDenied(feedback: String?)

    // MARK: - Artifact Management (§4.8 spec)
    case artifactGetRequested(id: UUID)
    case artifactNewRequested(fileURL: URL, kind: OnboardingUploadKind, performExtraction: Bool)
    case artifactAdded(id: UUID, kind: OnboardingUploadKind)
    case artifactUpdated(id: UUID, extractedText: String?)
    case artifactDeleted(id: UUID)

    // Upload completion (generic)
    case uploadCompleted(files: [ProcessedUploadInfo], requestKind: String, callId: String?, metadata: JSON)

    // Artifact pipeline (tool → state → persistence)
    case artifactRecordProduced(record: JSON)  // emitted when a tool returns an artifact_record
    case artifactRecordPersisted(record: JSON) // emitted after persistence/index update succeeds
    case artifactRecordsReplaced(records: [JSON]) // emitted when persisted artifact records replace in-memory state
    case artifactMetadataUpdateRequested(artifactId: String, updates: JSON) // emitted when LLM requests metadata update
    case artifactMetadataUpdated(artifact: JSON) // emitted after StateCoordinator updates metadata (includes full artifact)

    // MARK: - Knowledge Card Operations
    case knowledgeCardPersisted(card: JSON) // emitted when a knowledge card is approved and persisted
    case knowledgeCardsReplaced(cards: [JSON]) // emitted when persisted knowledge cards replace in-memory state

    // MARK: - Draft Knowledge Cards
    case draftKnowledgeCardProduced(KnowledgeCardDraft)
    case draftKnowledgeCardUpdated(KnowledgeCardDraft)
    case draftKnowledgeCardRemoved(UUID)

    // MARK: - Evidence Requirements
    case evidenceRequirementAdded(EvidenceRequirement)
    case evidenceRequirementUpdated(EvidenceRequirement)
    case evidenceRequirementRemoved(String)

    // MARK: - Timeline Operations
    case timelineCardCreated(card: JSON)
    case timelineCardUpdated(id: String, fields: JSON)
    case timelineCardDeleted(id: String)
    case timelineCardsReordered(ids: [String])

    // MARK: - Objective Management
    case objectiveStatusRequested(id: String, response: (String?) -> Void)
    case objectiveStatusUpdateRequested(id: String, status: String, source: String?, notes: String?, details: [String: String]?)
    case objectiveStatusChanged(id: String, oldStatus: String?, newStatus: String, phase: String, source: String?, notes: String?, details: [String: String]?)

    // MARK: - State Management (§6 spec)
    case stateSnapshot(updatedKeys: [String], snapshot: JSON)
    case stateAllowedToolsUpdated(tools: Set<String>)

    // MARK: - LLM Topics (§6 spec)
    case chatboxUserMessageAdded(messageId: String)  // Emitted when chatbox adds message to transcript immediately
    case llmUserMessageSent(messageId: String, payload: JSON, isSystemGenerated: Bool = false)
    case llmDeveloperMessageSent(messageId: String, payload: JSON)
    case llmSentToolResponseMessage(messageId: String, payload: JSON)
    case llmSendUserMessage(payload: JSON, isSystemGenerated: Bool = false)
    case llmSendDeveloperMessage(payload: JSON)
    case llmToolResponseMessage(payload: JSON)
    case llmStatus(status: LLMStatus)
    // Stream request events (for enqueueing via StateCoordinator)
    case llmEnqueueUserMessage(payload: JSON, isSystemGenerated: Bool)
    case llmEnqueueToolResponse(payload: JSON)
    // Stream execution events (for serial processing via StateCoordinator)
    case llmExecuteUserMessage(payload: JSON, isSystemGenerated: Bool)
    case llmExecuteToolResponse(payload: JSON)
    // Sidebar reasoning (ChatGPT-style, not attached to messages)
    case llmReasoningSummaryDelta(delta: String)  // Incremental reasoning text for sidebar
    case llmReasoningSummaryComplete(text: String)  // Final reasoning text for sidebar
    case llmReasoningItemsForToolCalls(ids: [String])  // Reasoning item IDs to pass back with tool outputs

    // MARK: - Phase Management (§6 spec)
    case phaseTransitionRequested(from: String, to: String, reason: String?)
    case phaseTransitionApplied(phase: String, timestamp: Date)

    // MARK: - Phase 3: Workflow Automation & Robustness
    case llmCancelRequested
    case skeletonTimelineReplaced(timeline: JSON, diff: TimelineDiff?, meta: JSON?)
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

    // Event history for debugging
    private var eventHistory: [OnboardingEvent] = []
    private let maxHistorySize = 10000  // Large enough to capture full sessions without losing important events

    // Streaming consolidation state
    private var lastStreamingMessageId: UUID?
    private var consolidatedStreamingUpdates = 0
    private var consolidatedStreamingChars = 0

    // Metrics
    private var metrics = EventMetrics()

    struct EventMetrics {
        var publishedCount: [EventTopic: Int] = [:]
        var queueDepth: [EventTopic: Int] = [:]
        var lastPublishTime: [EventTopic: Date] = [:]
    }

    init() {
        // Initialize subscriber dictionaries for each topic
        for topic in EventTopic.allCases {
            subscriberContinuations[topic] = [:]
            metrics.publishedCount[topic] = 0
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
    func streamAll() -> AsyncStream<OnboardingEvent> {
        let subscriberId = UUID()
        let stream = AsyncStream<OnboardingEvent>(bufferingPolicy: .bufferingNewest(50)) { continuation in
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

        // Log the event
        logEvent(event)

        // Update metrics
        metrics.publishedCount[topic, default: 0] += 1
        metrics.lastPublishTime[topic] = Date()

        // Add to history with streaming event consolidation
        addToHistoryWithConsolidation(event)

        // Broadcast to ALL subscriber continuations for this topic
        if let continuations = subscriberContinuations[topic] {
            for continuation in continuations.values {
                continuation.yield(event)
            }
        } else {
            Logger.warning("[EventBus] No subscribers for topic: \(topic)", category: .ai)
        }
    }

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

        // Append event to history
        eventHistory.append(event)
        if eventHistory.count > maxHistorySize {
            eventHistory.removeFirst(eventHistory.count - maxHistorySize)
        }
    }

    /// Extract topic from event type
    private func extractTopic(from event: OnboardingEvent) -> EventTopic {
        switch event {
        // LLM events
        case .chatboxUserMessageAdded, .llmUserMessageSent, .llmDeveloperMessageSent, .llmSentToolResponseMessage,
             .llmSendUserMessage, .llmSendDeveloperMessage, .llmToolResponseMessage, .llmStatus,
             .llmEnqueueUserMessage, .llmEnqueueToolResponse,
             .llmExecuteUserMessage, .llmExecuteToolResponse,
             .llmReasoningSummaryDelta, .llmReasoningSummaryComplete, .llmReasoningItemsForToolCalls, .llmCancelRequested,
             .streamingMessageBegan, .streamingMessageUpdated, .streamingMessageFinalized:
            return .llm

        // State events
        case .stateSnapshot, .stateAllowedToolsUpdated,
             .applicantProfileStored, .skeletonTimelineStored, .enabledSectionsUpdated,
             .checkpointRequested:
            return .state

        // Phase events
        case .phaseTransitionRequested, .phaseTransitionApplied, .phaseAdvanceRequested, .phaseAdvanceDismissed,
             .phaseAdvanceApproved, .phaseAdvanceDenied:
            return .phase

        // Objective events
        case .objectiveStatusRequested, .objectiveStatusUpdateRequested, .objectiveStatusChanged:
            return .objective

        // Tool events
        case .toolCallRequested, .toolCallCompleted:
            return .tool

        // Artifact events
        case .uploadCompleted,
             .artifactGetRequested, .artifactNewRequested, .artifactAdded, .artifactUpdated, .artifactDeleted,
             .artifactRecordProduced, .artifactRecordPersisted, .artifactRecordsReplaced,
             .artifactMetadataUpdateRequested, .artifactMetadataUpdated,
             .knowledgeCardPersisted, .knowledgeCardsReplaced,
             .draftKnowledgeCardProduced, .draftKnowledgeCardUpdated, .draftKnowledgeCardRemoved:
            return .artifact

        // Evidence Requirements (treated as state/objectives)
        case .evidenceRequirementAdded, .evidenceRequirementUpdated, .evidenceRequirementRemoved:
            return .state

        // Toolpane events
        case .choicePromptRequested, .choicePromptCleared, .uploadRequestPresented,
             .uploadRequestCancelled, .validationPromptRequested, .validationPromptCleared,
             .applicantProfileIntakeRequested, .profileSummaryUpdateRequested(_), .applicantProfileIntakeCleared, .profileSummaryDismissRequested,
             .sectionToggleRequested, .sectionToggleCleared, .toolPaneCardRestored:
            return .toolpane

        // Timeline events
        case .timelineCardCreated, .timelineCardUpdated, .timelineCardDeleted, .timelineCardsReordered,
             .skeletonTimelineReplaced:
            return .timeline

        // Processing events
        case .processingStateChanged, .streamingStatusUpdated, .waitingStateChanged,
             .pendingExtractionUpdated, .errorOccurred:
            return .processing
        }
    }

    /// Get metrics for monitoring
    func getMetrics() -> EventMetrics {
        metrics
    }

    /// Get recent event history
    func getRecentEvents(count: Int = 10) -> [OnboardingEvent] {
        Array(eventHistory.suffix(count))
    }

    /// Clear event history
    func clearHistory() {
        eventHistory.removeAll()
    }

    // MARK: - Private

    private func logEvent(_ event: OnboardingEvent) {
        let description: String
        switch event {
        case .processingStateChanged(let processing, let statusMessage):
            let statusInfo = statusMessage.map { " - \($0)" } ?? ""
            description = "Processing: \(processing)\(statusInfo)"
        case .streamingMessageBegan(_, _, _, let statusMessage):
            let statusInfo = statusMessage.map { " - \($0)" } ?? ""
            description = "Streaming began\(statusInfo)"
        case .streamingMessageUpdated(_, _, let statusMessage):
            let statusInfo = statusMessage.map { " - \($0)" } ?? ""
            description = "Streaming update\(statusInfo)"
        case .streamingMessageFinalized(_, _, _, let statusMessage):
            let statusInfo = statusMessage.map { " - \($0)" } ?? ""
            description = "Streaming finalized\(statusInfo)"
        case .streamingStatusUpdated(let status, let statusMessage):
            let statusInfo = statusMessage.map { " - \($0)" } ?? ""
            description = "Status: \(status ?? "nil")\(statusInfo)"
        case .waitingStateChanged(let state, let statusMessage):
            let statusInfo = statusMessage.map { " - \($0)" } ?? ""
            description = "Waiting: \(state ?? "nil")\(statusInfo)"
        case .pendingExtractionUpdated(let extraction, let statusMessage):
            let statusInfo = statusMessage.map { " - \($0)" } ?? ""
            description = "Pending extraction: \(extraction?.title ?? "nil")\(statusInfo)"
        case .errorOccurred(let error):
            description = "Error: \(error)"
        case .applicantProfileStored:
            description = "Profile stored"
        case .skeletonTimelineStored:
            description = "Timeline stored"
        case .enabledSectionsUpdated:
            description = "Sections updated"
        case .checkpointRequested:
            description = "Checkpoint requested"
        case .toolCallRequested(_, let statusMessage):
            let statusInfo = statusMessage.map { " - \($0)" } ?? ""
            description = "Tool call requested\(statusInfo)"
        case .toolCallCompleted(_, _, let statusMessage):
            let statusInfo = statusMessage.map { " - \($0)" } ?? ""
            description = "Tool call completed\(statusInfo)"
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
        case .phaseAdvanceRequested:
            description = "Phase advance requested"
        case .phaseAdvanceDismissed:
            description = "Phase advance dismissed"
        case .phaseAdvanceApproved:
            description = "Phase advance approved"
        case .phaseAdvanceDenied:
            description = "Phase advance denied"
        case .artifactGetRequested(let id):
            description = "Artifact get requested: \(id)"
        case .artifactNewRequested:
            description = "Artifact new requested"
        case .artifactAdded(let id, _):
            description = "Artifact added: \(id)"
        case .artifactUpdated(let id, _):
            description = "Artifact updated: \(id)"
        case .artifactDeleted(let id):
            description = "Artifact deleted: \(id)"
        case .artifactRecordProduced(let record):
            description = "Artifact record produced: \(record["id"].stringValue)"
        case .artifactRecordPersisted(let record):
            description = "Artifact record persisted: \(record["id"].stringValue)"
        case .artifactRecordsReplaced(let records):
            description = "Artifact records replaced (\(records.count))"
        case .artifactMetadataUpdateRequested(let artifactId, let updates):
            description = "Artifact metadata update requested: \(artifactId) (\(updates.dictionaryValue.keys.count) fields)"
        case .artifactMetadataUpdated(let artifact):
            description = "Artifact metadata updated: \(artifact["id"].stringValue)"
        case .knowledgeCardPersisted(let card):
            description = "Knowledge card persisted: \(card["title"].stringValue)"
        case .knowledgeCardsReplaced(let cards):
            description = "Knowledge cards replaced (\(cards.count))"
        case .draftKnowledgeCardProduced(let draft):
            description = "Draft knowledge card produced: \(draft.title)"
        case .draftKnowledgeCardUpdated(let draft):
            description = "Draft knowledge card updated: \(draft.title)"
        case .draftKnowledgeCardRemoved(let id):
            description = "Draft knowledge card removed: \(id)"
        case .evidenceRequirementAdded(let req):
            description = "Evidence requirement added: \(req.description)"
        case .evidenceRequirementUpdated(let req):
            description = "Evidence requirement updated: \(req.description) (\(req.status))"
        case .evidenceRequirementRemoved(let id):
            description = "Evidence requirement removed: \(id)"
        case .timelineCardCreated:
            description = "Timeline card created"
        case .timelineCardUpdated(let id, _):
            description = "Timeline card \(id) updated"
        case .timelineCardDeleted(let id):
            description = "Timeline card \(id) deleted"
        case .timelineCardsReordered:
            description = "Timeline cards reordered"
        case .objectiveStatusRequested:
            description = "Objective status requested"
        case .objectiveStatusUpdateRequested(let id, let status, _, _, _):
            description = "Objective update requested: \(id) → \(status)"
        case .objectiveStatusChanged(let id, let oldStatus, let newStatus, _, let source, _, _):
            let sourceInfo = source.map { " (source: \($0))" } ?? ""
            let oldInfo = oldStatus.map { "\($0) → " } ?? ""
            description = "Objective \(id): \(oldInfo)\(newStatus)\(sourceInfo)"
        case .stateSnapshot(let keys, _):
            description = "State snapshot (\(keys.count) keys updated)"
        case .stateAllowedToolsUpdated(let tools):
            description = "Allowed tools updated (\(tools.count) tools)"
        case .chatboxUserMessageAdded:
            description = "Chatbox user message added"
        case .llmUserMessageSent:
            description = "LLM user message sent"
        case .llmDeveloperMessageSent:
            description = "LLM developer message sent"
        case .llmSentToolResponseMessage:
            description = "LLM tool response sent"
        case .llmSendUserMessage:
            description = "LLM send user message requested"
        case .llmSendDeveloperMessage:
            description = "LLM send developer message requested"
        case .llmToolResponseMessage:
            description = "LLM tool response requested"
        case .llmEnqueueUserMessage(_, let isSystemGenerated):
            description = "LLM enqueue user message (system: \(isSystemGenerated))"
        case .llmEnqueueToolResponse:
            description = "LLM enqueue tool response"
        case .llmExecuteUserMessage(_, let isSystemGenerated):
            description = "LLM execute user message (system: \(isSystemGenerated))"
        case .llmExecuteToolResponse:
            description = "LLM execute tool response"
        case .llmStatus(let status):
            description = "LLM status: \(status.rawValue)"
        case .llmReasoningSummaryDelta(let delta):
            description = "LLM reasoning summary delta (\(delta.prefix(50))...)"
        case .llmReasoningSummaryComplete(let text):
            description = "LLM reasoning summary complete (\(text.count) chars)"
        case .llmReasoningItemsForToolCalls(let ids):
            description = "LLM reasoning items for tool calls (\(ids.count) item(s))"
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
            case .profileSummaryUpdateRequested(profile:_):
                description = "Profile Summary Update Requested"
            case .profileSummaryDismissRequested:
                description = "Dismiss Profile Summary Requested"
            case .toolPaneCardRestored(let card):
                description = "ToolPane card restored: \(card.rawValue)"
        }

        Logger.debug("[Event] \(description)", category: .ai)
    }
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

/// Protocol for components that handle events
protocol OnboardingEventHandler {
    func handleEvent(_ event: OnboardingEvent) async
}

// Tool call structure now uses the one from ToolProtocol.swift
// Legacy compatibility
struct FunctionCall: Codable {
    let name: String
    let arguments: String
}

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

