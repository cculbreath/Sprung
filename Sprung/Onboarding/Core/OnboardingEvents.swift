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
    case processingStateChanged(Bool)

    // MARK: - Messages
    case streamingMessageBegan(id: UUID, text: String, reasoningExpected: Bool)
    case streamingMessageUpdated(id: UUID, delta: String)
    case streamingMessageFinalized(id: UUID, finalText: String, toolCalls: [OnboardingMessage.ToolCallInfo]? = nil)

    // MARK: - Status Updates
    case streamingStatusUpdated(String?)
    case waitingStateChanged(String?)
    case pendingExtractionUpdated(OnboardingPendingExtraction?)
    case errorOccurred(String)

    // MARK: - Data Storage
    case applicantProfileStored(JSON)
    case skeletonTimelineStored(JSON)
    case enabledSectionsUpdated(Set<String>)
    case checkpointRequested

    // MARK: - Tool Execution
    case toolCallRequested(ToolCall)
    case toolCallCompleted(id: UUID, result: JSON)
    case toolContinuationNeeded(id: UUID, toolName: String)

    // MARK: - Tool UI Requests
    case choicePromptRequested(prompt: OnboardingChoicePrompt, continuationId: UUID)
    case choicePromptCleared(continuationId: UUID)
    case uploadRequestPresented(request: OnboardingUploadRequest, continuationId: UUID)
    case uploadRequestCancelled(id: UUID)
    case validationPromptRequested(prompt: OnboardingValidationPrompt, continuationId: UUID)
    case validationPromptCleared(continuationId: UUID)
    case applicantProfileIntakeRequested(continuationId: UUID)
    case applicantProfileIntakeCleared
    case profileSummaryUpdateRequested(profile: JSON)
    case profileSummaryDismissRequested
    case sectionToggleRequested(request: OnboardingSectionToggleRequest, continuationId: UUID)
    case sectionToggleCleared(continuationId: UUID)
    case phaseAdvanceRequested(request: OnboardingPhaseAdvanceRequest, continuationId: UUID)
    case phaseAdvanceDismissed

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
    case llmUserMessageSent(messageId: String, payload: JSON, isSystemGenerated: Bool = false)
    case llmDeveloperMessageSent(messageId: String, payload: JSON)
    case llmSentToolResponseMessage(messageId: String, payload: JSON)
    case llmSendUserMessage(payload: JSON, isSystemGenerated: Bool = false)
    case llmSendDeveloperMessage(payload: JSON)
    case llmToolResponseMessage(payload: JSON)
    case llmStatus(status: LLMStatus)
    // Stream request events (for enqueueing via StateCoordinator)
    case llmEnqueueUserMessage(payload: JSON, isSystemGenerated: Bool)
    case llmEnqueueDeveloperMessage(payload: JSON)
    case llmEnqueueToolResponse(payload: JSON)
    // Stream execution events (for serial processing via StateCoordinator)
    case llmExecuteUserMessage(payload: JSON, isSystemGenerated: Bool)
    case llmExecuteDeveloperMessage(payload: JSON)
    case llmExecuteToolResponse(payload: JSON)
    // Sidebar reasoning (ChatGPT-style, not attached to messages)
    case llmReasoningSummaryDelta(delta: String)  // Incremental reasoning text for sidebar
    case llmReasoningSummaryComplete(text: String)  // Final reasoning text for sidebar

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
    private let maxHistorySize = 100

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

        // Add to history
        eventHistory.append(event)
        if eventHistory.count > maxHistorySize {
            eventHistory.removeFirst(eventHistory.count - maxHistorySize)
        }

        // Broadcast to ALL subscriber continuations for this topic
        if let continuations = subscriberContinuations[topic] {
            for continuation in continuations.values {
                continuation.yield(event)
            }
        } else {
            Logger.warning("[EventBus] No subscribers for topic: \(topic)", category: .ai)
        }
    }

    /// Extract topic from event type
    private func extractTopic(from event: OnboardingEvent) -> EventTopic {
        switch event {
        // LLM events
        case .llmUserMessageSent, .llmDeveloperMessageSent, .llmSentToolResponseMessage,
             .llmSendUserMessage, .llmSendDeveloperMessage, .llmToolResponseMessage, .llmStatus,
             .llmEnqueueUserMessage, .llmEnqueueDeveloperMessage, .llmEnqueueToolResponse,
             .llmExecuteUserMessage, .llmExecuteDeveloperMessage, .llmExecuteToolResponse,
             .llmReasoningSummaryDelta, .llmReasoningSummaryComplete, .llmCancelRequested,
             .streamingMessageBegan, .streamingMessageUpdated, .streamingMessageFinalized:
            return .llm

        // State events
        case .stateSnapshot, .stateAllowedToolsUpdated,
             .applicantProfileStored, .skeletonTimelineStored, .enabledSectionsUpdated,
             .checkpointRequested:
            return .state

        // Phase events
        case .phaseTransitionRequested, .phaseTransitionApplied, .phaseAdvanceRequested, .phaseAdvanceDismissed:
            return .phase

        // Objective events
        case .objectiveStatusRequested, .objectiveStatusUpdateRequested, .objectiveStatusChanged:
            return .objective

        // Tool events
        case .toolCallRequested, .toolCallCompleted, .toolContinuationNeeded:
            return .tool

        // Artifact events
        case .uploadCompleted,
             .artifactGetRequested, .artifactNewRequested, .artifactAdded, .artifactUpdated, .artifactDeleted,
             .artifactRecordProduced, .artifactRecordPersisted, .artifactRecordsReplaced,
             .artifactMetadataUpdateRequested, .artifactMetadataUpdated,
             .knowledgeCardPersisted, .knowledgeCardsReplaced:
            return .artifact

        // Toolpane events
        case .choicePromptRequested, .choicePromptCleared, .uploadRequestPresented,
             .uploadRequestCancelled, .validationPromptRequested, .validationPromptCleared,
             .applicantProfileIntakeRequested, .applicantProfileIntakeCleared,
             .sectionToggleRequested, .sectionToggleCleared:
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
        case .processingStateChanged(let processing):
            description = "Processing: \(processing)"
        case .streamingMessageBegan:
            description = "Streaming began"
        case .streamingMessageUpdated:
            description = "Streaming update"
        case .streamingMessageFinalized:
            description = "Streaming finalized"
        case .streamingStatusUpdated(let status):
            description = "Status: \(status ?? "nil")"
        case .waitingStateChanged(let state):
            description = "Waiting: \(state ?? "nil")"
        case .pendingExtractionUpdated(let extraction):
            description = "Pending extraction: \(extraction?.title ?? "nil")"
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
        case .toolCallRequested:
            description = "Tool call requested"
        case .toolCallCompleted:
            description = "Tool call completed"
        case .toolContinuationNeeded:
            description = "Tool continuation needed"
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
        case .llmEnqueueDeveloperMessage:
            description = "LLM enqueue developer message"
        case .llmEnqueueToolResponse:
            description = "LLM enqueue tool response"
        case .llmExecuteUserMessage(_, let isSystemGenerated):
            description = "LLM execute user message (system: \(isSystemGenerated))"
        case .llmExecuteDeveloperMessage:
            description = "LLM execute developer message"
        case .llmExecuteToolResponse:
            description = "LLM execute tool response"
        case .llmStatus(let status):
            description = "LLM status: \(status.rawValue)"
        case .llmReasoningSummaryDelta(let delta):
            description = "LLM reasoning summary delta (\(delta.prefix(50))...)"
        case .llmReasoningSummaryComplete(let text):
            description = "LLM reasoning summary complete (\(text.count) chars)"
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
