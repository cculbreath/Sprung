import Foundation
import SwiftyJSON
/// Immutable phase policy configuration derived from PhaseScriptRegistry.
struct PhasePolicy {
    let requiredObjectives: [InterviewPhase: [String]]
    let allowedTools: [InterviewPhase: Set<String>]
}
/// Thin orchestrator for onboarding state.
/// Delegates domain logic to injected services and maintains sync caches for SwiftUI.
actor StateCoordinator: OnboardingEventEmitter {
    // MARK: - Event System
    let eventBus: EventCoordinator
    private var subscriptionTask: Task<Void, Never>?
    // MARK: - Domain Services (Injected)
    private let objectiveStore: ObjectiveStore
    private let artifactRepository: ArtifactRepository
    private let chatStore: ChatTranscriptStore
    private let uiState: SessionUIState
    private let streamQueueManager: StreamQueueManager
    private let llmStateManager: LLMStateManager
    // MARK: - Phase Policy
    private let phasePolicy: PhasePolicy
    // Runtime tool exclusions (e.g., one-time bootstrap tools)
    private var excludedTools: Set<String> = []
    // MARK: - Core Interview State
    private(set) var phase: InterviewPhase = .phase1CoreFacts
    private(set) var evidenceRequirements: [EvidenceRequirement] = []

    // MARK: - Dossier Tracking (Opportunistic Collection)
    private var dossierTracker = CandidateDossierTracker()
    // MARK: - Wizard Progress (Computed from ObjectiveStore)
    enum WizardStep: String, CaseIterable {
        case introduction
        case resumeIntake
        case artifactDiscovery
        case writingCorpus
        case wrapUp
    }
    private(set) var currentWizardStep: WizardStep = .introduction
    private(set) var completedWizardSteps: Set<WizardStep> = []
    // MARK: - Stream Queue (Delegated to StreamQueueManager)
    // StreamQueueManager handles serial LLM streaming and parallel tool call batching
    // MARK: - LLM State (Delegated to LLMStateManager)
    // LLMStateManager handles tool names, response IDs, model config, and tool pane cards
    // MARK: - State Accessors
    var pendingValidationPrompt: OnboardingValidationPrompt? {
        get async { await uiState.pendingValidationPrompt }
    }
    // MARK: - Initialization
    init(
        eventBus: EventCoordinator,
        phasePolicy: PhasePolicy,
        objectives: ObjectiveStore,
        artifacts: ArtifactRepository,
        chat: ChatTranscriptStore,
        uiState: SessionUIState
    ) {
        self.eventBus = eventBus
        self.phasePolicy = phasePolicy
        self.objectiveStore = objectives
        self.artifactRepository = artifacts
        self.chatStore = chat
        self.uiState = uiState
        self.streamQueueManager = StreamQueueManager(eventBus: eventBus)
        self.llmStateManager = LLMStateManager()
        Logger.info("🎯 StateCoordinator initialized (orchestrator mode with injected services)", category: .ai)
    }
    // MARK: - Phase Management
    private static let nextPhaseMap: [InterviewPhase: InterviewPhase?] = [
        .phase1CoreFacts: .phase2DeepDive,
        .phase2DeepDive: .phase3WritingCorpus,
        .phase3WritingCorpus: .complete,
        .complete: nil
    ]
    func setPhase(_ phase: InterviewPhase) async {
        self.phase = phase
        Logger.info("📍 Phase changed to: \(phase)", category: .ai)
        await objectiveStore.registerDefaultObjectives(for: phase)
        await uiState.setPhase(phase)
        await updateWizardProgress()
    }
    func advanceToNextPhase() async -> InterviewPhase? {
        guard await canAdvancePhase() else { return nil }
        guard let nextPhase = Self.nextPhaseMap[phase] ?? nil else {
            return nil
        }
        await setPhase(nextPhase)
        return nextPhase
    }
    func canAdvancePhase() async -> Bool {
        return await objectiveStore.canAdvancePhase(from: phase)
    }
    // MARK: - Wizard Progress (Queries ObjectiveStore)
    private func updateWizardProgress() async {
        // Phase 1 objectives
        let hasProfile = await objectiveStore.getObjectiveStatus("applicant_profile") == .completed
        let hasTimeline = await objectiveStore.getObjectiveStatus("skeleton_timeline") == .completed
        let hasSections = await objectiveStore.getObjectiveStatus("enabled_sections") == .completed
        // Phase 2 objectives (updated for evidence-based flow)
        let hasEvidenceAudit = await objectiveStore.getObjectiveStatus("evidence_audit_completed") == .completed
        let hasCardsGenerated = await objectiveStore.getObjectiveStatus("cards_generated") == .completed
        // Phase 3 objectives
        let hasWriting = await objectiveStore.getObjectiveStatus("one_writing_sample") == .completed
        let hasDossier = await objectiveStore.getObjectiveStatus("dossier_complete") == .completed
        // Start from introduction
        if currentWizardStep == .introduction {
            let allObjectives = await objectiveStore.getAllObjectives()
            if !allObjectives.isEmpty {
                currentWizardStep = .resumeIntake
            }
        }
        // Resume Intake (Phase 1)
        if hasProfile && hasTimeline && hasSections {
            completedWizardSteps.insert(.resumeIntake)
            if phase == .phase2DeepDive || phase == .phase3WritingCorpus || phase == .complete {
                currentWizardStep = .artifactDiscovery
            }
        }
        // Artifact Discovery (Phase 2) - now based on evidence audit and card generation
        if hasEvidenceAudit && hasCardsGenerated {
            completedWizardSteps.insert(.artifactDiscovery)
            if phase == .phase3WritingCorpus || phase == .complete {
                currentWizardStep = .writingCorpus
            }
        }
        // Writing Corpus (Phase 3)
        if hasWriting && hasDossier {
            completedWizardSteps.insert(.writingCorpus)
            currentWizardStep = .wrapUp
        }
        // Wrap Up
        if phase == .complete {
            completedWizardSteps.insert(.wrapUp)
        }
    }
    // MARK: - Event Subscription Setup
    func startEventSubscriptions() async {
        subscriptionTask?.cancel()
        subscriptionTask = Task { [weak self] in
            guard let self else { return }
            await withTaskGroup(of: Void.self) { group in
                // Subscribe to all relevant event topics
                group.addTask {
                    for await event in await self.eventBus.stream(topic: .state) {
                        await self.handleStateEvent(event)
                    }
                }
                group.addTask {
                    for await event in await self.eventBus.stream(topic: .llm) {
                        await self.handleLLMEvent(event)
                    }
                }
                group.addTask {
                    for await event in await self.eventBus.stream(topic: .objective) {
                        await self.handleObjectiveEvent(event)
                    }
                }
                group.addTask {
                    for await event in await self.eventBus.stream(topic: .phase) {
                        await self.handlePhaseEvent(event)
                    }
                }
                group.addTask {
                    for await event in await self.eventBus.stream(topic: .timeline) {
                        await self.handleTimelineEvent(event)
                    }
                }
                group.addTask {
                    for await event in await self.eventBus.stream(topic: .artifact) {
                        await self.handleArtifactEvent(event)
                    }
                }
                group.addTask {
                    for await event in await self.eventBus.stream(topic: .toolpane) {
                        await self.handleToolpaneEvent(event)
                    }
                }
                group.addTask {
                    for await event in await self.eventBus.stream(topic: .processing) {
                        await self.handleProcessingEvent(event)
                    }
                }
            }
        }
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        Logger.info("📡 StateCoordinator subscribed to event streams", category: .ai)
    }
    // MARK: - Event Handlers (Delegate to Services)
    private func handleStateEvent(_ event: OnboardingEvent) async {
        switch event {
        case .applicantProfileStored:
            Logger.info("👤 Applicant profile stored via event", category: .ai)
        case .skeletonTimelineStored:
            Logger.info("📅 Skeleton timeline stored via event", category: .ai)
        case .enabledSectionsUpdated:
            Logger.info("📑 Enabled sections updated via event", category: .ai)
        case .stateAllowedToolsUpdated(let tools):
            await llmStateManager.setAllowedToolNames(tools)
        case .evidenceRequirementAdded(let req):
            evidenceRequirements.append(req)
            Logger.info("📋 Evidence requirement added: \(req.description)", category: .ai)
        case .evidenceRequirementUpdated(let req):
            if let index = evidenceRequirements.firstIndex(where: { $0.id == req.id }) {
                evidenceRequirements[index] = req
                Logger.info("📋 Evidence requirement updated: \(req.description)", category: .ai)
            }
        case .evidenceRequirementRemoved(let id):
            evidenceRequirements.removeAll { $0.id == id }
            Logger.info("📋 Evidence requirement removed: \(id)", category: .ai)
        case .dossierFieldCollected(let field):
            dossierTracker.recordFieldCollected(field)
            Logger.info("📋 Dossier field collected: \(field)", category: .ai)
        default:
            break
        }
    }
    private func handleProcessingEvent(_ event: OnboardingEvent) async {
        switch event {
        case .processingStateChanged(let processing, _):
            // Delegate to SessionUIState
            await uiState.setProcessingState(processing, emitEvent: false)
        case .waitingStateChanged(let waiting, _):
            // SessionUIState handles this internally, just log
            Logger.debug("Waiting state changed: \(waiting ?? "nil")", category: .ai)
        case .pendingExtractionUpdated(let extraction, _):
            await uiState.setPendingExtraction(extraction)
        case .streamingStatusUpdated(let status, _):
            await uiState.setStreamingStatus(status)
        case .errorOccurred(let error):
            // On stream errors, handle pending tool responses or revert to clean state
            if error.hasPrefix("Stream error:") {
                // Check if there are pending tool responses that need retry (with retry counting)
                if let pendingPayloads = await llmStateManager.getPendingToolResponsesForRetry() {
                    // Retry pending tool responses instead of reverting
                    Logger.warning("🔄 Stream error recovery: retrying \(pendingPayloads.count) pending tool response(s)", category: .ai)
                    // Use exponential backoff delay before retry
                    try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 second delay
                    if pendingPayloads.count == 1 {
                        await eventBus.publish(.llmExecuteToolResponse(payload: pendingPayloads[0]))
                    } else {
                        await eventBus.publish(.llmExecuteBatchedToolResponses(payloads: pendingPayloads))
                    }
                } else if let cleanId = await llmStateManager.getLastCleanResponseId() {
                    // No pending tool responses (or max retries exceeded) - revert to clean state
                    await llmStateManager.setLastResponseId(cleanId)
                    Logger.warning("🔄 Stream error recovery: reverted to last clean response ID (\(cleanId.prefix(8)))", category: .ai)
                } else {
                    Logger.warning("🔄 Stream error recovery: no clean response ID available, conversation may be stuck", category: .ai)
                }
            }
        default:
            break
        }
    }
    private func handleLLMEvent(_ event: OnboardingEvent) async {
        switch event {
        case .llmUserMessageSent(_, let payload, let isSystemGenerated):
            if isSystemGenerated {
                let text = payload["text"].stringValue
                _ = await chatStore.appendUserMessage(text, isSystemGenerated: isSystemGenerated)
                Logger.debug("StateCoordinator: system-generated user message appended", category: .ai)
            }
        case .llmSentToolResponseMessage:
            break
        case .llmStatus(let status):
            let newProcessingState = status == .busy
            await uiState.setProcessingState(newProcessingState)
        case .streamingMessageBegan(let id, let text, let reasoningExpected, _):
            _ = await chatStore.beginStreamingMessage(id: id, initialText: text, reasoningExpected: reasoningExpected)
        case .streamingMessageUpdated(let id, let delta, _):
            await chatStore.updateStreamingMessage(id: id, delta: delta)
        case .streamingMessageFinalized(let id, let finalText, let toolCalls, _):
            await chatStore.finalizeStreamingMessage(id: id, finalText: finalText, toolCalls: toolCalls)
        case .llmReasoningSummaryDelta(let delta):
            await chatStore.updateReasoningSummary(delta: delta)
        case .llmReasoningSummaryComplete(let text):
            await chatStore.completeReasoningSummary(finalText: text)
        case .llmEnqueueUserMessage(let payload, let isSystemGenerated, let chatboxMessageId, let originalText, let toolChoice):
            // Bundle any queued developer messages WITH the user message
            // They'll be included as input items in the same API request
            let bundledDevMessages = await llmStateManager.drainQueuedDeveloperMessages()
            if !bundledDevMessages.isEmpty {
                Logger.info("📦 Bundling \(bundledDevMessages.count) developer message(s) with user message", category: .ai)
            }
            await streamQueueManager.enqueue(.userMessage(
                payload: payload,
                isSystemGenerated: isSystemGenerated,
                chatboxMessageId: chatboxMessageId,
                originalText: originalText,
                bundledDeveloperMessages: bundledDevMessages,
                toolChoice: toolChoice
            ))
        case .llmSendDeveloperMessage(let payload):
            // Codex paradigm: Always queue developer messages until user action
            // Developer messages are batched and flushed when:
            // 1. User sends a chatbox message
            // 2. An artifact completion arrives (sent as user message)
            // 3. A pending UI tool call is completed
            await llmStateManager.queueDeveloperMessage(payload)
            Logger.debug("📥 Developer message queued (awaiting user action)", category: .ai)
        case .llmToolCallBatchStarted(let expectedCount, let callIds):
            await streamQueueManager.startToolCallBatch(expectedCount: expectedCount, callIds: callIds)
        case .llmEnqueueToolResponse(let payload):
            await streamQueueManager.enqueueToolResponse(payload)
        case .llmStreamCompleted:
            // Handle stream completion via event to ensure proper ordering with tool call events
            await streamQueueManager.handleStreamCompleted()
        default:
            break
        }
    }
    private func handleObjectiveEvent(_ event: OnboardingEvent) async {
        switch event {
        case .objectiveStatusRequested(let id, let response):
            let status = await objectiveStore.getObjectiveStatus(id)
            response(status?.rawValue)
        case .objectiveStatusUpdateRequested(let id, let statusString, let source, let notes, let details):
            guard let status = ObjectiveStatus(rawValue: statusString) else {
                Logger.warning("Invalid objective status: \(statusString)", category: .ai)
                return
            }
            await objectiveStore.setObjectiveStatus(id, status: status, source: source, notes: notes, details: details)
        case .objectiveStatusChanged(let id, _, let newStatus, _, _, _, _):
            // Update wizard progress
            await updateWizardProgress()
            // Clear any queued developer messages for this objective when it completes
            if newStatus == "completed" {
                await llmStateManager.clearQueuedMessagesForObjective(id)
            }
        default:
            break
        }
    }
    private func handlePhaseEvent(_ event: OnboardingEvent) async {
        switch event {
        case .phaseTransitionRequested(let from, let to, _):
            if from == phase.rawValue {
                if let newPhase = InterviewPhase(rawValue: to) {
                    await setPhase(newPhase)
                    await emit(.phaseTransitionApplied(phase: newPhase.rawValue, timestamp: Date()))
                }
            }
        default:
            break
        }
    }
    private func handleTimelineEvent(_ event: OnboardingEvent) async {
        switch event {
        case .timelineCardCreated(let card):
            Logger.info("📊 StateCoordinator: Received timelineCardCreated", category: .ai)
            await artifactRepository.createTimelineCard(card)
            Logger.info("📊 StateCoordinator: Timeline sync updated. Cards count: \(artifactRepository.skeletonTimelineSync?["experiences"].array?.count ?? 0)", category: .ai)
            // Emit UI update event AFTER repository is updated
            if let timeline = await artifactRepository.getSkeletonTimeline() {
                await emit(.timelineUIUpdateNeeded(timeline: timeline))
                Logger.info("📊 StateCoordinator: Emitted timelineUIUpdateNeeded after card create", category: .ai)
            }
        case .timelineCardUpdated(let id, let fields):
            Logger.info("📊 StateCoordinator: Received timelineCardUpdated for id=\(id)", category: .ai)
            await artifactRepository.updateTimelineCard(id: id, fields: fields)
            // Emit UI update event AFTER repository is updated
            if let timeline = await artifactRepository.getSkeletonTimeline() {
                await emit(.timelineUIUpdateNeeded(timeline: timeline))
                Logger.info("📊 StateCoordinator: Emitted timelineUIUpdateNeeded after card \(id) update", category: .ai)
            } else {
                Logger.warning("📊 StateCoordinator: No timeline found after card \(id) update - UI update skipped", category: .ai)
            }
        case .timelineCardDeleted(let id, let fromUI):
            Logger.info("📊 StateCoordinator: Received timelineCardDeleted for id=\(id), fromUI=\(fromUI)", category: .ai)
            await artifactRepository.deleteTimelineCard(id: id)
            // Only emit UI update for non-UI deletions (UI-initiated already has the update)
            if !fromUI, let timeline = await artifactRepository.getSkeletonTimeline() {
                await emit(.timelineUIUpdateNeeded(timeline: timeline))
                Logger.info("📊 StateCoordinator: Emitted timelineUIUpdateNeeded after card \(id) delete", category: .ai)
            }
        case .timelineCardsReordered(let orderedIds):
            Logger.info("📊 StateCoordinator: Received timelineCardsReordered", category: .ai)
            await artifactRepository.reorderTimelineCards(orderedIds: orderedIds)
            // Emit UI update event AFTER repository is updated
            if let timeline = await artifactRepository.getSkeletonTimeline() {
                await emit(.timelineUIUpdateNeeded(timeline: timeline))
                Logger.info("📊 StateCoordinator: Emitted timelineUIUpdateNeeded after reorder", category: .ai)
            }
        case .skeletonTimelineReplaced(let timeline, let diff, _):
            Logger.info("📊 StateCoordinator: Received skeletonTimelineReplaced", category: .ai)
            await artifactRepository.replaceSkeletonTimeline(timeline, diff: diff)
            // Emit UI update event AFTER repository is updated
            if let updatedTimeline = await artifactRepository.getSkeletonTimeline() {
                await emit(.timelineUIUpdateNeeded(timeline: updatedTimeline))
                Logger.info("📊 StateCoordinator: Emitted timelineUIUpdateNeeded after timeline replace", category: .ai)
            }
        case .timelineUIUpdateNeeded:
            // Don't handle our own event to avoid loops
            break
        default:
            break
        }
    }
    private func handleArtifactEvent(_ event: OnboardingEvent) async {
        switch event {
        case .artifactRecordProduced(let record):
            await artifactRepository.upsertArtifactRecord(record)
        case .artifactRecordsReplaced(let records):
            await artifactRepository.setArtifactRecords(records)
        case .artifactMetadataUpdateRequested(let artifactId, let updates):
            await artifactRepository.updateArtifactMetadata(artifactId: artifactId, updates: updates)
        case .knowledgeCardPersisted(let card):
            await artifactRepository.addKnowledgeCard(card)
        case .knowledgeCardsReplaced(let cards):
            await artifactRepository.setKnowledgeCards(cards)
        case .toolGatingRequested(let toolName, let exclude):
            // Handle tool gating via events
            if exclude {
                await excludeTool(toolName)
            } else {
                await includeTool(toolName)
            }
        default:
            break
        }
    }
    private func handleToolpaneEvent(_ event: OnboardingEvent) async {
        switch event {
        case .choicePromptRequested(let prompt):
            await uiState.setPendingChoice(prompt)
            await llmStateManager.setToolPaneCard(.choicePrompt)
        case .choicePromptCleared:
            await uiState.setPendingChoice(nil)
            await llmStateManager.setToolPaneCard(.none)
        case .uploadRequestPresented(let request):
            await uiState.setPendingUpload(request)
            await llmStateManager.setToolPaneCard(.uploadRequest)
        case .uploadRequestCancelled:
            await uiState.setPendingUpload(nil)
            await llmStateManager.setToolPaneCard(.none)
        case .validationPromptRequested(let prompt):
            await uiState.setPendingValidation(prompt)
            await llmStateManager.setToolPaneCard(prompt.mode == .editor ? .editTimelineCards : .confirmTimelineCards)
        case .validationPromptCleared:
            await uiState.setPendingValidation(nil)
            await llmStateManager.setToolPaneCard(.none)
        case .applicantProfileIntakeRequested:
            await llmStateManager.setToolPaneCard(.applicantProfileRequest)
        case .applicantProfileIntakeCleared:
            await llmStateManager.setToolPaneCard(.none)
        case .sectionToggleRequested:
            await llmStateManager.setToolPaneCard(.sectionToggle)
        case .sectionToggleCleared:
            await llmStateManager.setToolPaneCard(.none)
        default:
            break
        }
    }
    // MARK: - Stream Queue Management (Delegated to StreamQueueManager)
    /// Mark stream as completed - emits event to ensure proper ordering with pending tool calls
    /// This method should be called by LLMMessenger when a stream finishes
    func markStreamCompleted() async {
        await streamQueueManager.markStreamCompleted()
    }
    /// Check if this is the first response (for toolChoice logic)
    func getHasStreamedFirstResponse() async -> Bool {
        await streamQueueManager.getHasStreamedFirstResponse()
    }

    /// Restore streaming state when resuming a session
    /// Call this after restoring messages to mark that conversation is in progress
    func restoreStreamingState(hasMessages: Bool) async {
        if hasMessages {
            await streamQueueManager.restoreState(hasStreamedFirstResponse: true)
            Logger.info("✅ Restored hasStreamedFirstResponse=true (session has messages)", category: .ai)
        }
    }
    // MARK: - LLM State Accessors (Delegated to LLMStateManager)
    /// Get allowed tool names
    func getAllowedToolNames() async -> Set<String> {
        await llmStateManager.getAllowedToolNames()
    }
    /// Update conversation state (called by LLMMessenger when response completes)
    /// - Parameters:
    ///   - responseId: The response ID from the completed response
    ///   - hadToolCalls: Whether this response included tool calls (affects checkpoint safety)
    func updateConversationState(responseId: String, hadToolCalls: Bool = false) async {
        await llmStateManager.updateConversationState(responseId: responseId, hadToolCalls: hadToolCalls)
    }
    /// Get last response ID
    func getLastResponseId() async -> String? {
        await llmStateManager.getLastResponseId()
    }
    /// Set model ID
    func setModelId(_ modelId: String) async {
        await llmStateManager.setModelId(modelId)
    }
    /// Get current model ID
    func getCurrentModelId() async -> String {
        await llmStateManager.getCurrentModelId()
    }
    /// Get whether flex processing is enabled
    func getUseFlexProcessing() async -> Bool {
        await llmStateManager.getUseFlexProcessing()
    }
    /// Set whether to use flex processing tier (50% cost savings, variable latency)
    func setUseFlexProcessing(_ enabled: Bool) async {
        await llmStateManager.setUseFlexProcessing(enabled)
    }
    /// Get the default reasoning effort level
    func getDefaultReasoningEffort() async -> String {
        await llmStateManager.getDefaultReasoningEffort()
    }
    /// Set the default reasoning effort level (none, minimal, low, medium, high)
    func setDefaultReasoningEffort(_ effort: String) async {
        await llmStateManager.setDefaultReasoningEffort(effort)
    }
    // MARK: - Pending Tool Response Tracking
    /// Store pending tool response payload(s) before sending (for retry on stream error)
    func setPendingToolResponses(_ payloads: [JSON]) async {
        await llmStateManager.setPendingToolResponses(payloads)
    }
    /// Get pending tool response payloads for retry
    func getPendingToolResponses() async -> [JSON] {
        await llmStateManager.getPendingToolResponses()
    }
    /// Check if there are pending tool responses
    func hasPendingToolResponses() async -> Bool {
        await llmStateManager.hasPendingToolResponses()
    }
    /// Clear pending tool responses (call after successful acknowledgment)
    func clearPendingToolResponses() async {
        await llmStateManager.clearPendingToolResponses()
    }
    /// Get pending tool responses for retry, with retry counting
    /// Returns nil if max retries exceeded (caller should revert to clean state)
    func getPendingToolResponsesForRetry() async -> [JSON]? {
        await llmStateManager.getPendingToolResponsesForRetry()
    }

    // MARK: - Pending UI Tool Call (Codex Paradigm)
    // UI tools present cards and await user action before responding.
    // When a UI tool is pending, developer messages are queued behind it.

    /// Set a UI tool as pending (awaiting user action)
    func setPendingUIToolCall(callId: String, toolName: String) async {
        await llmStateManager.setPendingUIToolCall(callId: callId, toolName: toolName)
    }

    /// Check if there's a pending UI tool awaiting user action
    func hasPendingUIToolCall() async -> Bool {
        await llmStateManager.hasPendingUIToolCall()
    }

    /// Get the pending UI tool call info
    func getPendingUIToolCall() async -> (callId: String, toolName: String)? {
        await llmStateManager.getPendingUIToolCall()
    }

    /// Clear the pending UI tool call (after user action sends tool output)
    func clearPendingUIToolCall() async {
        await llmStateManager.clearPendingUIToolCall()
    }

    /// Queue a developer message while a UI tool is pending
    func queueDeveloperMessage(_ payload: JSON) async {
        await llmStateManager.queueDeveloperMessage(payload)
    }

    /// Drain queued developer messages (call after UI tool output is sent)
    func drainQueuedDeveloperMessages() async -> [JSON] {
        await llmStateManager.drainQueuedDeveloperMessages()
    }

    /// Check if there are queued developer messages
    func hasQueuedDeveloperMessages() async -> Bool {
        await llmStateManager.hasQueuedDeveloperMessages()
    }

    // MARK: - Snapshot Management
    struct StateSnapshot: Codable {
        let phase: InterviewPhase
        let objectives: [String: ObjectiveStore.ObjectiveEntry]
        let wizardStep: String
        let completedWizardSteps: Set<String>
        // Conversation state for resume (clean response ID = no pending tool calls)
        let lastCleanResponseId: String?
        let currentModelId: String
        let messages: [OnboardingMessage]
        let hasStreamedFirstResponse: Bool
        // ToolPane UI state for resume
        let currentToolPaneCard: OnboardingToolPaneCard
        let evidenceRequirements: [EvidenceRequirement]
    }
    func createSnapshot() async -> StateSnapshot {
        let allObjectives = await objectiveStore.getAllObjectives()
        let objectivesDict = Dictionary(uniqueKeysWithValues: allObjectives.map { ($0.id, $0) })
        // Get conversation state
        let currentMessages = await chatStore.getAllMessages()
        let hasStreamedFirst = await streamQueueManager.getHasStreamedFirstResponse()
        let llmSnapshot = await llmStateManager.createSnapshot()
        return StateSnapshot(
            phase: phase,
            objectives: objectivesDict,
            wizardStep: currentWizardStep.rawValue,
            completedWizardSteps: Set(completedWizardSteps.map { $0.rawValue }),
            lastCleanResponseId: llmSnapshot.lastCleanResponseId,  // Use clean ID for safe restore
            currentModelId: llmSnapshot.currentModelId,
            messages: currentMessages,
            hasStreamedFirstResponse: hasStreamedFirst,
            currentToolPaneCard: llmSnapshot.currentToolPaneCard,
            evidenceRequirements: evidenceRequirements
        )
    }
    func restoreFromSnapshot(_ snapshot: StateSnapshot) async {
        phase = snapshot.phase
        await objectiveStore.restore(objectives: snapshot.objectives)
        if let step = WizardStep(rawValue: snapshot.wizardStep) {
            currentWizardStep = step
        }
        completedWizardSteps = Set(snapshot.completedWizardSteps.compactMap { WizardStep(rawValue: $0) })
        // Restore conversation state using clean response ID
        if let cleanResponseId = snapshot.lastCleanResponseId {
            await chatStore.setPreviousResponseId(cleanResponseId)
            Logger.info("📝 Restoring from clean response ID: \(cleanResponseId.prefix(8))...", category: .ai)
        }
        // Restore LLM state via LLMStateManager
        let llmSnapshot = LLMStateManager.Snapshot(
            lastCleanResponseId: snapshot.lastCleanResponseId,
            currentModelId: snapshot.currentModelId,
            currentToolPaneCard: snapshot.currentToolPaneCard
        )
        await llmStateManager.restoreFromSnapshot(llmSnapshot)
        await chatStore.restoreMessages(snapshot.messages)
        Logger.info("💬 Restored \(snapshot.messages.count) chat messages", category: .ai)
        // Restore streaming state via StreamQueueManager
        await streamQueueManager.restoreState(hasStreamedFirstResponse: snapshot.hasStreamedFirstResponse)
        // Restore evidence requirements
        evidenceRequirements = snapshot.evidenceRequirements
        Logger.info("📥 State restored from snapshot with conversation history", category: .ai)
    }
    /// Backfill objective statuses when migrating from legacy snapshots
    private func backfillObjectiveStatuses(snapshot: StateSnapshot) async {
        let restoredObjectives = snapshot.objectives
        // contact_source_selected: completed if applicant_profile was completed
        if let applicantProfile = restoredObjectives["applicant_profile"],
           applicantProfile.status == .completed {
            await objectiveStore.setObjectiveStatus(
                "contact_source_selected",
                status: .completed,
                source: "migration",
                notes: "Backfilled based on applicant_profile completion"
            )
        }
        // contact_data_collected: completed if applicant_profile.contact_intake.persisted was completed
        if let contactPersisted = restoredObjectives["applicant_profile.contact_intake.persisted"],
           contactPersisted.status == .completed {
            await objectiveStore.setObjectiveStatus(
                "contact_data_collected",
                status: .completed,
                source: "migration",
                notes: "Backfilled based on contact_intake.persisted completion"
            )
        }
        // contact_data_validated: completed if applicant_profile.contact_intake.persisted was completed
        if let contactPersisted = restoredObjectives["applicant_profile.contact_intake.persisted"],
           contactPersisted.status == .completed {
            await objectiveStore.setObjectiveStatus(
                "contact_data_validated",
                status: .completed,
                source: "migration",
                notes: "Backfilled based on contact_intake.persisted completion"
            )
        }
        Logger.info("✅ Objective status backfill completed", category: .ai)
    }
    private func emitSnapshot(reason: String) async {
        let snapshot = await createSnapshot()
        var snapshotJSON = JSON()
        snapshotJSON["phase"].string = snapshot.phase.rawValue
        snapshotJSON["wizardStep"].string = snapshot.wizardStep
        let updatedKeys = ["phase", "wizardStep", "objectives"]
        await emit(.stateSnapshot(updatedKeys: updatedKeys, snapshot: snapshotJSON))
    }
    // MARK: - Reset
    func reset() async {
        phase = .phase1CoreFacts
        currentWizardStep = .introduction
        completedWizardSteps.removeAll()
        // Reset all services
        await objectiveStore.reset()
        await artifactRepository.reset()
        await chatStore.reset()
        await uiState.reset()
        await streamQueueManager.reset()
        await llmStateManager.reset()
        Logger.info("🔄 StateCoordinator reset (all services reset)", category: .ai)
    }
    // MARK: - ToolPane Card Tracking (Delegated to LLMStateManager)
    func setToolPaneCard(_ card: OnboardingToolPaneCard) async {
        await llmStateManager.setToolPaneCard(card)
    }
    func getCurrentToolPaneCard() async -> OnboardingToolPaneCard {
        await llmStateManager.getCurrentToolPaneCard()
    }
    // MARK: - Delegation Methods (Convenience APIs)
    // Objective delegation
    func getObjectiveStatus(_ id: String) async -> ObjectiveStatus? {
        await objectiveStore.getObjectiveStatus(id)
    }
    func getAllObjectives() async -> [ObjectiveStore.ObjectiveEntry] {
        await objectiveStore.getAllObjectives()
    }
    func getMissingObjectives() async -> [String] {
        await objectiveStore.getMissingObjectives(for: phase)
    }
    func getObjectivesForPhase(_ phase: InterviewPhase) async -> [ObjectiveStore.ObjectiveEntry] {
        await objectiveStore.getObjectivesForPhase(phase)
    }
    /// Get all objectives as a dictionary mapping ID to status string (for subphase inference)
    func getObjectiveStatusMap() async -> [String: String] {
        let objectives = await objectiveStore.getAllObjectives()
        return Dictionary(uniqueKeysWithValues: objectives.map { ($0.id, $0.status.rawValue) })
    }
    /// Restore an objective status from persisted session
    func restoreObjectiveStatus(objectiveId: String, status: String) async {
        guard let objectiveStatus = ObjectiveStatus(rawValue: status) else {
            Logger.warning("⚠️ Invalid objective status to restore: \(status)", category: .ai)
            return
        }
        await objectiveStore.setObjectiveStatus(objectiveId, status: objectiveStatus, source: "session_restore")
    }

    /// Restore an artifact from persisted session
    func restoreArtifact(_ artifact: JSON) async {
        await artifactRepository.addArtifactRecord(artifact)
    }

    /// Restore multiple artifacts from persisted session
    func restoreArtifacts(_ artifacts: [JSON]) async {
        await artifactRepository.setArtifactRecords(artifacts)
    }

    /// Restore skeleton timeline from persisted session
    func restoreSkeletonTimeline(_ timeline: JSON) async {
        await artifactRepository.setSkeletonTimeline(timeline)
    }

    /// Restore applicant profile from persisted session
    func restoreApplicantProfile(_ profile: JSON) async {
        await artifactRepository.setApplicantProfile(profile)
    }

    /// Restore enabled sections from persisted session
    func restoreEnabledSections(_ sections: Set<String>) async {
        await artifactRepository.setEnabledSections(sections)
    }
    // Artifact delegation
    func getArtifactRecord(id: String) async -> JSON? {
        await artifactRepository.getArtifactRecord(id: id)
    }
    func getArtifactsForPhaseObjective(_ objectiveId: String) async -> [JSON] {
        await artifactRepository.getArtifactsForPhaseObjective(objectiveId)
    }

    /// Delete an artifact record by ID (returns the deleted artifact for notification purposes)
    func deleteArtifactRecord(id: String) async -> JSON? {
        await artifactRepository.deleteArtifactRecord(id: id)
    }

    /// Store applicant profile in artifact repository
    func storeApplicantProfile(_ profile: JSON) async {
        await artifactRepository.setApplicantProfile(profile)
    }
    /// Store skeleton timeline in artifact repository
    func storeSkeletonTimeline(_ timeline: JSON) async {
        await artifactRepository.setSkeletonTimeline(timeline)
    }
    /// Store enabled sections in artifact repository
    func storeEnabledSections(_ sections: Set<String>) async {
        await artifactRepository.setEnabledSections(sections)
    }
    var artifacts: OnboardingArtifacts {
        get async {
            // Reconstruct artifacts struct from repository
            OnboardingArtifacts(
                applicantProfile: await artifactRepository.getApplicantProfile(),
                skeletonTimeline: await artifactRepository.getSkeletonTimeline(),
                enabledSections: await artifactRepository.getEnabledSections(),
                experienceCards: await artifactRepository.getExperienceCards(),
                writingSamples: await artifactRepository.getWritingSamples(),
                artifactRecords: await artifactRepository.getArtifacts().artifactRecords,
                knowledgeCards: await artifactRepository.getKnowledgeCards(),
                cardProposals: await artifactRepository.getCardProposals()
            )
        }
    }

    /// Store card proposals from propose_card_assignments tool
    func storeCardProposals(_ proposals: JSON) async {
        await artifactRepository.setCardProposals(proposals)
    }

    /// Get card proposals for dispatch_kc_agents
    func getCardProposals() async -> JSON {
        await artifactRepository.getCardProposals()
    }

    // MARK: - Pending Knowledge Cards (Milestone 7)

    /// Store a generated card for later submission (keeps content out of main thread)
    func storePendingCard(_ card: JSON, id: String) async {
        await artifactRepository.storePendingCard(card, id: id)
    }

    /// Retrieve a pending card by ID
    func getPendingCard(id: String) async -> JSON? {
        await artifactRepository.getPendingCard(id: id)
    }

    /// Remove a pending card after submission
    func removePendingCard(id: String) async {
        await artifactRepository.removePendingCard(id: id)
    }

    func listArtifactSummaries() async -> [JSON] {
        await artifactRepository.listArtifactSummaries()
    }

    /// Get enabled sections configured by user in Phase 1
    func getEnabledSections() async -> Set<String> {
        await artifactRepository.getEnabledSections()
    }

    /// Direct access to artifact records for UI sync
    var artifactRecords: [JSON] {
        get async {
            await artifactRepository.getArtifacts().artifactRecords
        }
    }

    // Chat delegation
    var messages: [OnboardingMessage] {
        get async {
            await chatStore.getAllMessages()
        }
    }
    var latestReasoningSummary: String? {
        get async {
            await chatStore.getLatestReasoningSummary()
        }
    }
    func appendUserMessage(_ text: String, isSystemGenerated: Bool = false) async -> UUID {
        let id = await chatStore.appendUserMessage(text, isSystemGenerated: isSystemGenerated)
        return id
    }

    /// Remove a message by ID (used when message send fails)
    func removeMessage(id: UUID) async -> OnboardingMessage? {
        await chatStore.removeMessage(id: id)
    }
    func appendAssistantMessage(_ text: String) async -> UUID {
        await chatStore.appendAssistantMessage(text)
    }
    func beginStreamingMessage(initialText: String, reasoningExpected: Bool) async -> UUID {
        await chatStore.beginStreamingMessage(initialText: initialText, reasoningExpected: reasoningExpected)
    }
    func updateStreamingMessage(id: UUID, delta: String) async {
        await chatStore.updateStreamingMessage(id: id, delta: delta)
    }
    func finalizeStreamingMessage(id: UUID, finalText: String, toolCalls: [OnboardingMessage.ToolCallInfo]? = nil) async {
        await chatStore.finalizeStreamingMessage(id: id, finalText: finalText, toolCalls: toolCalls)
    }
    func getPreviousResponseId() async -> String? {
        await chatStore.getPreviousResponseId()
    }
    func setPreviousResponseId(_ responseId: String?) async {
        await chatStore.setPreviousResponseId(responseId)
    }
    // UI State delegation
    func setActiveState(_ active: Bool) async {
        await uiState.setActiveState(active)
        Logger.info("🎛️ Interview active state set to: \(active) (chatbox \(active ? "enabled" : "disabled"))", category: .ai)
    }
    func publishAllowedToolsNow() async {
        await uiState.publishToolPermissionsNow()
    }
    var waitingState: SessionUIState.WaitingState? {
        get async {
            await uiState.getWaitingState()
        }
    }
    func getAllowedToolsForCurrentPhase() -> Set<String> {
        let phaseTools = phasePolicy.allowedTools[phase] ?? []
        return phaseTools.subtracting(excludedTools)
    }
    /// Remove a tool from the allowed tools list (e.g., after one-time use)
    func excludeTool(_ toolName: String) async {
        excludedTools.insert(toolName)
        Logger.info("🚫 Tool excluded from future calls: \(toolName)", category: .ai)
        // Update SessionUIState's excluded tools (this also republishes permissions)
        await uiState.excludeTool(toolName)
    }

    // MARK: - Dossier Tracking API

    /// Get the next dossier field to collect for the current phase
    func getNextDossierField() -> CandidateDossierField? {
        dossierTracker.getNextField(for: phase)
    }

    /// Build a prompt for the LLM to ask a dossier question
    func buildDossierPrompt() -> String? {
        dossierTracker.buildDossierPrompt(for: phase)
    }

    /// Check if a dossier field has been collected
    func hasDossierFieldCollected(_ field: CandidateDossierField) -> Bool {
        dossierTracker.hasCollected(field)
    }

    /// Re-include a previously excluded tool (e.g., when user action enables it)
    func includeTool(_ toolName: String) async {
        excludedTools.remove(toolName)
        Logger.info("✅ Tool re-included in allowed calls: \(toolName)", category: .ai)
        // Update SessionUIState's excluded tools (this also republishes permissions)
        await uiState.includeTool(toolName)
    }
    var isProcessing: Bool {
        get async {
            await uiState.isProcessing
        }
    }
    var isActive: Bool {
        get async {
            await uiState.isActive
        }
    }
    var pendingExtraction: OnboardingPendingExtraction? {
        get async {
            await uiState.pendingExtraction
        }
    }
    var pendingStreamingStatus: String? {
        get async {
            nil
        }
    }
}
