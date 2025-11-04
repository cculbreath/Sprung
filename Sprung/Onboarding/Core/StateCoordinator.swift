import Foundation
import SwiftyJSON

/// Immutable phase policy configuration derived from PhaseScriptRegistry.
struct PhasePolicy {
    let requiredObjectives: [InterviewPhase: [String]]
    let allowedTools: [InterviewPhase: Set<String>]
}

/// Single source of truth for ALL onboarding state.
/// This replaces InterviewSession, InterviewState, objective ledgers, and all distributed state.
actor StateCoordinator: OnboardingEventEmitter {
    // MARK: - Event System

    let eventBus: EventCoordinator
    private var subscriptionTask: Task<Void, Never>?

    // MARK: - Phase Policy

    private let phasePolicy: PhasePolicy

    // MARK: - Core Interview State

    private(set) var phase: InterviewPhase = .phase1CoreFacts
    private(set) var isActive = false
    private(set) var isProcessing = false

    // MARK: - Objectives (Single Source)

    /// The ONLY objective tracking in the entire system
    private var objectives: [String: ObjectiveEntry] = [:]

    struct ObjectiveEntry: Codable {
        let id: String
        let label: String
        var status: ObjectiveStatus
        let phase: InterviewPhase
        var source: String
        var completedAt: Date?
        var notes: String?
    }

    // MARK: - Artifacts

    private(set) var artifacts = OnboardingArtifacts()

    struct OnboardingArtifacts {
        var applicantProfile: JSON?
        var skeletonTimeline: JSON?
        var enabledSections: Set<String> = []
        var experienceCards: [JSON] = []
        var writingSamples: [JSON] = []
        var artifactRecords: [JSON] = []
    }

    // MARK: - Chat & Messages

    private(set) var messages: [OnboardingMessage] = []
    private(set) var streamingMessage: StreamingMessage?
    private(set) var latestReasoningSummary: String?

    struct StreamingMessage {
        let id: UUID
        var text: String
        var reasoningExpected: Bool
    }

    // MARK: - Active UI State

    private(set) var pendingUploadRequest: OnboardingUploadRequest?
    private(set) var pendingChoicePrompt: OnboardingChoicePrompt?
    private(set) var pendingValidationPrompt: OnboardingValidationPrompt?
    private(set) var pendingExtraction: OnboardingPendingExtraction?
    private(set) var pendingStreamingStatus: String?

    // MARK: - Waiting State

    enum WaitingState: String {
        case selection
        case upload
        case validation
        case extraction
        case processing
    }

    private(set) var waitingState: WaitingState?

    // Phase Management
    private(set) var pendingPhaseAdvanceRequest: OnboardingPhaseAdvanceRequest?

    func setPendingPhaseAdvanceRequest(_ request: OnboardingPhaseAdvanceRequest?) {
        self.pendingPhaseAdvanceRequest = request
    }

    // MARK: - Wizard Progress

    enum WizardStep: String, CaseIterable {
        case introduction
        case resumeIntake
        case artifactDiscovery
        case writingCorpus
        case wrapUp
    }

    private(set) var currentWizardStep: WizardStep = .resumeIntake
    private(set) var completedWizardSteps: Set<WizardStep> = []

    // MARK: - Initialization

    init(eventBus: EventCoordinator, phasePolicy: PhasePolicy) {
        self.eventBus = eventBus
        self.phasePolicy = phasePolicy
        Logger.info("🎯 StateCoordinator initialized - single source of truth", category: .ai)
        // Register initial objectives directly (can't call actor-isolated method from init)
        let descriptors = Self.objectivesForPhase(phase, policy: phasePolicy)
        for descriptor in descriptors {
            objectives[descriptor.id] = ObjectiveEntry(
                id: descriptor.id,
                label: descriptor.label,
                status: .pending,
                phase: phase,
                source: "initial",
                completedAt: nil,
                notes: nil
            )
        }
    }

    // MARK: - Objective Catalog

    /// Hardcoded objective metadata (labels and structure) for each phase.
    /// The phasePolicy (from PhaseScriptRegistry) provides required objectives and allowed tools.
    private static let objectiveMetadata: [InterviewPhase: [(id: String, label: String)]] = [
        .phase1CoreFacts: [
            ("applicant_profile", "Applicant profile objective"),
            ("skeleton_timeline", "Skeleton timeline objective"),
            ("enabled_sections", "Enabled sections objective"),
            ("contact_source_selected", "Contact source selected"),
            ("contact_data_collected", "Contact data collected"),
            ("contact_data_validated", "Contact data validated"),
            ("contact_photo_collected", "Contact photo collected")
        ],
        .phase2DeepDive: [
            ("interviewed_one_experience", "Experience interview completed"),
            ("one_card_generated", "Knowledge card generated")
        ],
        .phase3WritingCorpus: [
            ("one_writing_sample", "Writing sample collected"),
            ("dossier_complete", "Dossier completed")
        ],
        .complete: []
    ]

    private static let nextPhaseMap: [InterviewPhase: InterviewPhase?] = [
        .phase1CoreFacts: .phase2DeepDive,
        .phase2DeepDive: .phase3WritingCorpus,
        .phase3WritingCorpus: .complete,
        .complete: nil
    ]

    private func registerDefaultObjectives(for phase: InterviewPhase) {
        let descriptors = Self.objectivesForPhase(phase, policy: phasePolicy)
        for descriptor in descriptors {
            registerObjective(
                descriptor.id,
                label: descriptor.label,
                phase: descriptor.phase,
                source: descriptor.source
            )
        }
    }

    private static func objectivesForPhase(_ phase: InterviewPhase, policy: PhasePolicy) -> [(id: String, label: String, phase: InterviewPhase, source: String)] {
        let metadata = objectiveMetadata[phase] ?? []
        return metadata.map { (id: $0.id, label: $0.label, phase: phase, source: "system") }
    }

    // MARK: - Phase Management

    func setPhase(_ phase: InterviewPhase) {
        self.phase = phase
        Logger.info("📍 Phase changed to: \(phase)", category: .ai)
        registerDefaultObjectives(for: phase)
        updateWizardProgress()
    }

    func advanceToNextPhase() -> InterviewPhase? {
        guard canAdvancePhase() else { return nil }

        guard let nextPhase = Self.nextPhaseMap[phase] ?? nil else {
            return nil
        }

        setPhase(nextPhase)
        return nextPhase
    }

    func canAdvancePhase() -> Bool {
        guard let requiredObjectives = phasePolicy.requiredObjectives[phase] else {
            return false
        }
        return requiredObjectives.allSatisfy { objectiveId in
            objectives[objectiveId]?.status == .completed ||
            objectives[objectiveId]?.status == .skipped
        }
    }

    // MARK: - Objective Management (The ONLY objective system)

    func registerObjective(
        _ id: String,
        label: String,
        phase: InterviewPhase,
        source: String = "system"
    ) {
        guard objectives[id] == nil else { return }

        objectives[id] = ObjectiveEntry(
            id: id,
            label: label,
            status: .pending,
            phase: phase,
            source: source,
            completedAt: nil,
            notes: nil
        )

        Logger.info("📋 Objective registered: \(id) for \(phase)", category: .ai)
    }

    func setObjectiveStatus(
        _ id: String,
        status: ObjectiveStatus,
        source: String? = nil,
        notes: String? = nil
    ) {
        guard var objective = objectives[id] else {
            Logger.warning("⚠️ Attempted to update unknown objective: \(id)", category: .ai)
            return
        }

        let oldStatus = objective.status
        objective.status = status

        if let source = source {
            objective.source = source
        }

        if let notes = notes {
            objective.notes = notes
        }

        if status == .completed && objective.completedAt == nil {
            objective.completedAt = Date()
        }

        objectives[id] = objective

        Logger.info("✅ Objective \(id): \(oldStatus) → \(status)", category: .ai)
        updateWizardProgress()
    }

    func getObjectiveStatus(_ id: String) -> ObjectiveStatus? {
        objectives[id]?.status
    }

    func getAllObjectives() -> [ObjectiveEntry] {
        Array(objectives.values)
    }

    func getObjectivesForPhase(_ phase: InterviewPhase) -> [ObjectiveEntry] {
        objectives.values.filter { $0.phase == phase }
    }

    func getMissingObjectives() -> [String] {
        let requiredForPhase = phasePolicy.requiredObjectives[phase] ?? []

        return requiredForPhase.filter { id in
            let status = objectives[id]?.status
            return status != .completed && status != .skipped
        }
    }

    // MARK: - Artifact Management

    func setApplicantProfile(_ profile: JSON?) {
        artifacts.applicantProfile = profile
        if profile != nil {
            setObjectiveStatus("applicant_profile", status: .completed, source: "artifact_saved")
        }
        Logger.info("👤 Applicant profile \(profile != nil ? "saved" : "cleared")", category: .ai)
    }

    func setSkeletonTimeline(_ timeline: JSON?) {
        artifacts.skeletonTimeline = timeline
        if timeline != nil {
            setObjectiveStatus("skeleton_timeline", status: .completed, source: "artifact_saved")
        }
        Logger.info("📅 Skeleton timeline \(timeline != nil ? "saved" : "cleared")", category: .ai)
    }

    func setArtifactRecords(_ records: [JSON]) {
        artifacts.artifactRecords = records
        Logger.info("📦 Artifact records restored: \(records.count)", category: .ai)
    }

    func addArtifactRecord(_ artifact: JSON) {
        artifacts.artifactRecords.append(artifact)
        Logger.info("📦 Artifact record added: \(artifact["id"].stringValue)", category: .ai)
    }

    func getArtifactRecord(id: String) -> JSON? {
        artifacts.artifactRecords.first { artifact in
            let artifactId = artifact["id"].stringValue
            let sha256 = artifact["sha256"].stringValue
            return artifactId == id || sha256 == id
        }
    }

    /// Idempotent upsert of artifact record by id or sha256
    private func upsertArtifactRecord(_ record: JSON) {
        let id = record["id"].string ?? record["sha256"].string ?? UUID().uuidString
        var replaced = false

        for i in artifacts.artifactRecords.indices {
            let existingId = artifacts.artifactRecords[i]["id"].string ?? artifacts.artifactRecords[i]["sha256"].string
            if existingId == id {
                artifacts.artifactRecords[i] = record
                replaced = true
                break
            }
        }

        if !replaced {
            artifacts.artifactRecords.append(record)
        }
    }

    /// List artifact summaries (id, filename, size, content_type)
    func listArtifactSummaries() -> [JSON] {
        artifacts.artifactRecords.map { artifact in
            var summary = JSON()
            summary["id"].string = artifact["id"].string ?? artifact["sha256"].string
            summary["filename"].string = artifact["filename"].string
            summary["size_bytes"].int = artifact["size_bytes"].int
            summary["content_type"].string = artifact["content_type"].string
            return summary
        }
    }

    // MARK: - Timeline Card Management

    /// Helper to get current timeline cards using TimelineCardAdapter
    private func currentTimelineCards() -> (cards: [TimelineCard], meta: JSON?) {
        let timelineJSON = artifacts.skeletonTimeline ?? JSON()
        return TimelineCardAdapter.cards(from: TimelineCardAdapter.normalizedTimeline(timelineJSON))
    }

    func createTimelineCard(_ card: JSON) {
        var (cards, meta) = currentTimelineCards()

        // Create new timeline card
        let newCard: TimelineCard
        if let id = card["id"].string {
            newCard = TimelineCard(id: id, fields: card)
        } else {
            newCard = TimelineCard(id: UUID().uuidString, fields: card)
        }

        cards.append(newCard)
        artifacts.skeletonTimeline = TimelineCardAdapter.makeTimelineJSON(cards: cards, meta: meta)
        setObjectiveStatus("skeleton_timeline", status: .inProgress)
        Logger.info("📅 Timeline card created", category: .ai)
    }

    func updateTimelineCard(id: String, fields: JSON) {
        var (cards, meta) = currentTimelineCards()

        guard let idx = cards.firstIndex(where: { $0.id == id }) else {
            Logger.warning("Timeline card \(id) not found for update", category: .ai)
            return
        }

        cards[idx] = cards[idx].applying(fields: fields)
        artifacts.skeletonTimeline = TimelineCardAdapter.makeTimelineJSON(cards: cards, meta: meta)
        Logger.info("📅 Timeline card \(id) updated", category: .ai)
    }

    func deleteTimelineCard(id: String) {
        var (cards, meta) = currentTimelineCards()

        cards.removeAll { $0.id == id }
        artifacts.skeletonTimeline = TimelineCardAdapter.makeTimelineJSON(cards: cards, meta: meta)
        Logger.info("📅 Timeline card \(id) deleted", category: .ai)
    }

    func reorderTimelineCards(orderedIds: [String]) {
        let (cards, meta) = currentTimelineCards()

        let cardMap = Dictionary(uniqueKeysWithValues: cards.map { ($0.id, $0) })
        let reordered = orderedIds.compactMap { cardMap[$0] }

        artifacts.skeletonTimeline = TimelineCardAdapter.makeTimelineJSON(cards: reordered, meta: meta)
        Logger.info("📅 Timeline cards reordered", category: .ai)
    }

    func setEnabledSections(_ sections: Set<String>) {
        artifacts.enabledSections = sections
        if !sections.isEmpty {
            setObjectiveStatus("enabled_sections", status: .completed, source: "artifact_saved")
        }
        Logger.info("📑 Enabled sections updated: \(sections.count) sections", category: .ai)
    }

    func addExperienceCard(_ card: JSON) {
        artifacts.experienceCards.append(card)
        if !artifacts.experienceCards.isEmpty {
            setObjectiveStatus("one_card_generated", status: .completed, source: "artifact_saved")
        }
    }

    func addWritingSample(_ sample: JSON) {
        artifacts.writingSamples.append(sample)
        if !artifacts.writingSamples.isEmpty {
            setObjectiveStatus("one_writing_sample", status: .completed, source: "artifact_saved")
        }
    }

    // MARK: - Message Management

    func appendUserMessage(_ text: String) -> UUID {
        let message = OnboardingMessage(
            id: UUID(),
            role: .user,
            text: text,
            timestamp: Date()
        )
        messages.append(message)
        return message.id
    }

    func appendAssistantMessage(_ text: String) -> UUID {
        let message = OnboardingMessage(
            id: UUID(),
            role: .assistant,
            text: text,
            timestamp: Date()
        )
        messages.append(message)
        return message.id
    }

    func beginStreamingMessage(initialText: String, reasoningExpected: Bool) -> UUID {
        let id = UUID()
        streamingMessage = StreamingMessage(
            id: id,
            text: initialText,
            reasoningExpected: reasoningExpected
        )

        let message = OnboardingMessage(
            id: id,
            role: .assistant,
            text: initialText,
            timestamp: Date(),
            showReasoningPlaceholder: reasoningExpected
        )
        messages.append(message)
        return id
    }

    func updateStreamingMessage(id: UUID, delta: String) {
        guard var streaming = streamingMessage, streaming.id == id else { return }
        streaming.text += delta
        streamingMessage = streaming

        if let index = messages.firstIndex(where: { $0.id == id }) {
            messages[index].text += delta
        }
    }

    func finalizeStreamingMessage(id: UUID, finalText: String) {
        streamingMessage = nil

        if let index = messages.firstIndex(where: { $0.id == id }) {
            messages[index].text = finalText
            messages[index].showReasoningPlaceholder = false
        }
    }

    func setReasoningSummary(_ summary: String?, for messageId: UUID) {
        if let index = messages.firstIndex(where: { $0.id == messageId }) {
            messages[index].reasoningSummary = summary
            messages[index].showReasoningPlaceholder = false
        }

        // Also update latest for the status bar
        latestReasoningSummary = summary
    }

    // MARK: - UI State Management

    func setProcessingState(_ processing: Bool) {
        isProcessing = processing
    }

    func setActiveState(_ active: Bool) {
        isActive = active
    }

    func setWaitingState(_ state: WaitingState?) {
        waitingState = state
    }

    func setPendingUpload(_ request: OnboardingUploadRequest?) {
        pendingUploadRequest = request
        if request != nil {
            waitingState = .upload
        }
    }

    func setPendingChoice(_ prompt: OnboardingChoicePrompt?) {
        pendingChoicePrompt = prompt
        if prompt != nil {
            waitingState = .selection
        }
    }

    func setPendingValidation(_ prompt: OnboardingValidationPrompt?) {
        pendingValidationPrompt = prompt
        if prompt != nil {
            waitingState = .validation
        }
    }

    func setPendingExtraction(_ extraction: OnboardingPendingExtraction?) {
        pendingExtraction = extraction
        if extraction != nil {
            waitingState = .extraction
        }
    }

    func setStreamingStatus(_ status: String?) {
        pendingStreamingStatus = status
    }

    // MARK: - Wizard Progress

    private func updateWizardProgress() {
        // Determine current step based on objectives
        let hasProfile = objectives["applicant_profile"]?.status == .completed
        let hasTimeline = objectives["skeleton_timeline"]?.status == .completed
        let hasSections = objectives["enabled_sections"]?.status == .completed
        _ = objectives["interviewed_one_experience"]?.status == .completed
        let hasWriting = objectives["one_writing_sample"]?.status == .completed

        if hasProfile {
            completedWizardSteps.insert(.resumeIntake)
        }

        if hasTimeline && hasSections {
            completedWizardSteps.insert(.artifactDiscovery)
            currentWizardStep = .writingCorpus
        } else if hasProfile {
            currentWizardStep = .artifactDiscovery
        }

        if hasWriting {
            completedWizardSteps.insert(.writingCorpus)
            currentWizardStep = .wrapUp
        }

        if phase == .phase3WritingCorpus && hasWriting {
            completedWizardSteps.insert(.wrapUp)
        }
    }

    // MARK: - Reset

    func reset() {
        phase = .phase1CoreFacts
        isActive = false
        isProcessing = false
        objectives.removeAll()
        artifacts = OnboardingArtifacts()
        messages.removeAll()
        streamingMessage = nil
        latestReasoningSummary = nil
        pendingUploadRequest = nil
        pendingChoicePrompt = nil
        pendingValidationPrompt = nil
        pendingExtraction = nil
        pendingStreamingStatus = nil
        waitingState = nil
        currentWizardStep = .resumeIntake
        completedWizardSteps.removeAll()

        Logger.info("🔄 StateCoordinator reset to clean state", category: .ai)
    }

    // MARK: - Snapshot for Persistence

    struct StateSnapshot: Codable {
        let phase: InterviewPhase
        let objectives: [String: ObjectiveEntry]
        let artifacts: ArtifactsSnapshot
        let wizardStep: String
        let completedWizardSteps: Set<String>

        struct ArtifactsSnapshot: Codable {
            let hasApplicantProfile: Bool
            let hasSkeletonTimeline: Bool
            let enabledSections: Set<String>
            let experienceCardCount: Int
            let writingSampleCount: Int
        }
    }

    func createSnapshot() -> StateSnapshot {
        StateSnapshot(
            phase: phase,
            objectives: objectives,
            artifacts: StateSnapshot.ArtifactsSnapshot(
                hasApplicantProfile: artifacts.applicantProfile != nil,
                hasSkeletonTimeline: artifacts.skeletonTimeline != nil,
                enabledSections: artifacts.enabledSections,
                experienceCardCount: artifacts.experienceCards.count,
                writingSampleCount: artifacts.writingSamples.count
            ),
            wizardStep: currentWizardStep.rawValue,
            completedWizardSteps: Set(completedWizardSteps.map { $0.rawValue })
        )
    }

    func restoreFromSnapshot(_ snapshot: StateSnapshot) {
        phase = snapshot.phase
        objectives = snapshot.objectives

        // Note: Actual artifact content would be restored separately from persistent storage
        artifacts.enabledSections = snapshot.artifacts.enabledSections

        if let step = WizardStep(rawValue: snapshot.wizardStep) {
            currentWizardStep = step
        }

        completedWizardSteps = Set(snapshot.completedWizardSteps.compactMap { WizardStep(rawValue: $0) })

        Logger.info("📥 State restored from snapshot", category: .ai)
    }

    // MARK: - Event Subscription Setup

    /// Start listening to relevant events
    func startEventSubscriptions() {
        subscriptionTask?.cancel()

        subscriptionTask = Task { [weak self] in
            guard let self else { return }

            await withTaskGroup(of: Void.self) { group in
                // Subscribe to State topic for state updates
                group.addTask {
                    for await event in await self.eventBus.stream(topic: .state) {
                        await self.handleStateEvent(event)
                    }
                }

                // Subscribe to LLM topic for message tracking
                group.addTask {
                    for await event in await self.eventBus.stream(topic: .llm) {
                        await self.handleLLMEvent(event)
                    }
                }

                // Subscribe to Objective topic
                group.addTask {
                    for await event in await self.eventBus.stream(topic: .objective) {
                        await self.handleObjectiveEvent(event)
                    }
                }

                // Subscribe to Phase topic
                group.addTask {
                    for await event in await self.eventBus.stream(topic: .phase) {
                        await self.handlePhaseEvent(event)
                    }
                }

                // Subscribe to Timeline topic
                group.addTask {
                    for await event in await self.eventBus.stream(topic: .timeline) {
                        await self.handleTimelineEvent(event)
                    }
                }

                // Subscribe to Artifact topic
                group.addTask {
                    for await event in await self.eventBus.stream(topic: .artifact) {
                        await self.handleArtifactEvent(event)
                    }
                }
            }
        }

        Logger.info("📡 StateCoordinator subscribed to event streams", category: .ai)
    }

    // MARK: - Event Handlers

    private func handleStateEvent(_ event: OnboardingEvent) async {
        switch event {
        case .checkpointRequested:
            // Emit state snapshot for checkpointing
            await emitSnapshot(reason: "checkpoint")

        default:
            break
        }
    }

    private func handleLLMEvent(_ event: OnboardingEvent) async {
        switch event {
        case .llmUserMessageSent(let messageId, _):
            // Track message for state
            Logger.debug("StateCoordinator tracking user message: \(messageId)", category: .ai)

        case .llmSentToolResponseMessage(let messageId, _):
            // Track tool response
            Logger.debug("StateCoordinator tracking tool response: \(messageId)", category: .ai)

        case .llmStatus(let status):
            // Update processing state based on LLM status
            switch status {
            case .busy:
                isProcessing = true
            case .idle, .error:
                isProcessing = false
            }
            Logger.debug("StateCoordinator processing state: \(isProcessing)", category: .ai)

        default:
            break
        }
    }

    private func handleObjectiveEvent(_ event: OnboardingEvent) async {
        switch event {
        case .objectiveStatusRequested(let id, let response):
            // Respond with current objective status
            let status = objectives[id]?.status.rawValue
            response(status)

        case .objectiveStatusUpdateRequested(let id, let statusString, let source, let notes):
            // Parse status string to ObjectiveStatus enum
            guard let status = ObjectiveStatus(rawValue: statusString) else {
                Logger.warning("Invalid objective status requested: \(statusString)", category: .ai)
                return
            }

            // Update the objective status
            setObjectiveStatus(id, status: status, source: source, notes: notes)

            // The setObjectiveStatus method will emit .objectiveStatusChanged event

        default:
            break
        }
    }

    private func handlePhaseEvent(_ event: OnboardingEvent) async {
        switch event {
        case .phaseTransitionRequested(let from, let to, _):
            // Validate and apply phase transition
            if from == phase.rawValue {
                if let newPhase = InterviewPhase(rawValue: to) {
                    setPhase(newPhase)
                    // Emit confirmation
                    await emit(.phaseTransitionApplied(phase: newPhase.rawValue, timestamp: Date()))
                    // Emit updated allowed tools
                    await emitAllowedTools()
                }
            }

        default:
            break
        }
    }

    private func handleTimelineEvent(_ event: OnboardingEvent) async {
        switch event {
        case .timelineCardCreated(let card):
            createTimelineCard(card)
            // Emit confirmation event if needed
            Logger.info("📅 Timeline card created via event", category: .ai)

        case .timelineCardUpdated(let id, let fields):
            updateTimelineCard(id: id, fields: fields)
            Logger.info("📅 Timeline card \(id) updated via event", category: .ai)

        case .timelineCardDeleted(let id):
            deleteTimelineCard(id: id)
            Logger.info("📅 Timeline card \(id) deleted via event", category: .ai)

        case .timelineCardsReordered(let orderedIds):
            reorderTimelineCards(orderedIds: orderedIds)
            Logger.info("📅 Timeline cards reordered via event", category: .ai)

        default:
            break
        }
    }

    private func handleArtifactEvent(_ event: OnboardingEvent) async {
        switch event {
        case .artifactRecordProduced(let record):
            // Idempotent insert/update by id/sha
            upsertArtifactRecord(record)
            Logger.info("📦 Artifact record produced: \(record["id"].stringValue)", category: .ai)

        case .artifactRecordPersisted(let record):
            // Ensure persisted copy is reflected in state
            upsertArtifactRecord(record)
            Logger.info("📦 Artifact record persisted: \(record["id"].stringValue)", category: .ai)

        default:
            break
        }
    }

    // MARK: - Event Publications

    /// Emit state snapshot
    private func emitSnapshot(reason: String) async {
        let snapshot = createSnapshot()
        var snapshotJSON = JSON()

        // Convert snapshot to JSON (simplified for now)
        snapshotJSON["phase"].string = snapshot.phase.rawValue
        snapshotJSON["wizardStep"].string = snapshot.wizardStep

        let updatedKeys = ["phase", "wizardStep", "objectives"]
        await emit(.stateSnapshot(updatedKeys: updatedKeys, snapshot: snapshotJSON))
    }

    /// Get allowed tools for the current phase
    func getAllowedToolsForCurrentPhase() -> Set<String> {
        return phasePolicy.allowedTools[phase] ?? []
    }

    /// Emit allowed tools when phase changes
    private func emitAllowedTools() async {
        let tools = getAllowedToolsForCurrentPhase()
        await emit(.stateAllowedToolsUpdated(tools: tools))
    }

    func publishAllowedToolsNow() async {
        await emitAllowedTools()
    }

    /// When objectives change, emit update
    func updateObjectiveStatus(_ id: String, status: ObjectiveStatus, source: String = "system") async {
        guard var objective = objectives[id] else {
            Logger.warning("Objective not found: \(id)", category: .ai)
            return
        }

        let oldStatus = objective.status
        objective.status = status
        objective.source = source

        if status == .completed {
            objective.completedAt = Date()
        }

        objectives[id] = objective

        // Emit event
        await emit(.objectiveStatusChanged(
            id: id,
            status: status.rawValue,
            phase: phase.rawValue
        ))

        Logger.info("📊 Objective \(id): \(oldStatus.rawValue) → \(status.rawValue)", category: .ai)
    }
}
