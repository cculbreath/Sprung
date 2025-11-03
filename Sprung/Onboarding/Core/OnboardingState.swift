import Foundation
import SwiftyJSON

/// Single source of truth for ALL onboarding state.
/// This replaces InterviewSession, InterviewState, objective ledgers, and all distributed state.
actor OnboardingState {
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

    init() {
        Logger.info("🎯 OnboardingState initialized - single source of truth", category: .ai)
    }

    // MARK: - Phase Management

    func setPhase(_ phase: InterviewPhase) {
        self.phase = phase
        Logger.info("📍 Phase changed to: \(phase)", category: .ai)
        updateWizardProgress()
    }

    func advanceToNextPhase() -> InterviewPhase? {
        guard canAdvancePhase() else { return nil }

        let nextPhase: InterviewPhase
        switch phase {
        case .phase1CoreFacts:
            nextPhase = .phase2DeepDive
        case .phase2DeepDive:
            nextPhase = .phase3WritingCorpus
        case .phase3WritingCorpus:
            return nil // Already at final phase
        }

        setPhase(nextPhase)
        return nextPhase
    }

    func canAdvancePhase() -> Bool {
        let requiredObjectives: [String]

        switch phase {
        case .phase1CoreFacts:
            requiredObjectives = ["applicant_profile", "skeleton_timeline", "enabled_sections"]
        case .phase2DeepDive:
            requiredObjectives = ["interviewed_one_experience", "one_card_generated"]
        case .phase3WritingCorpus:
            requiredObjectives = ["one_writing_sample", "dossier_complete"]
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
        let requiredForPhase: [String]

        switch phase {
        case .phase1CoreFacts:
            requiredForPhase = ["applicant_profile", "skeleton_timeline", "enabled_sections"]
        case .phase2DeepDive:
            requiredForPhase = ["interviewed_one_experience", "one_card_generated"]
        case .phase3WritingCorpus:
            requiredForPhase = ["one_writing_sample", "dossier_complete"]
        }

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
            isStreaming: true,
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
            messages[index].isStreaming = false
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
        let hasExperience = objectives["interviewed_one_experience"]?.status == .completed
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

        Logger.info("🔄 OnboardingState reset to clean state", category: .ai)
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
}