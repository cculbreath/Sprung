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
    // MARK: - Artifact Management (§4.8 spec)
    case artifactGetRequested(id: UUID)
    case artifactNewRequested(fileURL: URL, kind: OnboardingUploadKind, performExtraction: Bool)
    case artifactAdded(id: UUID, kind: OnboardingUploadKind)
    case artifactUpdated(id: UUID, extractedText: String?)
    case artifactDeleted(id: UUID)
    // Upload completion (generic)
    case uploadCompleted(files: [ProcessedUploadInfo], requestKind: String, callId: String?, metadata: JSON)
    // Artifact pipeline (tool → state → SwiftData persistence)
    case artifactRecordProduced(record: JSON)  // emitted when a tool returns an artifact_record
    case artifactRecordsReplaced(records: [JSON]) // emitted when persisted artifact records replace in-memory state
    case artifactMetadataUpdateRequested(artifactId: String, updates: JSON) // emitted when LLM requests metadata update
    case artifactMetadataUpdated(artifact: JSON) // emitted after StateCoordinator updates metadata (includes full artifact)
    // MARK: - Knowledge Card Operations
    case knowledgeCardPersisted(card: JSON) // emitted when a knowledge card is approved and persisted
    case knowledgeCardsReplaced(cards: [JSON]) // emitted when persisted knowledge cards replace in-memory state

    // MARK: - Phase 3 Operations
    case writingSamplePersisted(sample: JSON) // emitted when a writing sample is persisted
    case candidateDossierPersisted(dossier: JSON) // emitted when final candidate dossier is persisted
    case experienceDefaultsGenerated(defaults: JSON) // emitted when LLM generates resume defaults from knowledge cards

    // MARK: - Dossier Collection (Opportunistic)
    /// Emitted when a dossier field is collected via persist_data(dataType: "candidate_dossier_entry")
    /// Used to track which fields have been collected to avoid duplicate questions
    case dossierFieldCollected(field: String)

    // MARK: - Knowledge Card Workflow (event-driven coordination)
    case knowledgeCardDoneButtonClicked(itemId: String?) // UI emits when user clicks "Done with this card"
    case knowledgeCardSubmissionPending(card: JSON) // Tool emits when card submitted for approval
    case knowledgeCardAutoPersistRequested // Request to auto-persist pending card after user confirms
    case knowledgeCardAutoPersisted(title: String) // Emitted after successful auto-persist
    case toolGatingRequested(toolName: String, exclude: Bool) // Request to gate/ungate a tool
    case planItemStatusChangeRequested(itemId: String, status: String) // Request to change plan item status

    // MARK: - Multi-Agent KC Generation Workflow
    /// UI emits when user clicks "Generate Cards" button (approves card assignments)
    /// Handler ungates dispatch_kc_agents and mandates its use via toolChoice
    case generateCardsButtonClicked
    /// Emitted after propose_card_assignments to gate dispatch until user approval
    case cardAssignmentsProposed(assignmentCount: Int, gapCount: Int)
    // MARK: - Evidence Requirements
    case evidenceRequirementAdded(EvidenceRequirement)
    case evidenceRequirementUpdated(EvidenceRequirement)
    case evidenceRequirementRemoved(String)

    // MARK: - Git Repository Analysis
    case gitRepoAnalysisStarted(repoPath: String, planItemId: String?)
    case gitRepoAnalysisCompleted(repoPath: String, artifactId: String, planItemId: String?)
    case gitRepoAnalysisFailed(repoPath: String, error: String, planItemId: String?)

    // MARK: - Git Agent Progress (multi-turn agent)
    case gitAgentTurnStarted(turn: Int, maxTurns: Int)
    case gitAgentToolExecuting(toolName: String, turn: Int)
    case gitAgentProgressUpdated(message: String, turn: Int)

    // MARK: - KC Agent Dispatch (parallel knowledge card generation)
    /// Emitted when dispatch_kc_agents is called to start parallel generation
    case kcAgentsDispatchStarted(count: Int, cardIds: [String])
    /// Emitted when all KC agents have completed (success or failure)
    case kcAgentsDispatchCompleted(successCount: Int, failureCount: Int)
    /// Emitted when a single KC agent starts processing
    case kcAgentStarted(agentId: String, cardId: String, cardTitle: String)
    /// Emitted when a single KC agent completes successfully
    case kcAgentCompleted(agentId: String, cardId: String, cardTitle: String)
    /// Emitted when a single KC agent fails
    case kcAgentFailed(agentId: String, cardId: String, error: String)
    /// Emitted when a KC agent is manually killed
    case kcAgentKilled(agentId: String, cardId: String)
    /// Emitted for KC agent turn progress (similar to git agent)
    case kcAgentTurnStarted(agentId: String, turn: Int, maxTurns: Int)
    /// Emitted when KC agent executes a tool
    case kcAgentToolExecuting(agentId: String, toolName: String, turn: Int)
    /// Emitted for general KC agent progress updates
    case kcAgentProgressUpdated(agentId: String, message: String)
    // MARK: - Timeline Operations
    case timelineCardCreated(card: JSON)
    case timelineCardUpdated(id: String, fields: JSON)
    case timelineCardDeleted(id: String, fromUI: Bool = false)
    case timelineCardsReordered(ids: [String])
    case timelineUIUpdateNeeded(timeline: JSON)  // Emitted AFTER repository update, signals UI to refresh
    // MARK: - Objective Management
    case objectiveStatusRequested(id: String, response: (String?) -> Void)
    case objectiveStatusUpdateRequested(id: String, status: String, source: String?, notes: String?, details: [String: String]?)
    case objectiveStatusChanged(id: String, oldStatus: String?, newStatus: String, phase: String, source: String?, notes: String?, details: [String: String]?)
    // MARK: - State Management (§6 spec)
    case stateSnapshot(updatedKeys: [String], snapshot: JSON)
    case stateAllowedToolsUpdated(tools: Set<String>)
    // MARK: - LLM Topics (§6 spec)
    case chatboxUserMessageAdded(messageId: String)  // Emitted when chatbox adds message to transcript immediately
    case llmUserMessageFailed(messageId: String, originalText: String, error: String)  // Emitted when user message fails (timeout, network error)
    case llmUserMessageSent(messageId: String, payload: JSON, isSystemGenerated: Bool = false)
    case llmDeveloperMessageSent(messageId: String, payload: JSON)
    case llmSentToolResponseMessage(messageId: String, payload: JSON)
    case llmSendUserMessage(payload: JSON, isSystemGenerated: Bool = false, chatboxMessageId: String? = nil, originalText: String? = nil)
    case llmSendDeveloperMessage(payload: JSON)
    case llmToolResponseMessage(payload: JSON)
    case llmStatus(status: LLMStatus)
    // Stream request events (for enqueueing via StateCoordinator)
    case llmEnqueueUserMessage(payload: JSON, isSystemGenerated: Bool, chatboxMessageId: String? = nil, originalText: String? = nil, toolChoice: String? = nil)
    case llmEnqueueToolResponse(payload: JSON)
    // Parallel tool call batching - signals how many tool responses to collect before sending
    case llmToolCallBatchStarted(expectedCount: Int, callIds: [String])
    case llmExecuteBatchedToolResponses(payloads: [JSON])
    // Stream execution events (for serial processing via StateCoordinator)
    case llmExecuteUserMessage(payload: JSON, isSystemGenerated: Bool, chatboxMessageId: String? = nil, originalText: String? = nil, bundledDeveloperMessages: [JSON] = [], toolChoice: String? = nil)
    case llmExecuteToolResponse(payload: JSON)
    case llmExecuteDeveloperMessage(payload: JSON)
    case llmStreamCompleted  // Signal that a stream finished and queue can process next item
    // Sidebar reasoning (ChatGPT-style, not attached to messages)
    case llmReasoningSummaryDelta(delta: String)  // Incremental reasoning text for sidebar
    case llmReasoningSummaryComplete(text: String)  // Final reasoning text for sidebar
    case llmReasoningItemsForToolCalls(ids: [String])  // Reasoning item IDs to pass back with tool outputs

    // Token usage tracking
    case llmTokenUsageReceived(modelId: String, inputTokens: Int, outputTokens: Int, cachedTokens: Int, reasoningTokens: Int)
    // Session persistence events
    case llmResponseIdUpdated(responseId: String?)  // previousResponseId updated after API response
    case knowledgeCardPlanUpdated(items: [KnowledgeCardPlanItem], currentFocus: String?, message: String?)  // Plan updated
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
        // Log the event
        logEvent(event)
        // Update metrics
        metrics.publishedCount[topic, default: 0] += 1
        metrics.lastPublishTime[topic] = Date()
        // Add to history with streaming event consolidation
        addToHistoryWithConsolidation(event)
        // Broadcast to ALL subscriber continuations for this topic
        if let continuations = subscriberContinuations[topic] {
            let subscriberCount = continuations.count
            // Log delivery for timelineUIUpdateNeeded to trace the issue
            if case .timelineUIUpdateNeeded = event {
                Logger.info("[EventBus] Delivering timelineUIUpdateNeeded to \(subscriberCount) subscriber(s) on topic: \(topic)", category: .ai)
            }
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
        case .chatboxUserMessageAdded, .llmUserMessageFailed, .llmUserMessageSent, .llmDeveloperMessageSent, .llmSentToolResponseMessage,
             .llmSendUserMessage, .llmSendDeveloperMessage, .llmToolResponseMessage, .llmStatus,
             .llmEnqueueUserMessage, .llmEnqueueToolResponse,
             .llmToolCallBatchStarted, .llmExecuteBatchedToolResponses,
             .llmExecuteUserMessage, .llmExecuteToolResponse, .llmExecuteDeveloperMessage, .llmStreamCompleted,
             .llmReasoningSummaryDelta, .llmReasoningSummaryComplete, .llmReasoningItemsForToolCalls, .llmCancelRequested,
             .llmResponseIdUpdated, .llmTokenUsageReceived,
             .streamingMessageBegan, .streamingMessageUpdated, .streamingMessageFinalized:
            return .llm
        // State events
        case .stateSnapshot, .stateAllowedToolsUpdated,
             .applicantProfileStored, .skeletonTimelineStored, .enabledSectionsUpdated:
            return .state
        // Phase events
        case .phaseTransitionRequested, .phaseTransitionApplied:
            return .phase
        // Objective events
        case .objectiveStatusRequested, .objectiveStatusUpdateRequested, .objectiveStatusChanged:
            return .objective
        // Tool events
        case .toolCallRequested, .toolCallCompleted, .knowledgeCardPlanUpdated:
            return .tool
        // Artifact events
        case .uploadCompleted,
             .artifactGetRequested, .artifactNewRequested, .artifactAdded, .artifactUpdated, .artifactDeleted,
             .artifactRecordProduced, .artifactRecordsReplaced,
             .artifactMetadataUpdateRequested, .artifactMetadataUpdated,
             .knowledgeCardPersisted, .knowledgeCardsReplaced,
             .knowledgeCardDoneButtonClicked, .knowledgeCardSubmissionPending,
             .knowledgeCardAutoPersistRequested, .knowledgeCardAutoPersisted,
             .toolGatingRequested, .planItemStatusChangeRequested,
             .generateCardsButtonClicked, .cardAssignmentsProposed,
             .writingSamplePersisted, .candidateDossierPersisted, .experienceDefaultsGenerated:
            return .artifact
        // Evidence Requirements (treated as state/objectives)
        case .evidenceRequirementAdded, .evidenceRequirementUpdated, .evidenceRequirementRemoved:
            return .state

        // Git Repository Analysis (treated as processing)
        case .gitRepoAnalysisStarted, .gitRepoAnalysisCompleted, .gitRepoAnalysisFailed,
             .gitAgentTurnStarted, .gitAgentToolExecuting, .gitAgentProgressUpdated:
            return .processing

        // KC Agent Dispatch (treated as processing)
        case .kcAgentsDispatchStarted, .kcAgentsDispatchCompleted,
             .kcAgentStarted, .kcAgentCompleted, .kcAgentFailed, .kcAgentKilled,
             .kcAgentTurnStarted, .kcAgentToolExecuting, .kcAgentProgressUpdated:
            return .processing
        // Toolpane events
        case .choicePromptRequested, .choicePromptCleared, .uploadRequestPresented,
             .uploadRequestCancelled, .validationPromptRequested, .validationPromptCleared,
             .applicantProfileIntakeRequested, .profileSummaryUpdateRequested, .applicantProfileIntakeCleared, .profileSummaryDismissRequested,
             .sectionToggleRequested, .sectionToggleCleared, .toolPaneCardRestored:
            return .toolpane
        // Timeline events
        case .timelineCardCreated, .timelineCardUpdated, .timelineCardDeleted, .timelineCardsReordered,
             .skeletonTimelineReplaced, .timelineUIUpdateNeeded:
            return .timeline
        // Processing events
        case .processingStateChanged, .streamingStatusUpdated, .waitingStateChanged,
             .pendingExtractionUpdated, .errorOccurred, .batchUploadStarted, .batchUploadCompleted,
             .extractionStateChanged:
            return .processing

        // Dossier events (treated as state)
        case .dossierFieldCollected:
            return .state
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
    // swiftlint:disable:next function_body_length
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
        case .batchUploadStarted(let expectedCount):
            description = "Batch upload started: expecting \(expectedCount) document(s)"
        case .batchUploadCompleted:
            description = "Batch upload completed"
        case .extractionStateChanged(let inProgress, let statusMessage):
            let statusInfo = statusMessage.map { " - \($0)" } ?? ""
            description = "Extraction: \(inProgress ? "started" : "completed")\(statusInfo)"
        case .dossierFieldCollected(let field):
            description = "Dossier field collected: \(field)"
        case .applicantProfileStored:
            description = "Profile stored"
        case .skeletonTimelineStored:
            description = "Timeline stored"
        case .enabledSectionsUpdated:
            description = "Sections updated"
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
        case .writingSamplePersisted(let sample):
            description = "Writing sample persisted: \(sample["name"].stringValue)"
        case .candidateDossierPersisted:
            description = "Candidate dossier persisted"
        case .experienceDefaultsGenerated(let defaults):
            let workCount = defaults["work"].arrayValue.count
            let skillsCount = defaults["skills"].arrayValue.count
            description = "Experience defaults generated (\(workCount) work, \(skillsCount) skills)"
        case .knowledgeCardDoneButtonClicked(let itemId):
            description = "Knowledge card done button clicked: \(itemId ?? "no item")"
        case .knowledgeCardSubmissionPending(let card):
            description = "Knowledge card submission pending: \(card["title"].stringValue)"
        case .knowledgeCardAutoPersistRequested:
            description = "Knowledge card auto-persist requested"
        case .knowledgeCardAutoPersisted(let title):
            description = "Knowledge card auto-persisted: \(title)"
        case .toolGatingRequested(let toolName, let exclude):
            description = "Tool gating requested: \(toolName) (exclude: \(exclude))"
        case .planItemStatusChangeRequested(let itemId, let status):
            description = "Plan item status change requested: \(itemId) → \(status)"
        case .generateCardsButtonClicked:
            description = "Generate cards button clicked"
        case .cardAssignmentsProposed(let assignmentCount, let gapCount):
            description = "Card assignments proposed: \(assignmentCount) assignments, \(gapCount) gaps"
        case .evidenceRequirementAdded(let req):
            description = "Evidence requirement added: \(req.description)"
        case .evidenceRequirementUpdated(let req):
            description = "Evidence requirement updated: \(req.description) (\(req.status))"
        case .evidenceRequirementRemoved(let id):
            description = "Evidence requirement removed: \(id)"
        case .gitRepoAnalysisStarted(let repoPath, let planItemId):
            let itemInfo = planItemId.map { " for item: \($0)" } ?? ""
            description = "Git repo analysis started: \(repoPath)\(itemInfo)"
        case .gitRepoAnalysisCompleted(let repoPath, let artifactId, _):
            description = "Git repo analysis completed: \(repoPath) → artifact \(artifactId)"
        case .gitRepoAnalysisFailed(let repoPath, let error, _):
            description = "Git repo analysis failed: \(repoPath) - \(error)"
        case .gitAgentTurnStarted(let turn, let maxTurns):
            description = "Git agent turn \(turn)/\(maxTurns) started"
        case .gitAgentToolExecuting(let toolName, let turn):
            description = "Git agent executing \(toolName) (turn \(turn))"
        case .gitAgentProgressUpdated(let message, let turn):
            description = "Git agent (turn \(turn)): \(message)"
        case .kcAgentsDispatchStarted(let count, _):
            description = "KC agents dispatch started (\(count) agents)"
        case .kcAgentsDispatchCompleted(let successCount, let failureCount):
            description = "KC agents dispatch completed (\(successCount) succeeded, \(failureCount) failed)"
        case .kcAgentStarted(_, let cardId, let cardTitle):
            description = "KC agent started: \(cardTitle) (\(cardId.prefix(8))...)"
        case .kcAgentCompleted(_, let cardId, let cardTitle):
            description = "KC agent completed: \(cardTitle) (\(cardId.prefix(8))...)"
        case .kcAgentFailed(_, let cardId, let error):
            description = "KC agent failed: \(cardId.prefix(8))... - \(error.prefix(50))"
        case .kcAgentKilled(_, let cardId):
            description = "KC agent killed: \(cardId.prefix(8))..."
        case .kcAgentTurnStarted(_, let turn, let maxTurns):
            description = "KC agent turn \(turn)/\(maxTurns) started"
        case .kcAgentToolExecuting(_, let toolName, let turn):
            description = "KC agent executing \(toolName) (turn \(turn))"
        case .kcAgentProgressUpdated(_, let message):
            description = "KC agent progress: \(message.prefix(50))"
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
        case .llmUserMessageFailed(let messageId, _, let error):
            description = "LLM user message failed: \(messageId.prefix(8))... - \(error.prefix(50))"
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
        case .llmExecuteUserMessage(_, let isSystemGenerated, let chatboxMessageId, _, let bundledDevMessages, let toolChoice):
            let chatboxInfo = chatboxMessageId.map { " chatbox:\($0.prefix(8))..." } ?? ""
            let bundledInfo = bundledDevMessages.isEmpty ? "" : " +\(bundledDevMessages.count) dev msgs"
            let toolInfo = toolChoice.map { " toolChoice:\($0)" } ?? ""
            description = "LLM execute user message (system: \(isSystemGenerated)\(chatboxInfo)\(bundledInfo)\(toolInfo))"
        case .llmExecuteToolResponse:
            description = "LLM execute tool response"
        case .llmExecuteDeveloperMessage:
            description = "LLM execute developer message"
        case .llmStreamCompleted:
            description = "LLM stream completed"
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
        case .profileSummaryUpdateRequested:
            description = "Profile Summary Update Requested"
        case .profileSummaryDismissRequested:
            description = "Dismiss Profile Summary Requested"
        case .toolPaneCardRestored(let card):
            description = "ToolPane card restored: \(card.rawValue)"
        case .llmResponseIdUpdated(let responseId):
            description = "LLM response ID updated: \(responseId?.prefix(12) ?? "nil")..."
        case .llmTokenUsageReceived(let modelId, let inputTokens, let outputTokens, let cachedTokens, _):
            let cachedStr = cachedTokens > 0 ? ", cached: \(cachedTokens)" : ""
            description = "Token usage: \(modelId) - in: \(inputTokens), out: \(outputTokens)\(cachedStr)"
        case .knowledgeCardPlanUpdated(let items, let focus, _):
            description = "Knowledge card plan updated: \(items.count) items, focus: \(focus ?? "none")"
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
