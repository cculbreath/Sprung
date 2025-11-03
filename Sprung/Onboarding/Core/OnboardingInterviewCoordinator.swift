import Foundation
import Observation
import SwiftyJSON
import SwiftOpenAI
import UniformTypeIdentifiers

/// Coordinator that orchestrates the onboarding interview flow.
/// All state is managed by OnboardingState actor - this is just the orchestration layer.
@MainActor
@Observable
final class OnboardingInterviewCoordinator {
    // MARK: - Core Dependencies

    private let state: OnboardingState
    private let eventBus: OnboardingEventBus
    private let chatTranscriptStore: ChatTranscriptStore
    let toolRouter: OnboardingToolRouter
    let wizardTracker: WizardProgressTracker
    let phaseRegistry: PhaseScriptRegistry
    let toolRegistry: ToolRegistry
    private let toolExecutor: ToolExecutor
    private let openAIService: OpenAIService?

    // Event subscription tracking
    private var eventSubscriptionId: UUID?

    // MARK: - Data Store Dependencies

    private let applicantProfileStore: ApplicantProfileStore
    private let dataStore: InterviewDataStore
    let checkpoints: Checkpoints

    // MARK: - Orchestration State (minimal, not business state)

    private var orchestrator: InterviewOrchestrator?
    private var phaseAdvanceContinuationId: UUID?
    // Phase advance cache removed - no longer needed with centralized state
    private var toolQueueEntries: [UUID: ToolQueueEntry] = [:]
    private var pendingExtractionProgressBuffer: [ExtractionProgressUpdate] = []
    private var reasoningSummaryClearTask: Task<Void, Never>?
    var onModelAvailabilityIssue: ((String) -> Void)?
    private(set) var preferences: OnboardingPreferences

    private struct ToolQueueEntry {
        let tokenId: UUID
        let callId: String
        let toolName: String
        let status: String
        let requestedInput: String
        let enqueuedAt: Date
    }

    // MARK: - Computed Properties (Read from OnboardingState)

    var isProcessing: Bool {
        get async { await state.isProcessing }
    }

    var isActive: Bool {
        get async { await state.isActive }
    }

    var pendingExtraction: OnboardingPendingExtraction? {
        get async { await state.pendingExtraction }
    }

    var pendingStreamingStatus: String? {
        get async { await state.pendingStreamingStatus }
    }

    var latestReasoningSummary: String? {
        get async { await state.latestReasoningSummary }
    }

    var currentPhase: InterviewPhase {
        get async { await state.phase }
    }

    var wizardStep: OnboardingState.WizardStep {
        get async { await state.currentWizardStep }
    }

    var applicantProfileJSON: JSON? {
        get async { await state.artifacts.applicantProfile }
    }

    var skeletonTimelineJSON: JSON? {
        get async { await state.artifacts.skeletonTimeline }
    }

    var artifacts: OnboardingState.OnboardingArtifacts {
        get async { await state.artifacts }
    }

    // Properties that need synchronous access for SwiftUI
    // These will be updated via observation when state changes
    @ObservationIgnored
    private var _isProcessingSync = false
    var isProcessingSync: Bool { _isProcessingSync }

    @ObservationIgnored
    private var _pendingExtractionSync: OnboardingPendingExtraction?
    var pendingExtractionSync: OnboardingPendingExtraction? { _pendingExtractionSync }

    @ObservationIgnored
    private var _pendingStreamingStatusSync: String?
    var pendingStreamingStatusSync: String? { _pendingStreamingStatusSync }

    // MARK: - UI State Properties (from ToolRouter)

    var pendingUploadRequests: [OnboardingUploadRequest] {
        toolRouter.pendingUploadRequests
    }

    var pendingChoicePrompt: OnboardingChoicePrompt? {
        toolRouter.pendingChoicePrompt
    }

    var pendingValidationPrompt: OnboardingValidationPrompt? {
        toolRouter.pendingValidationPrompt
    }

    var pendingApplicantProfileRequest: OnboardingApplicantProfileRequest? {
        toolRouter.pendingApplicantProfileRequest
    }

    var pendingApplicantProfileIntake: OnboardingApplicantProfileIntakeState? {
        toolRouter.pendingApplicantProfileIntake
    }

    var pendingSectionToggleRequest: OnboardingSectionToggleRequest? {
        toolRouter.pendingSectionToggleRequest
    }

