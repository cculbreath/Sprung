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
    // MARK: - Type Aliases (Backward Compatibility)

    typealias ObjectiveEntry = ObjectiveStore.ObjectiveEntry
    typealias OnboardingArtifacts = ArtifactRepository.OnboardingArtifacts

    // MARK: - Event System

    let eventBus: EventCoordinator
    private var subscriptionTask: Task<Void, Never>?

    // MARK: - Domain Services (Injected)

    private let objectiveStore: ObjectiveStore
    private let artifactRepository: ArtifactRepository
    private let chatStore: ChatTranscriptStore
    private let uiState: SessionUIState

    // MARK: - Phase Policy

    private let phasePolicy: PhasePolicy

    // MARK: - Core Interview State

    private(set) var phase: InterviewPhase = .phase1CoreFacts

    // MARK: - Synchronous Caches (for SwiftUI)

    /// PATTERN: Synchronous State Access for SwiftUI
    /// These nonisolated(unsafe) properties are synchronous caches updated from service events.
    /// StateCoordinator maintains these caches to provide a single point of access for SwiftUI views.
    ///
    /// Services own the authoritative state; StateCoordinator mirrors it here for sync access.
    /// Views only need @ObservedObject state: StateCoordinator instead of multiple service references.

    // From ObjectiveStore
    nonisolated(unsafe) private(set) var objectivesSync: [String: ObjectiveStore.ObjectiveEntry] = [:]

    // From ArtifactRepository
    nonisolated(unsafe) private(set) var artifactRecordsSync: [JSON] = []

    // From ChatTranscriptStore
    nonisolated(unsafe) private(set) var messagesSync: [OnboardingMessage] = []
    nonisolated(unsafe) private(set) var streamingMessageSync: ChatTranscriptStore.StreamingMessage?
    nonisolated(unsafe) private(set) var currentReasoningSummarySync: String?
    nonisolated(unsafe) private(set) var isReasoningActiveSync = false

    // From SessionUIState
    nonisolated(unsafe) private(set) var isProcessingSync = false
    nonisolated(unsafe) private(set) var isActiveSync = false
    nonisolated(unsafe) private(set) var pendingExtractionSync: OnboardingPendingExtraction?
    nonisolated(unsafe) private(set) var pendingStreamingStatusSync: String?
    nonisolated(unsafe) private(set) var pendingPhaseAdvanceRequestSync: OnboardingPhaseAdvanceRequest?

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

    // MARK: - Stream Queue Management (Ensures Serial LLM Streaming)

    enum StreamRequestType {
        case userMessage(payload: JSON, isSystemGenerated: Bool)
        case developerMessage(payload: JSON)
        case toolResponse(payload: JSON)
    }

    private var isStreaming = false
    private var streamQueue: [StreamRequestType] = []
    private(set) var hasStreamedFirstResponse = false

    // MARK: - LLM State (Single Source of Truth)

    private var allowedToolNames: Set<String> = []
    private var conversationId: String?
    private var lastResponseId: String?
    private var currentModelId: String = "gpt-5"

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

        // Register default objectives for new phase
        await objectiveStore.registerDefaultObjectives(for: phase)

        // Update UI state phase (for tool permissions)
        await uiState.setPhase(phase)

        // Update wizard progress
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
        // Query objective statuses from ObjectiveStore
        let hasProfile = await objectiveStore.getObjectiveStatus("applicant_profile") == .completed
        let hasTimeline = await objectiveStore.getObjectiveStatus("skeleton_timeline") == .completed
        let hasSections = await objectiveStore.getObjectiveStatus("enabled_sections") == .completed

        let hasExperienceInterview = await objectiveStore.getObjectiveStatus("interviewed_one_experience") == .completed
        let hasKnowledgeCard = await objectiveStore.getObjectiveStatus("one_card_generated") == .completed

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

        // Artifact Discovery (Phase 2)
        if hasExperienceInterview && hasKnowledgeCard {
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

    // MARK: - Scratchpad Summary (Aggregates from Services)

//    func scratchpadSummary(maxCharacters: Int = 1500) async -> String {
//        var lines: [String] = []
//
//        lines.append("phase=\(phase.rawValue)")
//
//        // Objectives from ObjectiveStore
//        let objectiveSummary = await objectiveStore.scratchpadSummary(for: phase)
//        lines.append(objectiveSummary)
//
//        // Artifacts from ArtifactRepository
//        let artifactLines = await artifactRepository.scratchpadSummary()
//        lines.append(contentsOf: artifactLines)
//
//        let combined = lines.joined(separator: "\n")
//        return truncateForScratchpad(combined, limit: maxCharacters)
//    }
//
//    private func truncateForScratchpad(_ text: String, limit: Int) -> String {
//        guard text.count > limit else { return text }
//        let endIndex = text.index(text.startIndex, offsetBy: limit)
//        return String(text[..<endIndex]) + "..."
//    }
//
//    // MARK: - Event Subscription Setup

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
        case .checkpointRequested:
            await emitSnapshot(reason: "checkpoint")

        case .applicantProfileStored:
            // Event notification only - data already stored in ArtifactRepository
            // Do NOT call setApplicantProfile here as it would create an infinite event loop
            Logger.info("👤 Applicant profile stored via event", category: .ai)

        case .skeletonTimelineStored:
            // Event notification only - data already stored in ArtifactRepository
            // Do NOT call setSkeletonTimeline here as it would create an infinite event loop
            Logger.info("📅 Skeleton timeline stored via event", category: .ai)

        case .enabledSectionsUpdated:
            // Event notification only - data already stored in ArtifactRepository
            // Do NOT call setEnabledSections here as it would create an infinite event loop
            Logger.info("📑 Enabled sections updated via event", category: .ai)

        case .stateAllowedToolsUpdated(let tools):
            allowedToolNames = tools
            Logger.info("🔧 Allowed tools updated in StateCoordinator: \(tools.count) tools", category: .ai)

        default:
            break
        }
    }

    private func handleProcessingEvent(_ event: OnboardingEvent) async {
        switch event {
        case .processingStateChanged(let processing):
            // Update StateCoordinator's cache first (source of truth)
            isProcessingSync = processing
            // Then delegate to SessionUIState
            await uiState.setProcessingState(processing, emitEvent: false)

        case .waitingStateChanged(let waiting):
            // SessionUIState handles this internally, just log
            Logger.debug("Waiting state changed: \(waiting ?? "nil")", category: .ai)

        case .pendingExtractionUpdated(let extraction):
            await uiState.setPendingExtraction(extraction)
            pendingExtractionSync = extraction // Update sync cache

        case .streamingStatusUpdated(let status):
            await uiState.setStreamingStatus(status)
            pendingStreamingStatusSync = status // Update sync cache

        default:
            break
        }
    }

    private func handleLLMEvent(_ event: OnboardingEvent) async {
        switch event {
        case .llmUserMessageSent(_, let payload, let isSystemGenerated):
            let text = payload["text"].stringValue
            _ = await chatStore.appendUserMessage(text, isSystemGenerated: isSystemGenerated)
            messagesSync = await chatStore.getAllMessages() // Update sync cache
            Logger.debug("StateCoordinator: user message appended via chat service", category: .ai)

        case .llmSentToolResponseMessage:
            break

        case .llmStatus(let status):
            let newProcessingState = status == .busy
            await uiState.setProcessingState(newProcessingState)
            isProcessingSync = newProcessingState // Update sync cache

        case .streamingMessageBegan(let id, let text, let reasoningExpected):
            _ = await chatStore.beginStreamingMessage(id: id, initialText: text, reasoningExpected: reasoningExpected)
            messagesSync = await chatStore.getAllMessages()
            streamingMessageSync = await chatStore.getStreamingMessage()

        case .streamingMessageUpdated(let id, let delta):
            await chatStore.updateStreamingMessage(id: id, delta: delta)
            messagesSync = await chatStore.getAllMessages()
            streamingMessageSync = await chatStore.getStreamingMessage()

        case .streamingMessageFinalized(let id, let finalText, let toolCalls):
            await chatStore.finalizeStreamingMessage(id: id, finalText: finalText, toolCalls: toolCalls)
            messagesSync = await chatStore.getAllMessages()
            streamingMessageSync = nil

        case .llmReasoningSummaryDelta(let delta):
            await chatStore.updateReasoningSummary(delta: delta)
            currentReasoningSummarySync = await chatStore.getCurrentReasoningSummary()
            isReasoningActiveSync = await chatStore.getIsReasoningActive()

        case .llmReasoningSummaryComplete(let text):
            await chatStore.completeReasoningSummary(finalText: text)
            currentReasoningSummarySync = await chatStore.getCurrentReasoningSummary()
            isReasoningActiveSync = false

        case .llmEnqueueUserMessage(let payload, let isSystemGenerated):
            enqueueStreamRequest(.userMessage(payload: payload, isSystemGenerated: isSystemGenerated))

        case .llmEnqueueDeveloperMessage(let payload):
            enqueueStreamRequest(.developerMessage(payload: payload))

        case .llmEnqueueToolResponse(let payload):
            enqueueStreamRequest(.toolResponse(payload: payload))

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

        case .objectiveStatusChanged:
            // Update sync cache when objectives change
            objectivesSync = objectiveStore.objectivesSync
            // Update wizard progress
            await updateWizardProgress()

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

        case .phaseAdvanceRequested(let request):
            await uiState.setPendingPhaseAdvanceRequest(request)
            pendingPhaseAdvanceRequestSync = request

        case .phaseTransitionApplied:
            await uiState.setPendingPhaseAdvanceRequest(nil)
            pendingPhaseAdvanceRequestSync = nil

        case .phaseAdvanceDismissed:
            await uiState.setPendingPhaseAdvanceRequest(nil)
            pendingPhaseAdvanceRequestSync = nil

        default:
            break
        }
    }

    private func handleTimelineEvent(_ event: OnboardingEvent) async {
        switch event {
        case .timelineCardCreated(let card):
            await artifactRepository.createTimelineCard(card)

        case .timelineCardUpdated(let id, let fields):
            await artifactRepository.updateTimelineCard(id: id, fields: fields)

        case .timelineCardDeleted(let id):
            await artifactRepository.deleteTimelineCard(id: id)

        case .timelineCardsReordered(let orderedIds):
            await artifactRepository.reorderTimelineCards(orderedIds: orderedIds)

        case .skeletonTimelineReplaced(let timeline, let diff, _):
            await artifactRepository.replaceSkeletonTimeline(timeline, diff: diff)

        default:
            break
        }
    }

    private func handleArtifactEvent(_ event: OnboardingEvent) async {
        switch event {
        case .artifactRecordProduced(let record):
            await artifactRepository.upsertArtifactRecord(record)
            artifactRecordsSync = artifactRepository.artifactRecordsSync

        case .artifactRecordPersisted(let record):
            await artifactRepository.upsertArtifactRecord(record)
            artifactRecordsSync = artifactRepository.artifactRecordsSync

        case .artifactRecordsReplaced(let records):
            await artifactRepository.setArtifactRecords(records)
            artifactRecordsSync = records

        case .artifactMetadataUpdateRequested(let artifactId, let updates):
            await artifactRepository.updateArtifactMetadata(artifactId: artifactId, updates: updates)
            artifactRecordsSync = artifactRepository.artifactRecordsSync

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

        case .choicePromptCleared:
            await uiState.setPendingChoice(nil)

        case .uploadRequestPresented(let request):
            await uiState.setPendingUpload(request)

        case .uploadRequestCancelled:
            await uiState.setPendingUpload(nil)

        case .validationPromptRequested(let prompt):
            await uiState.setPendingValidation(prompt)

        case .validationPromptCleared:
            await uiState.setPendingValidation(nil)

        default:
            break
        }
    }

    // MARK: - Stream Queue Management

    /// Enqueue a stream request to be processed serially
    func enqueueStreamRequest(_ requestType: StreamRequestType) {
        streamQueue.append(requestType)
        Logger.debug("📥 Stream request enqueued (queue size: \(streamQueue.count))", category: .ai)

        // If not currently streaming, start processing
        if !isStreaming {
            Task {
                await processStreamQueue()
            }
        }
    }

    /// Process the stream queue serially
    private func processStreamQueue() async {
        while !streamQueue.isEmpty {
            guard !isStreaming else {
                Logger.debug("⏸️ Queue processing paused (stream in progress)", category: .ai)
                return
            }

            isStreaming = true
            let request = streamQueue.removeFirst()
            Logger.debug("▶️ Processing stream request from queue (\(streamQueue.count) remaining)", category: .ai)

            // Emit event for LLMMessenger to react to
            await emitStreamRequest(request)

            // Note: isStreaming will be set to false when .streamCompleted event is received
        }
    }

    /// Emit the appropriate stream request event for LLMMessenger to handle
    private func emitStreamRequest(_ requestType: StreamRequestType) async {
        switch requestType {
        case .userMessage(let payload, let isSystemGenerated):
            await emit(.llmExecuteUserMessage(payload: payload, isSystemGenerated: isSystemGenerated))
        case .developerMessage(let payload):
            await emit(.llmExecuteDeveloperMessage(payload: payload))
        case .toolResponse(let payload):
            await emit(.llmExecuteToolResponse(payload: payload))
        }
    }

    /// Mark stream as completed and process next in queue
    func markStreamCompleted() {
        guard isStreaming else {
            Logger.warning("markStreamCompleted called but isStreaming=false", category: .ai)
            return
        }

        isStreaming = false
        hasStreamedFirstResponse = true
        Logger.debug("✅ Stream completed (queue size: \(streamQueue.count))", category: .ai)

        // Process next item in queue if any
        if !streamQueue.isEmpty {
            Task {
                await processStreamQueue()
            }
        }
    }

    /// Check if this is the first response (for toolChoice logic)
    func getHasStreamedFirstResponse() -> Bool {
        return hasStreamedFirstResponse
    }

    // MARK: - LLM State Accessors

    /// Get allowed tool names
    func getAllowedToolNames() -> Set<String> {
        return allowedToolNames
    }

    /// Update conversation state (called by LLMMessenger when response completes)
    func updateConversationState(conversationId: String, responseId: String) {
        self.conversationId = conversationId
        self.lastResponseId = responseId
        Logger.debug("💬 Conversation state updated: \(responseId.prefix(8))", category: .ai)
    }

    /// Get last response ID
    func getLastResponseId() -> String? {
        return lastResponseId
    }

    /// Set model ID
    func setModelId(_ modelId: String) {
        currentModelId = modelId
        Logger.info("🔧 Model ID set to: \(modelId)", category: .ai)
    }

    /// Get current model ID
    func getCurrentModelId() -> String {
        return currentModelId
    }

    // MARK: - Snapshot Management

    struct StateSnapshot: Codable {
        let version: Int
        let phase: InterviewPhase
        let objectives: [String: ObjectiveStore.ObjectiveEntry]
        let wizardStep: String
        let completedWizardSteps: Set<String>

        // Custom decoding to handle legacy snapshots without version field
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 0
            phase = try container.decode(InterviewPhase.self, forKey: .phase)
            objectives = try container.decode([String: ObjectiveStore.ObjectiveEntry].self, forKey: .objectives)
            wizardStep = try container.decode(String.self, forKey: .wizardStep)
            completedWizardSteps = try container.decode(Set<String>.self, forKey: .completedWizardSteps)
        }

        // Regular initializer for creating new snapshots
        init(version: Int = 1, phase: InterviewPhase, objectives: [String: ObjectiveStore.ObjectiveEntry], wizardStep: String, completedWizardSteps: Set<String>) {
            self.version = version
            self.phase = phase
            self.objectives = objectives
            self.wizardStep = wizardStep
            self.completedWizardSteps = completedWizardSteps
        }

        private enum CodingKeys: String, CodingKey {
            case version, phase, objectives, wizardStep, completedWizardSteps
        }
    }

    func createSnapshot() async -> StateSnapshot {
        let allObjectives = await objectiveStore.getAllObjectives()
        let objectivesDict = Dictionary(uniqueKeysWithValues: allObjectives.map { ($0.id, $0) })

        return StateSnapshot(
            version: 1,
            phase: phase,
            objectives: objectivesDict,
            wizardStep: currentWizardStep.rawValue,
            completedWizardSteps: Set(completedWizardSteps.map { $0.rawValue })
        )
    }

    func restoreFromSnapshot(_ snapshot: StateSnapshot) async {
        phase = snapshot.phase

        // Restore objectives to ObjectiveStore
        await objectiveStore.restore(objectives: snapshot.objectives)

        // MIGRATION: Re-register canonical objectives for the current phase
        // This ensures any newly added objectives are present after restore
        if snapshot.version == 0 {
            Logger.info("🔄 Migrating legacy snapshot (version 0) - re-registering canonical objectives", category: .ai)
            await objectiveStore.registerDefaultObjectives(for: phase)

            // Backfill statuses for known migration scenarios
            await backfillObjectiveStatuses(snapshot: snapshot)
        }

        // Restore wizard progress
        if let step = WizardStep(rawValue: snapshot.wizardStep) {
            currentWizardStep = step
        }
        completedWizardSteps = Set(snapshot.completedWizardSteps.compactMap { WizardStep(rawValue: $0) })

        // Update sync caches
        objectivesSync = objectiveStore.objectivesSync

        Logger.info("📥 State restored from snapshot (version: \(snapshot.version))", category: .ai)
    }

    /// Backfill objective statuses when migrating from legacy snapshots
    private func backfillObjectiveStatuses(snapshot: StateSnapshot) async {
        // Migration policy: Infer status for new objectives based on existing state
        // Example: If applicant_profile is completed, assume contact_source_selected is also completed

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

        // Reset sync caches
        objectivesSync = [:]
        artifactRecordsSync = []
        messagesSync = []
        streamingMessageSync = nil
        currentReasoningSummarySync = nil
        isReasoningActiveSync = false
        isProcessingSync = false
        isActiveSync = false
        pendingExtractionSync = nil
        pendingStreamingStatusSync = nil
        pendingPhaseAdvanceRequestSync = nil

        Logger.info("🔄 StateCoordinator reset (all services reset)", category: .ai)
    }

    // MARK: - Delegation Methods (Convenience APIs)

    /// Provides backward compatibility and convenience access to service methods.
    /// These delegate to the appropriate service actors.

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

    // Artifact delegation
    func getArtifactRecord(id: String) async -> JSON? {
        await artifactRepository.getArtifactRecord(id: id)
    }

    func getArtifactsForPhaseObjective(_ objectiveId: String) async -> [JSON] {
        await artifactRepository.getArtifactsForPhaseObjective(objectiveId)
    }

    var artifacts: ArtifactRepository.OnboardingArtifacts {
        get async {
            // Reconstruct artifacts struct from repository
            ArtifactRepository.OnboardingArtifacts(
                applicantProfile: await artifactRepository.getApplicantProfile(),
                skeletonTimeline: await artifactRepository.getSkeletonTimeline(),
                enabledSections: await artifactRepository.getEnabledSections(),
                experienceCards: await artifactRepository.getExperienceCards(),
                writingSamples: await artifactRepository.getWritingSamples(),
                artifactRecords: artifactRecordsSync,
                knowledgeCards: await artifactRepository.getKnowledgeCards()
            )
        }
    }

    func listArtifactSummaries() async -> [JSON] {
        await artifactRepository.listArtifactSummaries()
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
        await chatStore.appendUserMessage(text, isSystemGenerated: isSystemGenerated)
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
        phasePolicy.allowedTools[phase] ?? []
    }

    var isProcessing: Bool {
        get async {
            isProcessingSync
        }
    }

    var isActive: Bool {
        get async {
            isActiveSync
        }
    }

    var pendingExtraction: OnboardingPendingExtraction? {
        get async {
            pendingExtractionSync
        }
    }

    var pendingStreamingStatus: String? {
        get async {
            pendingStreamingStatusSync
        }
    }

    var pendingPhaseAdvanceRequest: OnboardingPhaseAdvanceRequest? {
        get async {
            pendingPhaseAdvanceRequestSync
        }
    }
}
