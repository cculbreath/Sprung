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

    private let objectives: ObjectiveStore
    private let artifacts: ArtifactRepository
    private let chat: ChatTranscriptStore
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
        self.objectives = objectives
        self.artifacts = artifacts
        self.chat = chat
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
        await objectives.registerDefaultObjectives(for: phase)

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
        return await objectives.canAdvancePhase(from: phase)
    }

    // MARK: - Wizard Progress (Queries ObjectiveStore)

    private func updateWizardProgress() async {
        // Query objective statuses from ObjectiveStore
        let hasProfile = await objectives.getObjectiveStatus("P1.1") == .completed
        let hasTimeline = await objectives.getObjectiveStatus("P1.2") == .completed
        let hasSections = await objectives.getObjectiveStatus("P1.3") == .completed

        let hasExperienceInterview = await objectives.getObjectiveStatus("interviewed_one_experience") == .completed
        let hasKnowledgeCard = await objectives.getObjectiveStatus("one_card_generated") == .completed

        let hasWriting = await objectives.getObjectiveStatus("one_writing_sample") == .completed
        let hasDossier = await objectives.getObjectiveStatus("dossier_complete") == .completed

        // Start from introduction
        if currentWizardStep == .introduction {
            let allObjectives = await objectives.getAllObjectives()
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

    func scratchpadSummary(maxCharacters: Int = 1500) async -> String {
        var lines: [String] = []

        lines.append("phase=\(phase.rawValue)")

        // Objectives from ObjectiveStore
        let objectiveSummary = await objectives.scratchpadSummary(for: phase)
        lines.append(objectiveSummary)

        // Artifacts from ArtifactRepository
        let artifactLines = await artifacts.scratchpadSummary()
        lines.append(contentsOf: artifactLines)

        let combined = lines.joined(separator: "\n")
        return truncateForScratchpad(combined, limit: maxCharacters)
    }

    private func truncateForScratchpad(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        let endIndex = text.index(text.startIndex, offsetBy: limit)
        return String(text[..<endIndex]) + "..."
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
        case .checkpointRequested:
            await emitSnapshot(reason: "checkpoint")

        case .applicantProfileStored(let profile):
            await artifacts.setApplicantProfile(profile)
            Logger.info("👤 Applicant profile stored via event", category: .ai)

        case .skeletonTimelineStored(let timeline):
            await artifacts.setSkeletonTimeline(timeline)
            Logger.info("📅 Skeleton timeline stored via event", category: .ai)

        case .enabledSectionsUpdated(let sections):
            await artifacts.setEnabledSections(sections)
            Logger.info("📑 Enabled sections updated via event", category: .ai)

        default:
            break
        }
    }

    private func handleProcessingEvent(_ event: OnboardingEvent) async {
        switch event {
        case .processingStateChanged(let processing):
            // Delegate to SessionUIState
            await uiState.setProcessingState(processing)

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
        case .llmUserMessageSent(let messageId, let payload, let isSystemGenerated):
            let text = payload["text"].stringValue
            _ = await chat.appendUserMessage(text, isSystemGenerated: isSystemGenerated)
            messagesSync = await chat.getAllMessages() // Update sync cache
            Logger.debug("StateCoordinator: user message appended via chat service", category: .ai)

        case .llmSentToolResponseMessage:
            break

        case .llmStatus(let status):
            let newProcessingState = status == .busy
            await uiState.setProcessingState(newProcessingState)
            isProcessingSync = newProcessingState // Update sync cache

        case .streamingMessageBegan(let id, let text, let reasoningExpected):
            _ = await chat.beginStreamingMessage(id: id, initialText: text, reasoningExpected: reasoningExpected)
            messagesSync = await chat.getAllMessages()
            streamingMessageSync = await chat.getStreamingMessage()

        case .streamingMessageUpdated(let id, let delta):
            await chat.updateStreamingMessage(id: id, delta: delta)
            messagesSync = await chat.getAllMessages()
            streamingMessageSync = await chat.getStreamingMessage()

        case .streamingMessageFinalized(let id, let finalText, let toolCalls):
            await chat.finalizeStreamingMessage(id: id, finalText: finalText, toolCalls: toolCalls)
            messagesSync = await chat.getAllMessages()
            streamingMessageSync = nil

        case .llmReasoningSummaryDelta(let delta):
            await chat.updateReasoningSummary(delta: delta)
            currentReasoningSummarySync = await chat.getCurrentReasoningSummary()
            isReasoningActiveSync = await chat.getIsReasoningActive()

        case .llmReasoningSummaryComplete(let text):
            await chat.completeReasoningSummary(finalText: text)
            currentReasoningSummarySync = await chat.getCurrentReasoningSummary()
            isReasoningActiveSync = false

        default:
            break
        }
    }

    private func handleObjectiveEvent(_ event: OnboardingEvent) async {
        switch event {
        case .objectiveStatusRequested(let id, let response):
            let status = await objectives.getObjectiveStatus(id)
            response(status?.rawValue)

        case .objectiveStatusUpdateRequested(let id, let statusString, let source, let notes):
            guard let status = ObjectiveStatus(rawValue: statusString) else {
                Logger.warning("Invalid objective status: \(statusString)", category: .ai)
                return
            }
            await objectives.setObjectiveStatus(id, status: status, source: source, notes: notes)

        case .objectiveStatusChanged:
            // Update sync cache when objectives change
            objectivesSync = await objectives.objectivesSync
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

        case .phaseAdvanceRequested(let request, _):
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
            await artifacts.createTimelineCard(card)

        case .timelineCardUpdated(let id, let fields):
            await artifacts.updateTimelineCard(id: id, fields: fields)

        case .timelineCardDeleted(let id):
            await artifacts.deleteTimelineCard(id: id)

        case .timelineCardsReordered(let orderedIds):
            await artifacts.reorderTimelineCards(orderedIds: orderedIds)

        case .skeletonTimelineReplaced(let timeline, let diff, _):
            await artifacts.replaceSkeletonTimeline(timeline, diff: diff)

        default:
            break
        }
    }

    private func handleArtifactEvent(_ event: OnboardingEvent) async {
        switch event {
        case .artifactRecordProduced(let record):
            await artifacts.upsertArtifactRecord(record)
            artifactRecordsSync = await artifacts.artifactRecordsSync

        case .artifactRecordPersisted(let record):
            await artifacts.upsertArtifactRecord(record)
            artifactRecordsSync = await artifacts.artifactRecordsSync

        case .artifactRecordsReplaced(let records):
            await artifacts.setArtifactRecords(records)
            artifactRecordsSync = records

        case .artifactMetadataUpdateRequested(let artifactId, let updates):
            await artifacts.updateArtifactMetadata(artifactId: artifactId, updates: updates)
            artifactRecordsSync = await artifacts.artifactRecordsSync

        case .knowledgeCardPersisted(let card):
            await artifacts.addKnowledgeCard(card)

        case .knowledgeCardsReplaced(let cards):
            await artifacts.setKnowledgeCards(cards)

        default:
            break
        }
    }

    private func handleToolpaneEvent(_ event: OnboardingEvent) async {
        switch event {
        case .choicePromptRequested(let prompt, _):
            await uiState.setPendingChoice(prompt)

        case .choicePromptCleared:
            await uiState.setPendingChoice(nil)

        case .uploadRequestPresented(let request, _):
            await uiState.setPendingUpload(request)

        case .uploadRequestCancelled:
            await uiState.setPendingUpload(nil)

        case .validationPromptRequested(let prompt, _):
            await uiState.setPendingValidation(prompt)

        case .validationPromptCleared:
            await uiState.setPendingValidation(nil)

        default:
            break
        }
    }

    // MARK: - Snapshot Management

    struct StateSnapshot: Codable {
        let phase: InterviewPhase
        let objectives: [String: ObjectiveStore.ObjectiveEntry]
        let wizardStep: String
        let completedWizardSteps: Set<String>
    }

    func createSnapshot() async -> StateSnapshot {
        let allObjectives = await objectives.getAllObjectives()
        let objectivesDict = Dictionary(uniqueKeysWithValues: allObjectives.map { ($0.id, $0) })

        return StateSnapshot(
            phase: phase,
            objectives: objectivesDict,
            wizardStep: currentWizardStep.rawValue,
            completedWizardSteps: Set(completedWizardSteps.map { $0.rawValue })
        )
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
        await objectives.reset()
        await artifacts.reset()
        await chat.reset()
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
}