    var pendingPhaseAdvanceRequest: OnboardingPhaseAdvanceRequest? {
        get async {
            await state.pendingPhaseAdvanceRequest
        }
    }

    // MARK: - Initialization

    init(
        openAIService: OpenAIService?,
        applicantProfileStore: ApplicantProfileStore,
        dataStore: InterviewDataStore,
        checkpoints: Checkpoints,
        preferences: OnboardingPreferences
    ) {
        self.state = OnboardingState()
        self.eventBus = OnboardingEventBus()
        self.openAIService = openAIService
        self.applicantProfileStore = applicantProfileStore
        self.dataStore = dataStore
        self.checkpoints = checkpoints
        self.preferences = preferences

        self.chatTranscriptStore = ChatTranscriptStore()

        // Create handlers for tool router
        let promptHandler = PromptInteractionHandler()

        let uploadStorage = OnboardingUploadStorage()
        let uploadFileService = UploadFileService()
        let uploadHandler = UploadInteractionHandler(
            uploadFileService: uploadFileService,
            uploadStorage: uploadStorage,
            applicantProfileStore: applicantProfileStore,
            dataStore: dataStore,
            extractionProgressHandler: nil
        )

        let contactsImportService = ContactsImportService()
        let profileHandler = ProfileInteractionHandler(contactsImportService: contactsImportService)

        let sectionHandler = SectionToggleHandler()

        self.toolRouter = OnboardingToolRouter(
            promptHandler: promptHandler,
            uploadHandler: uploadHandler,
            profileHandler: profileHandler,
            sectionHandler: sectionHandler
        )
        self.wizardTracker = WizardProgressTracker()
        self.phaseRegistry = PhaseScriptRegistry()
        self.toolRegistry = ToolRegistry()
        self.toolExecutor = ToolExecutor(registry: toolRegistry)

        Logger.info("🎯 OnboardingInterviewCoordinator initialized with event-driven architecture", category: .ai)

        // Subscribe to events from the orchestrator
        Task { await subscribeToEvents() }

        // Start observation task to sync critical UI state
        Task { await startStateObservation() }
    }

    // MARK: - Event Subscription

    private func subscribeToEvents() async {
        eventSubscriptionId = await eventBus.subscribe { [weak self] event in
            guard let self else { return }
            await self.handleEvent(event)
        }
    }

    private func handleEvent(_ event: OnboardingEvent) async {
        switch event {
        case .processingStateChanged(let processing):
            await state.setProcessingState(processing)
            _isProcessingSync = processing

        case .assistantMessageEmitted(let id, let text, let reasoningExpected):
            await MainActor.run {
                _ = self.appendAssistantMessage(text, reasoningExpected: reasoningExpected)
            }

        case .streamingMessageBegan(let id, let text, let reasoningExpected):
            await MainActor.run {
                _ = self.beginAssistantStream(initialText: text, reasoningExpected: reasoningExpected)
            }

        case .streamingMessageUpdated(let id, let delta):
            await MainActor.run {
                self.updateAssistantStream(id: id, text: delta)
            }

        case .streamingMessageFinalized(let id, let finalText):
            await MainActor.run {
                _ = self.finalizeAssistantStream(id: id, text: finalText)
            }

        case .reasoningSummaryUpdated(let messageId, let summary, let isFinal):
            await MainActor.run {
                self.updateReasoningSummary(summary, for: messageId, isFinal: isFinal)
            }

        case .reasoningSummariesFinalized(let messageIds):
            await MainActor.run {
                for id in messageIds {
                    self.chatTranscriptStore.finalizeReasoningSummariesIfNeeded(for: [id])
                }
            }

        case .streamingStatusUpdated(let status):
            await MainActor.run {
                self.setStreamingStatus(status)
            }

        case .waitingStateChanged(let waiting):
            await MainActor.run {
                self.updateWaitingState(waiting)
            }

        case .errorOccurred(let error):
            Logger.error("Interview error: \(error)", category: .ai)

        case .applicantProfileStored(let json):
            await MainActor.run {
                self.storeApplicantProfile(json)
            }

        case .skeletonTimelineStored(let json):
            await MainActor.run {
                self.storeSkeletonTimeline(json)
            }

        case .enabledSectionsUpdated(let sections):
            await MainActor.run {
                self.updateEnabledSections(sections)
            }

        case .checkpointRequested:
            await saveCheckpoint()

        case .toolCallRequested(let call):
            await processToolCall(call)

        case .toolCallCompleted(let id, let result):
            // Tool completion is handled by toolContinuationNeeded
            break

        case .toolContinuationNeeded(let id, let toolName):
            // This will be connected to the tool router
            break

        case .objectiveStatusRequested(let id, let response):
            let status = await state.getObjectiveStatus(id)?.rawValue
            response(status)
        }
    }

