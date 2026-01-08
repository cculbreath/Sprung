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
    private let streamingBuffer: StreamingMessageBuffer
    private let uiState: SessionUIState
    private let streamQueueManager: StreamQueueManager
    private let llmStateManager: LLMStateManager
    private let todoStore: InterviewTodoStore
    private let phaseRegistry: PhaseScriptRegistry

    // MARK: - New Architecture (ConversationLog)
    private let conversationLog: ConversationLog
    private let operationTracker: OperationTracker
    // MARK: - Phase Policy
    private let phasePolicy: PhasePolicy
    // Runtime tool exclusions (e.g., one-time bootstrap tools)
    private var excludedTools: Set<String> = []
    // MARK: - Core Interview State
    private(set) var phase: InterviewPhase = .phase1VoiceContext
    private(set) var evidenceRequirements: [EvidenceRequirement] = []

    // MARK: - Dossier Tracking (Opportunistic Collection)
    private var dossierTracker = CandidateDossierTracker()

    // MARK: - Dossier WIP Notes (Scratchpad for LLM)
    /// Free-form notes the LLM can update during the interview.
    /// Included in working memory so LLM can reference prior notes.
    /// Persisted with snapshot so notes survive session resume.
    private(set) var dossierNotes: String = ""

    // MARK: - User Approval Flags
    /// Set to true when user explicitly approves skipping KC generation.
    /// Only set via user UI interaction (submit_for_validation approval), never by LLM.
    /// Checked by phase 2→3 validation. Reset when entering new phase.
    private(set) var userApprovedKCSkip: Bool = false

    // MARK: - Wizard Progress (Computed from ObjectiveStore)
    /// Wizard steps that correspond to the 4-phase interview structure
    enum WizardStep: String, CaseIterable {
        case voice      // Phase 1: Voice & Context
        case story      // Phase 2: Career Story
        case evidence   // Phase 3: Evidence Collection
        case strategy   // Phase 4: Strategic Synthesis
    }
    private(set) var currentWizardStep: WizardStep = .voice
    private(set) var completedWizardSteps: Set<WizardStep> = []

    // MARK: - Tool Response Batching
    // Collects tool response payloads until all ConversationLog slots are filled
    private var collectedToolResponsePayloads: [JSON] = []

    // MARK: - Stream Queue (Delegated to StreamQueueManager)
    // StreamQueueManager handles serial LLM streaming (simplified - no tool tracking)
    // MARK: - LLM State (Delegated to LLMStateManager)
    // LLMStateManager handles tool names, response IDs, model config, and tool pane cards
    // MARK: - Initialization
    init(
        eventBus: EventCoordinator,
        phasePolicy: PhasePolicy,
        phaseRegistry: PhaseScriptRegistry,
        objectives: ObjectiveStore,
        artifacts: ArtifactRepository,
        streamingBuffer: StreamingMessageBuffer,
        uiState: SessionUIState,
        todoStore: InterviewTodoStore,
        operationTracker: OperationTracker,
        conversationLog: ConversationLog
    ) {
        self.eventBus = eventBus
        self.phasePolicy = phasePolicy
        self.phaseRegistry = phaseRegistry
        self.objectiveStore = objectives
        self.artifactRepository = artifacts
        self.streamingBuffer = streamingBuffer
        self.uiState = uiState
        self.todoStore = todoStore
        self.streamQueueManager = StreamQueueManager(eventBus: eventBus)
        self.llmStateManager = LLMStateManager()

        // New architecture: ConversationLog with OperationTracker (injected)
        self.operationTracker = operationTracker
        self.conversationLog = conversationLog

        Logger.info("🎯 StateCoordinator initialized (orchestrator mode with injected services)", category: .ai)
    }
    // MARK: - Phase Management
    func setPhase(_ phase: InterviewPhase) async {
        self.phase = phase
        // Reset user approval flags when entering new phase
        userApprovedKCSkip = false
        Logger.info("📍 Phase changed to: \(phase)", category: .ai)
        await objectiveStore.registerDefaultObjectives(for: phase)
        await uiState.setPhase(phase)
        await updateWizardProgress()
    }

    /// Restore phase during session resume - registers objectives for ALL phases up to and including the target.
    /// This ensures objectives from earlier phases (like skeleton_timeline_complete from Phase 2)
    /// are registered and can have their status restored when resuming a Phase 3+ session.
    func restorePhase(_ phase: InterviewPhase) async {
        self.phase = phase
        // Don't reset approval flags - they should be restored from session
        Logger.info("📍 Restoring phase to: \(phase)", category: .ai)

        // Register objectives for ALL phases up to and including the target phase
        // This ensures earlier phase objectives exist for status restoration
        let allPhases: [InterviewPhase] = [.phase1VoiceContext, .phase2CareerStory, .phase3EvidenceCollection, .phase4StrategicSynthesis]
        for p in allPhases {
            await objectiveStore.registerDefaultObjectives(for: p)
            if p == phase { break }
        }

        await uiState.setPhase(phase)
        await updateWizardProgress()
        Logger.info("📋 Registered objectives for phases up to \(phase)", category: .ai)
    }

    /// Set user approval for skipping KC generation.
    /// Only call this when user explicitly approves via UI interaction.
    func setUserApprovedKCSkip(_ approved: Bool) {
        userApprovedKCSkip = approved
        if approved {
            Logger.info("✅ User approved skipping KC generation", category: .ai)
        }
    }
    // MARK: - Wizard Progress (Queries ObjectiveStore)
    private func updateWizardProgress() async {
        // Phase 1 objectives
        let hasProfile = await objectiveStore.getObjectiveStatus(OnboardingObjectiveId.applicantProfileComplete.rawValue) == .completed
        // Phase 2 objectives
        let hasTimeline = await objectiveStore.getObjectiveStatus(OnboardingObjectiveId.skeletonTimelineComplete.rawValue) == .completed
        let hasSections = await objectiveStore.getObjectiveStatus(OnboardingObjectiveId.enabledSections.rawValue) == .completed
        // Phase 3 objectives
        let hasCardInventory = await objectiveStore.getObjectiveStatus(OnboardingObjectiveId.cardInventoryComplete.rawValue) == .completed
        let hasCardsGenerated = await objectiveStore.getObjectiveStatus(OnboardingObjectiveId.knowledgeCardsGenerated.rawValue) == .completed
        let hasWriting = await objectiveStore.getObjectiveStatus(OnboardingObjectiveId.writingSamplesCollected.rawValue) == .completed
        // Phase 4 objectives
        let hasDossier = await objectiveStore.getObjectiveStatus(OnboardingObjectiveId.dossierComplete.rawValue) == .completed

        // First: Set current wizard step based on actual phase (1:1 mapping)
        switch phase {
        case .phase1VoiceContext:
            currentWizardStep = .voice
        case .phase2CareerStory:
            currentWizardStep = .story
        case .phase3EvidenceCollection:
            currentWizardStep = .evidence
        case .phase4StrategicSynthesis:
            currentWizardStep = .strategy
        case .complete:
            currentWizardStep = .strategy  // Stay on strategy when complete
        }

        // Second: Mark steps as completed based on phase progression
        // If we've advanced past a phase, mark its wizard step as complete
        // (handles "proceed anyway" scenarios where objectives may be skipped)

        // Voice: complete if Phase 1 objectives done OR we've moved past Phase 1
        if (hasProfile && hasTimeline && hasSections) ||
           phase == .phase2CareerStory || phase == .phase3EvidenceCollection || phase == .phase4StrategicSynthesis || phase == .complete {
            completedWizardSteps.insert(.voice)
        }
        // Story: complete if Phase 2 objectives done OR we've moved past Phase 2
        if (hasCardInventory && hasCardsGenerated) ||
           phase == .phase3EvidenceCollection || phase == .phase4StrategicSynthesis || phase == .complete {
            completedWizardSteps.insert(.story)
        }
        // Evidence: complete if Phase 3 objectives done OR we've moved to Phase 4 or complete
        if (hasWriting && hasDossier) || phase == .phase4StrategicSynthesis || phase == .complete {
            completedWizardSteps.insert(.evidence)
        }
        // Strategy: completed when interview is complete
        if phase == .complete {
            completedWizardSteps.insert(.strategy)
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
        // Ensure LLMStateManager has an initial allowed-tools snapshot, even if
        // SessionUIState published tool permissions before subscriptions attached.
        let effectiveTools = await uiState.getEffectiveAllowedToolsSnapshot()
        await llmStateManager.setAllowedToolNames(effectiveTools)
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
            // Pass emitEvent: false to avoid infinite loop
            // (this event was already emitted by the original source)
            await uiState.setPendingExtraction(extraction, emitEvent: false)
        case .streamingStatusUpdated(let status, _):
            await uiState.setStreamingStatus(status)
        case .errorOccurred(let error):
            // On stream errors, retry pending tool responses if any
            if error.hasPrefix("Stream error:") {
                if let pendingPayloads = await llmStateManager.getPendingToolResponsesForRetry() {
                    Logger.warning("🔄 Stream error recovery: retrying \(pendingPayloads.count) pending tool response(s)", category: .ai)
                    await retryToolResponses(pendingPayloads)
                } else {
                    Logger.warning("🔄 Stream error: recovery exhausted, conversation will resend full history on next request", category: .ai)
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
                // ConversationLog handles gating - will fill pending tool slots before appending
                await conversationLog.appendUser(text: text, isSystemGenerated: isSystemGenerated)
                Logger.debug("StateCoordinator: system-generated user message sent to ConversationLog", category: .ai)
            }
        case .llmSentToolResponseMessage:
            break
        case .llmStatus(let status):
            let newProcessingState = status == .busy
            await uiState.setProcessingState(newProcessingState)
        case .streamingMessageBegan(let id, let text, _):
            await streamingBuffer.begin(id: id, initialText: text)
        case .streamingMessageUpdated(let id, let delta, _):
            await streamingBuffer.appendDelta(id: id, delta: delta)
        case .streamingMessageFinalized(let id, let finalText, let toolCalls, _):
            // ConversationLog is the sole source of truth
            let logToolCalls = toolCalls?.map { info in
                ToolCallInfo(id: info.id, name: info.name, arguments: info.arguments)
            }
            await conversationLog.appendAssistant(id: id, text: finalText, toolCalls: logToolCalls)
            // Clear streaming buffer - message is now in ConversationLog
            await streamingBuffer.finalize()
        case .llmEnqueueUserMessage(let payload, let isSystemGenerated, let chatboxMessageId, let originalText, let toolChoice):
            // Bundle any queued coordinator messages WITH the user message
            // They'll be included as input items in the same API request
            let bundledDevMessages = await llmStateManager.drainQueuedCoordinatorMessages()
            if !bundledDevMessages.isEmpty {
                Logger.info("📦 Bundling \(bundledDevMessages.count) coordinator message(s) with user message", category: .ai)
            }
            await streamQueueManager.enqueue(.userMessage(
                payload: payload,
                isSystemGenerated: isSystemGenerated,
                chatboxMessageId: chatboxMessageId,
                originalText: originalText,
                bundledCoordinatorMessages: bundledDevMessages,
                toolChoice: toolChoice
            ))
        case .llmSendCoordinatorMessage(let payload):
            // Codex paradigm: Always queue coordinator messages until user action
            // Developer messages are batched and flushed when:
            // 1. User sends a chatbox message
            // 2. An artifact completion arrives (sent as user message)
            // 3. A pending UI tool call is completed
            if let forcedTool = payload["toolChoice"].string {
                await llmStateManager.setPendingForcedToolChoice(forcedTool)
            }
            await llmStateManager.queueCoordinatorMessage(payload)
            Logger.debug("📥 Developer message queued (awaiting user action)", category: .ai)
        case .llmToolCallBatchStarted(let expectedCount, let callIds):
            // Reset collected payloads for new batch
            // ConversationLog already has slots created via appendAssistant
            collectedToolResponsePayloads = []
            Logger.info("📦 Tool call batch started: expecting \(expectedCount) responses, callIds: \(callIds.map { String($0.prefix(8)) })", category: .ai)
        case .llmEnqueueToolResponse(let payload):
            // Collect the payload
            collectedToolResponsePayloads.append(payload)
            let callId = payload["callId"].stringValue
            Logger.info("📦 Tool response collected: \(callId.prefix(8)) (total: \(collectedToolResponsePayloads.count))", category: .ai)

            // Check if all ConversationLog slots are filled (including UI tool slots)
            let hasPending = await conversationLog.hasPendingToolCalls
            if !hasPending {
                // All slots filled - send the batch
                let payloadsToSend = collectedToolResponsePayloads
                collectedToolResponsePayloads = []
                if payloadsToSend.count == 1 {
                    await streamQueueManager.enqueue(.toolResponse(payload: payloadsToSend[0]))
                    Logger.info("📦 Single tool response enqueued", category: .ai)
                } else if payloadsToSend.count > 1 {
                    await streamQueueManager.enqueue(.batchedToolResponses(payloads: payloadsToSend))
                    Logger.info("📦 Batched tool responses enqueued (\(payloadsToSend.count) responses)", category: .ai)
                }
            } else {
                Logger.debug("📦 Holding tool response - waiting for more slots to fill", category: .ai)
            }
        case .toolResultFilled:
            // Tool slot filled in ConversationLog - check if we can release held payloads
            if !collectedToolResponsePayloads.isEmpty {
                let hasPending = await conversationLog.hasPendingToolCalls
                if !hasPending {
                    let payloadsToSend = collectedToolResponsePayloads
                    collectedToolResponsePayloads = []
                    if payloadsToSend.count == 1 {
                        await streamQueueManager.enqueue(.toolResponse(payload: payloadsToSend[0]))
                        Logger.info("📦 Single tool response released after slot fill", category: .ai)
                    } else if payloadsToSend.count > 1 {
                        await streamQueueManager.enqueue(.batchedToolResponses(payloads: payloadsToSend))
                        Logger.info("📦 Batched tool responses released after slot fill (\(payloadsToSend.count) responses)", category: .ai)
                    }
                }
            }
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
            // Clear any queued coordinator messages for this objective when it completes
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
                    // Pre-populate todo list BEFORE phase change
                    // This ensures LLM sees updated list on next turn
                    // Use setItemsFromScript to mark items as locked (LLM can't remove them)
                    if let script = await MainActor.run(body: { phaseRegistry.script(for: newPhase) }) {
                        await todoStore.setItemsFromScript(script.initialTodoItems)
                        Logger.info("📋 Pre-populated todo list for \(newPhase.rawValue): \(script.initialTodoItems.count) items (locked)", category: .ai)
                    }
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
    // MARK: - Retry Logic with Exponential Backoff

    /// Retry tool responses with exponential backoff based on retry attempt
    /// Implements: 2s → 4s → 8s progression with max 3 retries
    private func retryToolResponses(_ payloads: [JSON]) async {
        // Get current retry count from LLMStateManager to calculate delay
        let retryCount = await llmStateManager.getPendingToolResponseRetryCount()

        // Calculate exponential backoff delay: 2^(retryCount) seconds
        // Retry 1: 2s, Retry 2: 4s, Retry 3: 8s
        let delaySeconds = pow(2.0, Double(retryCount))
        let delayNanoseconds = UInt64(delaySeconds * 1_000_000_000)

        Logger.info("⏱️ Stream error retry #\(retryCount + 1): waiting \(delaySeconds)s before retry", category: .ai)
        try? await Task.sleep(nanoseconds: delayNanoseconds)

        // Publish retry event
        if payloads.count == 1 {
            await eventBus.publish(.llmExecuteToolResponse(payload: payloads[0]))
        } else {
            await eventBus.publish(.llmExecuteBatchedToolResponses(payloads: payloads))
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
    /// Clear pending tool responses (call after successful acknowledgment)
    func clearPendingToolResponses() async {
        await llmStateManager.clearPendingToolResponses()
    }

    // MARK: - Completed Tool Results (Anthropic History)

    /// Store a completed tool result - ConversationLog is the sole source of truth
    func addCompletedToolResult(callId: String, toolName: String, output: String) async {
        await conversationLog.setToolResult(callId: callId, output: output, status: .completed)
        Logger.debug("✅ Tool result stored: \(toolName) (\(callId.prefix(8)))", category: .ai)
    }

    // MARK: - Pending UI Tool Call (Codex Paradigm)
    // UI tools present cards and await user action before responding.
    // When a UI tool is pending, coordinator messages are queued behind it.
    // NOTE: OperationTracker is the source of truth for pending UI tool state.
    // When a tool returns .pendingUserAction, ToolExecutionCoordinator calls
    // operation.setAwaitingUser() which sets the operation's state in OperationTracker.

    /// Set a UI tool as pending (awaiting user action)
    /// NOTE: This is called for logging/coordination. The actual state is in OperationTracker.
    func setPendingUIToolCall(callId: String, toolName: String) async {
        // Operation already in awaitingUser state via ToolOperation.setAwaitingUser()
        Logger.info("🎯 UI tool pending: \(toolName) (callId: \(callId.prefix(8)))", category: .ai)
    }

    /// Get the pending UI tool call info from OperationTracker
    func getPendingUIToolCall() async -> (callId: String, toolName: String)? {
        await operationTracker.getAwaitingUserOperation()
    }

    /// Clear the pending UI tool call (after user action sends tool output)
    /// NOTE: The operation gets completed via operation.complete() when tool response is sent.
    func clearPendingUIToolCall() async {
        // Batch release is handled by .toolResultFilled event when slot is filled
        Logger.debug("✅ UI tool call cleared (operation completed)", category: .ai)
    }

    /// Pop any pending forced tool choice override (one-shot).
    func popPendingForcedToolChoice() async -> String? {
        await llmStateManager.popPendingForcedToolChoice()
    }

    /// Set a pending forced tool choice for the next LLM request.
    /// Used to force a specific tool call after a UI tool completes.
    func setPendingForcedToolChoice(_ toolName: String) async {
        await llmStateManager.setPendingForcedToolChoice(toolName)
    }

    // MARK: - Reset
    func reset() async {
        phase = .phase1VoiceContext
        currentWizardStep = .voice
        completedWizardSteps.removeAll()
        collectedToolResponsePayloads = []
        // Reset all services
        await objectiveStore.reset()
        await artifactRepository.reset()
        await streamingBuffer.reset()
        await uiState.reset()
        await streamQueueManager.reset()
        await llmStateManager.reset()
        // Reset new architecture
        await conversationLog.reset()
        await operationTracker.reset()
        Logger.info("🔄 StateCoordinator reset (all services reset)", category: .ai)
    }

    // MARK: - ConversationLog Access (New Architecture)

    /// Get the conversation log for direct access
    func getConversationLog() -> ConversationLog {
        conversationLog
    }

    /// Get the operation tracker for tool lifecycle management
    func getOperationTracker() -> OperationTracker {
        operationTracker
    }
    // MARK: - ToolPane Card Tracking (Delegated to LLMStateManager)
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
                knowledgeCards: await artifactRepository.getKnowledgeCards()
            )
        }
    }

    func listArtifactSummaries() async -> [JSON] {
        await artifactRepository.listArtifactSummaries()
    }

    /// Get enabled sections configured by user in Phase 1
    func getEnabledSections() async -> Set<String> {
        await artifactRepository.getEnabledSections()
    }

    /// Store custom field definitions
    func storeCustomFieldDefinitions(_ definitions: [CustomFieldDefinition]) async {
        await artifactRepository.setCustomFieldDefinitions(definitions)
    }

    /// Get custom field definitions configured by user in Phase 2
    func getCustomFieldDefinitions() async -> [CustomFieldDefinition] {
        await artifactRepository.getCustomFieldDefinitions()
    }

    /// Direct access to artifact records for UI sync
    var artifactRecords: [JSON] {
        get async {
            await artifactRepository.getArtifacts().artifactRecords
        }
    }

    // Chat delegation - ConversationLog is source of truth, plus streaming message
    var messages: [OnboardingMessage] {
        get async {
            // Get finalized messages from ConversationLog
            var msgs = await conversationLog.getMessagesForUI()

            // Add current streaming message if any (not yet in ConversationLog)
            if let streamingMsg = await streamingBuffer.currentMessage {
                msgs.append(streamingMsg)
            }

            return msgs
        }
    }
    /// Append user message - gated by ConversationLog (fills pending tool slots first)
    /// - Returns: Message ID (always appends, gating is internal)
    func appendUserMessage(_ text: String, isSystemGenerated: Bool = false) async -> UUID? {
        // ConversationLog is the sole source of truth - handles gating for pending tool calls
        await conversationLog.appendUser(text: text, isSystemGenerated: isSystemGenerated)

        // Return a UUID for backwards compatibility (ConversationLog doesn't expose IDs)
        // TODO: Clean up callers that depend on this return value
        return UUID()
    }

    func appendAssistantMessage(_ text: String) async -> UUID {
        let id = UUID()
        await conversationLog.appendAssistant(id: id, text: text, toolCalls: nil)
        return id
    }
    // UI State delegation
    func setActiveState(_ active: Bool) async {
        await uiState.setActiveState(active)
        Logger.info("🎛️ Interview active state set to: \(active) (chatbox \(active ? "enabled" : "disabled"))", category: .ai)
    }
    func publishAllowedToolsNow() async {
        await uiState.publishToolPermissionsNow()
    }
    /// Check tool availability using centralized gating logic
    /// - Parameter toolName: Name of the tool to check
    /// - Returns: Availability status with reason if blocked
    func checkToolAvailability(_ toolName: String) async -> ToolAvailability {
        let waitingState = await uiState.getWaitingState()
        let phaseTools = phasePolicy.allowedTools[phase] ?? []
        return ToolGating.availability(
            for: toolName,
            waitingState: waitingState,
            phaseAllowedTools: phaseTools,
            excludedTools: excludedTools
        )
    }

    /// Remove a tool from the allowed tools list (e.g., after one-time use)
    func excludeTool(_ toolName: String) async {
        excludedTools.insert(toolName)
        Logger.info("🚫 Tool excluded from future calls: \(toolName)", category: .ai)
        // Update SessionUIState's excluded tools (this also republishes permissions)
        await uiState.excludeTool(toolName)
    }

    // MARK: - Dossier Tracking API

    /// Build a prompt for the LLM to ask a dossier question
    func buildDossierPrompt() -> String? {
        dossierTracker.buildDossierPrompt(for: phase)
    }

    // MARK: - Dossier WIP Notes API

    /// Update dossier WIP notes (replaces entire content)
    func setDossierNotes(_ notes: String) {
        dossierNotes = notes
        Logger.info("📝 Dossier notes updated (\(notes.count) chars)", category: .ai)
    }

    /// Get current dossier notes
    func getDossierNotes() -> String {
        dossierNotes
    }

    /// Re-include a previously excluded tool (e.g., when user action enables it)
    func includeTool(_ toolName: String) async {
        excludedTools.remove(toolName)
        Logger.info("✅ Tool re-included in allowed calls: \(toolName)", category: .ai)
        // Update SessionUIState's excluded tools (this also republishes permissions)
        await uiState.includeTool(toolName)
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
}