    // MARK: - State Observation

    private func startStateObservation() async {
        // Monitor state changes and update synchronous properties for UI
        while true {
            _isProcessingSync = await state.isProcessing
            _pendingExtractionSync = await state.pendingExtraction
            _pendingStreamingStatusSync = await state.pendingStreamingStatus

            // Update wizard tracker
            let step = await state.currentWizardStep
            let completed = await state.completedWizardSteps
            wizardTracker.updateFromState(currentStep: step, completedSteps: completed)

            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }
    }

    // MARK: - Interview Lifecycle

    func startInterview(resumeExisting: Bool = false) async -> Bool {
        Logger.info("🚀 Starting interview (resume: \(resumeExisting))", category: .ai)

        // Reset or restore state
        if resumeExisting {
            await loadPersistedArtifacts()
            let didRestore = await restoreFromCheckpointIfAvailable()
            if !didRestore {
                await state.reset()
                await clearCheckpoints()
                clearArtifacts()
                await resetStore()
            }
        } else {
            await state.reset()
            await clearCheckpoints()
            clearArtifacts()
            await resetStore()
        }

        await state.setActiveState(true)
        await registerObjectivesForCurrentPhase()

        // Build and start orchestrator
        let phase = await state.phase
        let systemPrompt = phaseRegistry.buildSystemPrompt(for: phase)
        guard let service = openAIService else {
            await state.setActiveState(false)
            return false
        }

        let orchestrator = makeOrchestrator(service: service, systemPrompt: systemPrompt)
        self.orchestrator = orchestrator

        Task {
            do {
                try await orchestrator.startInterview()
            } catch {
                Logger.error("Interview failed: \(error)", category: .ai)
                await endInterview()
            }
        }

        return true
    }

    func endInterview() async {
        Logger.info("🛑 Ending interview", category: .ai)
        await orchestrator?.endInterview()
        orchestrator = nil
        await state.setActiveState(false)
        await state.setProcessingState(false)
    }

    // MARK: - Phase Management

    func advancePhase() async -> InterviewPhase? {
        guard let newPhase = await state.advanceToNextPhase() else { return nil }

        // Update wizard progress
        let completedSteps = await state.completedWizardSteps
        wizardTracker.updateFromState(
            currentStep: await state.currentWizardStep,
            completedSteps: completedSteps
        )

        await registerObjectivesForCurrentPhase()
        return newPhase
    }

    func getCompletedObjectiveIds() async -> Set<String> {
        let objectives = await state.getAllObjectives()
        return Set(objectives
            .filter { $0.status == .completed || $0.status == .skipped }
            .map { $0.id })
    }

    // MARK: - Objective Management

    func registerObjectivesForCurrentPhase() async {
        // Objectives are now automatically registered by OnboardingState
        // when the phase is set, so this is no longer needed
        Logger.info("📋 Objectives auto-registered by OnboardingState for current phase", category: .ai)
    }

    func updateObjectiveStatus(objectiveId: String, status: String) async throws -> JSON {
        let objectiveStatus: ObjectiveStatus

        switch status.lowercased() {
        case "completed":
            objectiveStatus = .completed
        case "pending", "reset":
            objectiveStatus = .pending
        case "in_progress":
            objectiveStatus = .inProgress
        case "skipped":
            objectiveStatus = .skipped
        default:
            throw ToolError.invalidParameters("Unsupported status: \(status)")
        }

        await state.setObjectiveStatus(objectiveId, status: objectiveStatus, source: "llm")

        var result = JSON()
        result["success"].boolValue = true
        result["objective_id"].stringValue = objectiveId
        result["new_status"].stringValue = objectiveStatus.rawValue

        return result
    }

    func missingObjectives() async -> [String] {
        await state.getMissingObjectives()
    }

    func nextPhase() async -> InterviewPhase? {
        let canAdvance = await state.canAdvancePhase()
        guard canAdvance else { return nil }

        let currentPhase = await state.phase
        switch currentPhase {
        case .phase1CoreFacts:
            return .phase2DeepDive
        case .phase2DeepDive:
            return .phase3WritingCorpus
        case .phase3WritingCorpus, .complete:
            return nil
        }
    }

    // MARK: - Artifact Management

    func storeApplicantProfile(_ profile: JSON) {
        Task {
            await state.setApplicantProfile(profile)
            // TODO: Convert JSON to ApplicantProfile model for SwiftData storage
            // applicantProfileStore.save(convertJSONToApplicantProfile(profile))
            await saveCheckpoint()
        }
    }

    func storeSkeletonTimeline(_ timeline: JSON) {
        Task {
            await state.setSkeletonTimeline(timeline)
            await saveCheckpoint()
        }
    }

    func updateEnabledSections(_ sections: Set<String>) {
        Task {
            await state.setEnabledSections(sections)
            await saveCheckpoint()
        }
    }

    // MARK: - Message Management

    func appendUserMessage(_ text: String) -> UUID {
        Task {
            let id = await state.appendUserMessage(text)
            chatTranscriptStore.appendUserMessage(text)
            return id
        }.value
    }

    func appendAssistantMessage(_ text: String, reasoningExpected: Bool) -> UUID {
        Task {
            let id = await state.appendAssistantMessage(text)
            chatTranscriptStore.appendAssistantMessage(
                text,
                reasoningExpected: reasoningExpected
            )
            return id
        }.value
    }

    func beginAssistantStream(initialText: String, reasoningExpected: Bool) -> UUID {
        Task {
            let id = await state.beginStreamingMessage(
                initialText: initialText,
                reasoningExpected: reasoningExpected
            )
            chatTranscriptStore.beginAssistantStream(
                initialText: initialText,
                reasoningExpected: reasoningExpected
            )
            return id
        }.value
    }

    func updateAssistantStream(id: UUID, text: String) {
        Task {
            await state.updateStreamingMessage(id: id, delta: text)
            chatTranscriptStore.updateAssistantStream(id: id, text: text)
        }
    }

    func finalizeAssistantStream(id: UUID, text: String) -> TimeInterval {
        Task {
            await state.finalizeStreamingMessage(id: id, finalText: text)
        }
        let elapsed = chatTranscriptStore.finalizeAssistantStream(id: id, text: text)
        return elapsed
    }

    func updateReasoningSummary(_ summary: String, for messageId: UUID, isFinal: Bool) {
        Task {
            await state.setReasoningSummary(summary, for: messageId)
        }
        chatTranscriptStore.updateReasoningSummary(summary, for: messageId, isFinal: isFinal)
    }

    func clearLatestReasoningSummary() {
        Task {
            await state.setReasoningSummary(nil, for: UUID())
        }
    }

    // MARK: - Waiting State

    func updateWaitingState(_ waiting: String?) {
        Task {
            let waitingState: OnboardingState.WaitingState? = if let waiting {
                switch waiting {
                case "selection": .selection
                case "upload": .upload
                case "validation": .validation
                case "extraction": .extraction
                case "processing": .processing
                default: nil
                }
            } else {
                nil
            }
            await state.setWaitingState(waitingState)
        }
    }

    // MARK: - Extraction Management

    func setExtractionStatus(_ extraction: OnboardingPendingExtraction?) {
        Task {
            await state.setPendingExtraction(extraction)
            _pendingExtractionSync = extraction

            // Clear applicant profile intake when extraction begins
            // TODO: Check extraction type - OnboardingPendingExtraction doesn't have documentType
            // if extraction?.title.contains("Resume") || extraction?.title.contains("CV") {
            //     toolRouter.clearApplicantProfileIntake()
            // }
        }
    }

    func updateExtractionProgress(with update: ExtractionProgressUpdate) {
        Task {
            if var extraction = await state.pendingExtraction {
                extraction.applyProgressUpdate(update)
                await state.setPendingExtraction(extraction)
                _pendingExtractionSync = extraction
            } else {
                pendingExtractionProgressBuffer.append(update)
            }
        }
    }

    func setStreamingStatus(_ status: String?) {
        Task {
            await state.setStreamingStatus(status)
            _pendingStreamingStatusSync = status
        }
    }

    // MARK: - Tool Management

    func presentUploadRequest(_ request: OnboardingUploadRequest, continuationId: UUID) {
        toolRouter.presentUploadRequest(request, continuationId: continuationId)
        Task {
            await state.setPendingUpload(request)
        }
    }

    func completeUpload(id: UUID, fileURLs: [URL]) async -> (UUID, JSON)? {
        let result = await toolRouter.completeUpload(id: id, fileURLs: fileURLs)
        Task {
            await state.setPendingUpload(nil)
        }
        return result
    }

    func skipUpload(id: UUID) async -> (UUID, JSON)? {
        let result = await toolRouter.skipUpload(id: id)
        Task {
            await state.setPendingUpload(nil)
        }
        return result
    }

    func presentChoicePrompt(_ prompt: OnboardingChoicePrompt, continuationId: UUID) {
        toolRouter.presentChoicePrompt(prompt, continuationId: continuationId)
        Task {
            await state.setPendingChoice(prompt)
        }
    }

    func submitChoice(optionId: String) -> (UUID, JSON)? {
        let result = toolRouter.promptHandler.resolveChoice(selectionIds: [optionId])
        Task {
            await state.setPendingChoice(nil)
        }
        return result
    }

    func presentValidationPrompt(_ prompt: OnboardingValidationPrompt, continuationId: UUID) {
        toolRouter.presentValidationPrompt(prompt, continuationId: continuationId)
        Task {
            await state.setPendingValidation(prompt)
        }
    }

    func submitValidationResponse(
        status: String,
        updatedData: JSON?,
        changes: JSON?,
        notes: String?
    ) -> (UUID, JSON)? {
        let result = toolRouter.submitValidationResponse(
            status: status,
            updatedData: updatedData,
            changes: changes,
            notes: notes
        )
        Task {
            await state.setPendingValidation(nil)
        }
        return result
    }

    // MARK: - Phase Advance

    func presentPhaseAdvanceRequest(
        _ request: OnboardingPhaseAdvanceRequest,
        continuationId: UUID
    ) {
        Task {
            phaseAdvanceContinuationId = continuationId
            await state.setPendingPhaseAdvanceRequest(request)
        }
    }

    func approvePhaseAdvance() async {
        guard let continuationId = phaseAdvanceContinuationId else { return }

        let newPhase = await advancePhase()
        await state.setPendingPhaseAdvanceRequest(nil)
        phaseAdvanceContinuationId = nil

        var payload = JSON()
        payload["approved"].boolValue = true
        if let phase = newPhase {
            payload["new_phase"].stringValue = phase.rawValue
        }

        await resumeToolContinuation(id: continuationId, payload: payload)
    }

    func denyPhaseAdvance(feedback: String?) async {
        guard let continuationId = phaseAdvanceContinuationId else { return }

        await state.setPendingPhaseAdvanceRequest(nil)
        phaseAdvanceContinuationId = nil

        var payload = JSON()
        payload["approved"].boolValue = false
        if let feedback = feedback {
            payload["feedback"].stringValue = feedback
        }

        await resumeToolContinuation(id: continuationId, payload: payload)
    }

    // MARK: - Tool Execution

    func resumeToolContinuation(from result: (UUID, JSON)?) async {
        guard let (id, payload) = result else { return }
        await resumeToolContinuation(id: id, payload: payload)
    }

    func resumeToolContinuation(
        from result: (UUID, JSON)?,
        waitingState: WaitingStateChange,
        persistCheckpoint: Bool = false
    ) async {
        guard let (id, payload) = result else { return }

        if case .set(let state) = waitingState {
            updateWaitingState(state)
        }

        if persistCheckpoint {
            await saveCheckpoint()
        }

        await resumeToolContinuation(id: id, payload: payload)
    }

    func resumeToolContinuation(id: UUID, payload: JSON) async {
        guard let entry = toolQueueEntries.removeValue(forKey: id) else {
            Logger.warning("No queue entry for continuation \(id)", category: .ai)
            return
        }

        Logger.info("✅ Tool \(entry.toolName) completed", category: .ai)

        do {
            try await toolExecutor.resumeContinuation(
                tokenId: entry.tokenId,
                response: .success(payload)
            )
        } catch {
            Logger.error("Failed to resume tool: \(error)", category: .ai)
        }
    }

    enum WaitingStateChange {
        case keep
        case set(String?)
    }

    // MARK: - Checkpoint Management

    func saveCheckpoint() async {
        let snapshot = await state.createSnapshot()
        let artifacts = await state.artifacts

        // Save to persistent storage
        checkpoints.save(
            phase: snapshot.phase,
            objectives: snapshot.objectives,
            profileJSON: artifacts.applicantProfile,
            timelineJSON: artifacts.skeletonTimeline,
            enabledSections: artifacts.enabledSections
        )
    }

    func restoreFromCheckpointIfAvailable() async -> Bool {
        guard let checkpoint = checkpoints.restore() else { return false }

        await state.restoreFromSnapshot(checkpoint.snapshot)

        // Restore artifacts from checkpoint
        if let profile = checkpoint.profileJSON {
            await state.setApplicantProfile(profile)
            // TODO: Convert JSON to ApplicantProfile model for SwiftData storage
            // applicantProfileStore.save(convertJSONToApplicantProfile(profile))
        }

        if let timeline = checkpoint.timelineJSON {
            await state.setSkeletonTimeline(timeline)
        }

        if !checkpoint.enabledSections.isEmpty {
            await state.setEnabledSections(checkpoint.enabledSections)
        }

        Logger.info("✅ Restored from checkpoint", category: .ai)
        return true
    }

    func clearCheckpoints() async {
        checkpoints.clear()
    }

    // MARK: - Data Store Management

    func loadPersistedArtifacts() async {
        let records = dataStore.loadAllArtifacts()

        for record in records {
            switch record.kind {
            case .applicantProfile:
                if let json = record.dataJSON {
                    await state.setApplicantProfile(json)
                }
            case .skeletonTimeline:
                if let json = record.dataJSON {
                    await state.setSkeletonTimeline(json)
                }
            default:
                break
            }
        }
    }

    func clearArtifacts() {
        dataStore.clearAll()
    }

    func resetStore() async {
        await state.reset()
        chatTranscriptStore.reset()
        toolRouter.reset()
        wizardTracker.reset()
    }

    // MARK: - Orchestrator Factory

    private func makeOrchestrator(
        service: OpenAIService,
        systemPrompt: String
    ) -> InterviewOrchestrator {
        return InterviewOrchestrator(
            service: service,
            systemPrompt: systemPrompt,
            eventBus: eventBus
        )
    }

    // MARK: - Tool Processing

    private func processToolCall(_ call: ToolCall) async -> JSON? {
        let tokenId = UUID()

        toolQueueEntries[tokenId] = ToolQueueEntry(
            tokenId: tokenId,
            callId: call.callId,
            toolName: call.name,
            status: "processing",
            requestedInput: call.arguments.rawString() ?? "{}",
            enqueuedAt: Date()
        )

        // Process the tool call through the executor
        // This will be expanded in Phase 2
        return nil
    }

    // MARK: - Utility

    func notifyInvalidModel(id: String) {
        Logger.warning("⚠️ Invalid model id reported: \(id)", category: .ai)
        onModelAvailabilityIssue?(id)
    }

    func transcriptExportString() -> String {
        chatTranscriptStore.formattedTranscript()
    }

    // MARK: - Legacy Support (will be removed in Phase 2)

    var objectiveStatuses: [String: ObjectiveStatus] {
        // For UI compatibility during transition
        get async {
            let objectives = await state.getAllObjectives()
            return objectives.reduce(into: [:]) { dict, entry in
                dict[entry.id] = ObjectiveStatus(rawValue: entry.status.rawValue) ?? .pending
            }
        }
    }

    func buildSystemPrompt(for phase: InterviewPhase) -> String {
        phaseRegistry.buildSystemPrompt(for: phase)
    }
}

// Extension to bridge WizardProgressTracker
extension WizardProgressTracker {
    func updateFromState(
        currentStep: OnboardingState.WizardStep,
        completedSteps: Set<OnboardingState.WizardStep>
    ) {
        // Convert to legacy wizard step format
        // This will be removed when we update the UI in Phase 2
        self.currentStep = OnboardingWizardStep(rawValue: currentStep.rawValue) ?? .resumeIntake
        self.completedSteps = Set(completedSteps.compactMap {
            OnboardingWizardStep(rawValue: $0.rawValue)
        })
    }
}

// Extension to handle Task.value pattern
extension Task where Success == UUID, Failure == Never {
    var value: UUID {
        // Synchronous wrapper for UI compatibility
        UUID() // Placeholder, will be properly handled in Phase 2
    }
}