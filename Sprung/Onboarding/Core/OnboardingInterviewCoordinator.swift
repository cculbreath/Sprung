import Foundation
import Observation
import SwiftyJSON
import SwiftOpenAI

@MainActor
@Observable
final class OnboardingInterviewCoordinator {
    private let chatTranscriptStore: ChatTranscriptStore
    let toolRouter: OnboardingToolRouter // Central router that owns handler state surfaced to SwiftUI
    let dataStoreManager: OnboardingDataStoreManager
    let checkpointManager: OnboardingCheckpointManager
    let wizardTracker: WizardProgressTracker
    let phaseRegistry: PhaseScriptRegistry
    private let interviewState: InterviewState
    let toolRegistry: ToolRegistry
    private let toolExecutor: ToolExecutor
    private let openAIService: OpenAIService?

    private(set) var preferences: OnboardingPreferences
    private(set) var isProcessing = false
    private(set) var isActive = false
    private(set) var pendingExtraction: OnboardingPendingExtraction?
    private(set) var lastError: String?
    private(set) var pendingPhaseAdvanceRequest: OnboardingPhaseAdvanceRequest?
    private var orchestrator: InterviewOrchestrator?
    private var phaseAdvanceContinuationId: UUID?
    private var phaseAdvanceBlockCache: PhaseAdvanceBlockCache?
    private var lastLedgerSignature: String?
    private lazy var ledgerDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    // MARK: - Objective Ledger

    private func phasesThrough(_ phase: InterviewPhase) -> [InterviewPhase] {
        switch phase {
        case .phase1CoreFacts:
            return [.phase1CoreFacts]
        case .phase2DeepDive:
            return [.phase1CoreFacts, .phase2DeepDive]
        case .phase3WritingCorpus:
            return [.phase1CoreFacts, .phase2DeepDive, .phase3WritingCorpus]
        case .complete:
            return [.phase1CoreFacts, .phase2DeepDive, .phase3WritingCorpus]
        }
    }

    func registerObjectivesForCurrentPhase() async {
        let session = await interviewState.currentSession()
        for phase in phasesThrough(session.phase) {
            await interviewState.registerObjectives(ObjectiveCatalog.objectives(for: phase))
        }
        lastLedgerSignature = nil
    }

    func updateObjectiveStatus(
        _ id: String,
        status: ObjectiveStatus,
        source: String,
        details: [String: String]? = nil
    ) {
        Task {
            await interviewState.updateObjective(
                id: id,
                status: status,
                source: source,
                details: details
            )
        }
        lastLedgerSignature = nil
    }

    func ledgerStatusMessage() async -> String? {
        let snapshot = await interviewState.ledgerSnapshot()
        guard snapshot.signature != lastLedgerSignature else {
            return nil
        }
        let summary = snapshot.formattedSummary(dateFormatter: ledgerDateFormatter)
        guard !summary.isEmpty else {
            lastLedgerSignature = snapshot.signature
            return nil
        }
        lastLedgerSignature = snapshot.signature
        return "Objective update: \(summary)"
    }

    init(
        chatTranscriptStore: ChatTranscriptStore,
        toolRouter: OnboardingToolRouter,
        dataStoreManager: OnboardingDataStoreManager,
        checkpointManager: OnboardingCheckpointManager,
        wizardTracker: WizardProgressTracker,
        phaseRegistry: PhaseScriptRegistry,
        interviewState: InterviewState,
        openAIService: OpenAIService?,
        preferences: OnboardingPreferences = OnboardingPreferences()
    ) {
        self.chatTranscriptStore = chatTranscriptStore
        self.toolRouter = toolRouter
        self.dataStoreManager = dataStoreManager
        self.checkpointManager = checkpointManager
        self.wizardTracker = wizardTracker
        self.phaseRegistry = phaseRegistry
        self.interviewState = interviewState
        self.openAIService = openAIService
        self.toolRegistry = ToolRegistry()
        self.toolExecutor = ToolExecutor(registry: toolRegistry)
        self.preferences = preferences
    }

    var messages: [OnboardingMessage] {
        chatTranscriptStore.messages
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

    var pendingUploadRequests: [OnboardingUploadRequest] {
        toolRouter.pendingUploadRequests
    }

    var uploadedItems: [OnboardingUploadedItem] {
        toolRouter.uploadedItems
    }

    var pendingSectionToggleRequest: OnboardingSectionToggleRequest? {
        toolRouter.pendingSectionToggleRequest
    }

    var wizardStep: OnboardingWizardStep { wizardTracker.currentStep }

    var completedWizardSteps: Set<OnboardingWizardStep> { wizardTracker.completedSteps }

    var wizardStepStatuses: [OnboardingWizardStep: OnboardingWizardStepStatus] { wizardTracker.stepStatuses }

    // MARK: - Chat helpers

    func appendUserMessage(_ text: String) {
        chatTranscriptStore.appendUserMessage(text)
    }

    @discardableResult
    func appendAssistantMessage(_ text: String) -> UUID {
        chatTranscriptStore.appendAssistantMessage(text)
    }

    @discardableResult
    func beginAssistantStream(initialText: String = "") -> UUID {
        chatTranscriptStore.beginAssistantStream(initialText: initialText)
    }

    func updateAssistantStream(id: UUID, text: String) {
        chatTranscriptStore.updateAssistantStream(id: id, text: text)
    }

    func finalizeAssistantStream(id: UUID, text: String) -> TimeInterval {
        chatTranscriptStore.finalizeAssistantStream(id: id, text: text)
    }

    func updateReasoningSummary(_ summary: String, for messageId: UUID, isFinal: Bool) {
        chatTranscriptStore.updateReasoningSummary(summary, for: messageId, isFinal: isFinal)
    }

    func appendSystemMessage(_ text: String) {
        chatTranscriptStore.appendSystemMessage(text)
    }

    func resetTranscript() {
        chatTranscriptStore.reset()
        toolRouter.reset()
    }

    // MARK: - Preferences

    func setPreferredDefaults(modelId: String, backend: LLMFacade.Backend, webSearchAllowed: Bool) {
        preferences.preferredModelId = modelId
        preferences.preferredBackend = backend
        preferences.allowWebSearch = webSearchAllowed
    }

    func setWritingAnalysisConsent(_ allowed: Bool) {
        preferences.allowWritingAnalysis = allowed
    }

    // MARK: - Wizard Progress

    func setWizardStep(_ step: OnboardingWizardStep) {
        wizardTracker.setStep(step)
    }

    func updateWaitingState(_ waiting: InterviewSession.Waiting?) {
        wizardTracker.updateWaitingState(waiting)
    }

    func syncWizardProgress(from session: InterviewSession) {
        wizardTracker.syncProgress(from: session)
    }

    func resetWizard() {
        wizardTracker.reset()
    }

    func buildSystemPrompt(for session: InterviewSession) -> String {
        phaseRegistry.buildSystemPrompt(for: session)
    }

    // MARK: - Session & Objectives

    func currentSession() async -> InterviewSession {
        await interviewState.currentSession()
    }

    func missingObjectives() async -> [String] {
        await interviewState.missingObjectives()
    }

    func nextPhase() async -> InterviewPhase? {
        await interviewState.nextPhase()
    }

    func advancePhase() async -> InterviewPhase? {
        await interviewState.advanceToNextPhase()
        let session = await interviewState.currentSession()
        applyWizardProgress(from: session)
        phaseAdvanceBlockCache = nil
        await registerObjectivesForCurrentPhase()
        return session.phase
    }

    func updateObjectiveStatus(objectiveId: String, status: String) async throws -> JSON {
        let normalized = status.lowercased()
        let ledgerStatus: ObjectiveStatus
        switch normalized {
        case "completed":
            await interviewState.completeObjective(objectiveId)
            ledgerStatus = .completed
        case "pending", "reset":
            await interviewState.resetObjective(objectiveId)
            ledgerStatus = .pending
        default:
            throw ToolError.invalidParameters("Unsupported status: \(status)")
        }

        updateObjectiveStatus(
            objectiveId,
            status: ledgerStatus,
            source: "llm_proposed",
            details: ["requested_status": normalized]
        )

        let session = await interviewState.currentSession()
        applyWizardProgress(from: session)
        phaseAdvanceBlockCache = nil

        var response = JSON()
        response["status"].string = "ok"
        response["objective"].string = objectiveId
        response["state"].string = normalized == "completed" ? "completed" : "pending"
        return response
    }

    // MARK: - Checkpoints

    func hasRestorableCheckpoint() async -> Bool {
        await checkpointManager.hasRestorableCheckpoint()
    }

    func restoreCheckpoint() async -> CheckpointSnapshot? {
        await checkpointManager.restoreLatest()
    }

    func saveCheckpoint(
        applicantProfile: JSON?,
        skeletonTimeline: JSON?,
        enabledSections: [String]?
    ) async {
        await checkpointManager.save(
            applicantProfile: applicantProfile,
            skeletonTimeline: skeletonTimeline,
            enabledSections: enabledSections
        )
    }

    func clearCheckpoints() async {
        await checkpointManager.clear()
    }

    // MARK: - Choice Prompts

    func presentChoicePrompt(_ prompt: OnboardingChoicePrompt, continuationId: UUID) {
        toolRouter.presentChoicePrompt(prompt, continuationId: continuationId)
    }

    func clearChoicePrompt(continuationId: UUID) {
        toolRouter.clearChoicePrompt(continuationId: continuationId)
    }

    func resolveChoice(selectionIds: [String]) -> (UUID, JSON)? {
        toolRouter.resolveChoice(selectionIds: selectionIds)
    }

    func cancelChoicePrompt(reason: String) -> (UUID, JSON)? {
        toolRouter.cancelChoicePrompt(reason: reason)
    }

    // MARK: - Validation Prompts

    func presentValidationPrompt(_ prompt: OnboardingValidationPrompt, continuationId: UUID) {
        toolRouter.presentValidationPrompt(prompt, continuationId: continuationId)
    }

    func clearValidationPrompt(continuationId: UUID) {
        toolRouter.clearValidationPrompt(continuationId: continuationId)
    }

    func submitValidationResponse(
        status: String,
        updatedData: JSON?,
        changes: JSON?,
        notes: String?
    ) -> (UUID, JSON)? {
        toolRouter.submitValidationResponse(
            status: status,
            updatedData: updatedData,
            changes: changes,
            notes: notes
        )
    }

    func cancelValidation(reason: String) -> (UUID, JSON)? {
        toolRouter.cancelValidation(reason: reason)
    }

    // MARK: - Applicant Profile Validation

    func presentApplicantProfileRequest(_ request: OnboardingApplicantProfileRequest, continuationId: UUID) {
        toolRouter.presentApplicantProfileRequest(request, continuationId: continuationId)
    }

    func clearApplicantProfileRequest(continuationId: UUID) {
        toolRouter.clearApplicantProfileRequest(continuationId: continuationId)
    }

    func resolveApplicantProfile(with draft: ApplicantProfileDraft) -> (UUID, JSON)? {
        toolRouter.resolveApplicantProfile(with: draft)
    }

    func rejectApplicantProfile(reason: String) -> (UUID, JSON)? {
        toolRouter.rejectApplicantProfile(reason: reason)
    }

    // MARK: - Applicant Profile Intake

    func presentApplicantProfileIntake(continuationId: UUID) {
        toolRouter.presentApplicantProfileIntake(continuationId: continuationId)
    }

    func resetApplicantProfileIntakeToOptions() {
        toolRouter.resetApplicantProfileIntakeToOptions()
    }

    func beginApplicantProfileManualEntry() {
        toolRouter.beginApplicantProfileManualEntry()
    }

    func beginApplicantProfileURL() {
        toolRouter.beginApplicantProfileURL()
    }

    func beginApplicantProfileUpload() -> (request: OnboardingUploadRequest, continuationId: UUID)? {
        toolRouter.beginApplicantProfileUpload()
    }

    func beginApplicantProfileContactsFetch() {
        toolRouter.beginApplicantProfileContactsFetch()
    }

    func submitApplicantProfileURL(_ urlString: String) -> (UUID, JSON)? {
        toolRouter.submitApplicantProfileURL(urlString)
    }

    func completeApplicantProfileDraft(_ draft: ApplicantProfileDraft, source: OnboardingApplicantProfileIntakeState.Source) -> (UUID, JSON)? {
        toolRouter.completeApplicantProfileDraft(draft, source: source)
    }

    func cancelApplicantProfileIntake(reason: String) -> (UUID, JSON)? {
        toolRouter.cancelApplicantProfileIntake(reason: reason)
    }

    // MARK: - Uploads

    func presentUploadRequest(_ request: OnboardingUploadRequest, continuationId: UUID) {
        toolRouter.presentUploadRequest(request, continuationId: continuationId)
    }

    func completeUpload(id: UUID, fileURLs: [URL]) async -> (UUID, JSON)? {
        await toolRouter.completeUpload(id: id, fileURLs: fileURLs)
    }

    func completeUpload(id: UUID, link: URL) async -> (UUID, JSON)? {
        await toolRouter.completeUpload(id: id, link: link)
    }

    func skipUpload(id: UUID) async -> (UUID, JSON)? {
        await toolRouter.skipUpload(id: id)
    }

    // MARK: - Section Toggle Handling

    func presentSectionToggle(_ request: OnboardingSectionToggleRequest, continuationId: UUID) {
        toolRouter.presentSectionToggle(request, continuationId: continuationId)
    }

    func resolveSectionToggle(enabled: [String]) -> (UUID, JSON)? {
        if let result = toolRouter.resolveSectionToggle(enabled: enabled) {
            dataStoreManager.updateEnabledSections(enabled)
            return result
        }
        return nil
    }

    func rejectSectionToggle(reason: String) -> (UUID, JSON)? {
        toolRouter.rejectSectionToggle(reason: reason)
    }

    // MARK: - Continuations

    func resumeToolContinuation(id: UUID, payload: JSON) async {
        isProcessing = true
        await orchestrator?.resumeToolContinuation(id: id, payload: payload)
    }

    func setProcessingState(_ processing: Bool) {
        isProcessing = processing
    }

    // MARK: - Capabilities

    func capabilityManifest(
        pendingExtraction: OnboardingPendingExtraction?,
        knowledgeCardAvailable: Bool
    ) -> JSON {
        let toolStatuses = toolRouter.statusSnapshot

        var manifest = JSON()
        manifest["version"].int = 2

        var toolsJSON = JSON()
        toolsJSON["capabilities_describe"]["status"].string = OnboardingToolStatus.ready.rawValue

        toolsJSON[OnboardingToolIdentifier.getUserOption.rawValue]["status"].string =
            toolStatuses.status(for: .getUserOption).rawValue

        var uploadJSON = JSON()
        uploadJSON["status"].string = toolStatuses.status(for: .getUserUpload).rawValue
        uploadJSON["accepts"] = JSON(["pdf", "docx", "txt", "md"])
        uploadJSON["max_bytes"].int = 10 * 1024 * 1024
        toolsJSON[OnboardingToolIdentifier.getUserUpload.rawValue] = uploadJSON

        var contactsJSON = JSON()
        contactsJSON["status"].string = toolStatuses.status(for: .getMacOSContactCard).rawValue
        toolsJSON[OnboardingToolIdentifier.getMacOSContactCard.rawValue] = contactsJSON

        var profileJSON = JSON()
        profileJSON["status"].string = toolStatuses.status(for: .getApplicantProfile).rawValue
        profileJSON["paths"] = JSON(["upload", "url", "contacts", "manual"])
        toolsJSON[OnboardingToolIdentifier.getApplicantProfile.rawValue] = profileJSON

        var extractionJSON = JSON()
        extractionJSON["status"].string = pendingExtraction == nil ? OnboardingToolStatus.ready.rawValue : OnboardingToolStatus.processing.rawValue
        extractionJSON["supports"] = JSON(["pdf", "docx"])
        extractionJSON["ocr"].bool = true
        extractionJSON["layout_preservation"].bool = true
        extractionJSON["return_types"] = JSON(["artifact_record", "applicant_profile", "skeleton_timeline"])
        toolsJSON["extract_document"] = extractionJSON

        toolsJSON[OnboardingToolIdentifier.submitForValidation.rawValue]["status"].string =
            toolStatuses.status(for: .submitForValidation).rawValue
        toolsJSON[OnboardingToolIdentifier.submitForValidation.rawValue]["data_types"] = JSON([
            "applicant_profile",
            "skeleton_timeline",
            "experience",
            "education",
            "knowledge_card"
        ])

        toolsJSON["persist_data"]["status"].string = OnboardingToolStatus.ready.rawValue
        toolsJSON["persist_data"]["data_types"] = JSON([
            "applicant_profile",
            "skeleton_timeline",
            "knowledge_card",
            "artifact_record",
            "writing_sample",
            "candidate_dossier"
        ])

        toolsJSON["set_objective_status"]["status"].string = OnboardingToolStatus.ready.rawValue
        toolsJSON["next_phase"]["status"].string = OnboardingToolStatus.ready.rawValue

        let knowledgeCardStatus = knowledgeCardAvailable ? OnboardingToolStatus.ready.rawValue : OnboardingToolStatus.locked.rawValue
        toolsJSON["generate_knowledge_card"]["status"].string = knowledgeCardStatus

        manifest["tools"] = toolsJSON
        return manifest
    }

    // MARK: - Phase Advance Handling

    func hasActivePhaseAdvanceRequest() -> Bool {
        pendingPhaseAdvanceRequest != nil
    }

    func currentPhaseAdvanceAwaitingPayload() -> JSON? {
        guard let request = pendingPhaseAdvanceRequest else { return nil }
        return buildAwaitingPayload(for: request)
    }

    func cachedPhaseAdvanceBlockedResponse(missing: [String], overrides: [String]) async -> JSON? {
        guard let cache = phaseAdvanceBlockCache else { return nil }
        return cache.matches(missing: missing, overrides: overrides) ? cache.response : nil
    }

    func cachePhaseAdvanceBlockedResponse(missing: [String], overrides: [String], response: JSON) async {
        phaseAdvanceBlockCache = PhaseAdvanceBlockCache(
            missing: missing,
            overrides: overrides,
            response: response
        )
    }

    func logPhaseAdvanceEvent(
        status: String,
        overrides: [String],
        missing: [String],
        reason: String?,
        userDecision: String?,
        advancedTo: InterviewPhase?,
        currentPhase: InterviewPhase
    ) async {
        var metadata: [String: String] = [
            "status": status,
            "overrides": overrides.joined(separator: ","),
            "missing": missing.joined(separator: ","),
            "current_phase": currentPhase.rawValue
        ]
        if let reason, !reason.isEmpty {
            metadata["reason"] = reason
        }
        if let userDecision {
            metadata["decision"] = userDecision
        }
        if let advancedTo {
            metadata["advanced_to"] = advancedTo.rawValue
            metadata["next_phase"] = advancedTo.rawValue
        }
        Logger.info("🎯 Phase advance \(status)", category: .ai, metadata: metadata)
    }

    func presentPhaseAdvanceRequest(_ request: OnboardingPhaseAdvanceRequest, continuationId: UUID) {
        phaseAdvanceBlockCache = nil
        pendingPhaseAdvanceRequest = request
        phaseAdvanceContinuationId = continuationId
        isProcessing = false
        updateWaitingState(.validation)
        Task { [request] in
            await logPhaseAdvanceEvent(
                status: "awaiting_user_approval",
                overrides: request.proposedOverrides,
                missing: request.missingObjectives,
                reason: request.reason,
                userDecision: nil,
                advancedTo: request.nextPhase,
                currentPhase: request.currentPhase
            )
        }
    }

    func approvePhaseAdvanceRequest() async {
        guard let continuationId = phaseAdvanceContinuationId else { return }
        let request = pendingPhaseAdvanceRequest
        pendingPhaseAdvanceRequest = nil
        phaseAdvanceContinuationId = nil
        updateWaitingState(nil)
        isProcessing = true

        let newPhase = await advancePhase()
        var payload = JSON()
        payload["status"].string = "approved"
        if let newPhase {
            payload["advanced_to"].string = newPhase.rawValue
        }

        await persistCheckpoint()
        if let request {
            await logPhaseAdvanceEvent(
                status: "approved",
                overrides: request.proposedOverrides,
                missing: request.missingObjectives,
                reason: request.reason,
                userDecision: "approved",
                advancedTo: newPhase,
                currentPhase: request.currentPhase
            )
        }
        await orchestrator?.resumeToolContinuation(id: continuationId, payload: payload)
    }

    func denyPhaseAdvanceRequest(feedback: String?) async {
        guard let continuationId = phaseAdvanceContinuationId else { return }
        let request = pendingPhaseAdvanceRequest
        pendingPhaseAdvanceRequest = nil
        phaseAdvanceContinuationId = nil
        updateWaitingState(nil)
        isProcessing = true

        var payload = JSON()
        if let feedback, !feedback.isEmpty {
            payload["status"].string = "denied_with_feedback"
            payload["feedback"].string = feedback
        } else {
            payload["status"].string = "denied"
        }

        phaseAdvanceBlockCache = PhaseAdvanceBlockCache(
            missing: request?.missingObjectives ?? [],
            overrides: request?.proposedOverrides ?? [],
            response: payload
        )
        if let request {
            let decision = payload["status"].stringValue
            await logPhaseAdvanceEvent(
                status: decision,
                overrides: request.proposedOverrides,
                missing: request.missingObjectives,
                reason: request.reason,
                userDecision: decision,
                advancedTo: nil,
                currentPhase: request.currentPhase
            )
        }
        await orchestrator?.resumeToolContinuation(id: continuationId, payload: payload)
    }

    // MARK: - Interview Lifecycle

    func startInterview(modelId: String, backend: LLMFacade.Backend, resumeExisting: Bool) async {
        guard backend == .openAI else {
            updateLastError("Only the OpenAI backend is supported for onboarding interviews.")
            return
        }

        guard let openAIService else {
            updateLastError("OpenAI API key is not configured.")
            return
        }

        guard isActive == false else {
            Logger.debug("startInterview called while interview is already active; ignoring request.")
            return
        }

        updateLastError(nil)
        resetTransientState()

        let restoredFromCheckpoint = await prepareStateForStart(resumeExisting: resumeExisting)
        await registerObjectivesForCurrentPhase()

        let currentSession = await interviewState.currentSession()
        let prompt = buildSystemPrompt(for: currentSession)
        orchestrator = makeOrchestrator(service: openAIService, systemPrompt: prompt)
        isActive = true
        isProcessing = true

        if !restoredFromCheckpoint {
            wizardTracker.setStep(.resumeIntake)
            Logger.debug("[WizardStep] Set to .resumeIntake (fresh start)")
        } else {
            Logger.debug("[WizardStep] After checkpoint restore: \(wizardStep)")
        }

        await orchestrator?.startInterview(modelId: modelId)
    }

    func sendMessage(_ text: String) async {
        guard isActive else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        appendUserMessage(trimmed)
        await orchestrator?.sendUserMessage(trimmed)
    }

    func resetInterview() {
        resetTransientState()
        updateLastError(nil)
        orchestrator = nil

        Task { await interviewState.restore(from: InterviewSession()) }
        Task { await loadPersistedArtifacts() }
        Task { await clearCheckpoints() }
    }

    func setExtractionStatus(_ status: OnboardingPendingExtraction?) {
        pendingExtraction = status
    }

    func updateLastError(_ message: String?) {
        lastError = message
    }

    func recordError(_ message: String) {
        lastError = message
        appendSystemMessage("⚠️ \(message)")
    }

    func loadPersistedArtifacts() async {
        await dataStoreManager.loadPersistedArtifacts()
    }

    // MARK: - Internal Helpers

    private func prepareStateForStart(resumeExisting: Bool) async -> Bool {
        let restored: Bool
        if resumeExisting {
            await dataStoreManager.loadPersistedArtifacts()
            await interviewState.restore(from: InterviewSession())
            let didRestore = await restoreFromCheckpointIfAvailable()
            if !didRestore {
                await clearCheckpoints()
                dataStoreManager.clearArtifacts()
                await dataStoreManager.resetStore()
            }
            restored = didRestore
        } else {
            await clearCheckpoints()
            dataStoreManager.clearArtifacts()
            await dataStoreManager.resetStore()
            await interviewState.restore(from: InterviewSession())
            restored = false
        }
        return restored
    }

    private func restoreFromCheckpointIfAvailable() async -> Bool {
        guard let snapshot = await restoreCheckpoint() else {
            return false
        }

        let (session, profileJSON, timelineJSON, enabledSections, _) = snapshot
        await interviewState.restore(from: session)
        applyWizardProgress(from: session)
        lastLedgerSignature = nil

        if let profileJSON {
            await storeApplicantProfile(profileJSON)
        }
        if let timelineJSON {
            await storeSkeletonTimeline(timelineJSON)
        }
        if let enabledSections, !enabledSections.isEmpty {
            dataStoreManager.updateEnabledSections(enabledSections)
        }

        isProcessing = false
        return true
    }

    private func applyWizardProgress(from session: InterviewSession) {
        syncWizardProgress(from: session)
    }

    private func makeOrchestrator(service: OpenAIService, systemPrompt: String) -> InterviewOrchestrator {
        let callbacks = InterviewOrchestrator.Callbacks(
            updateProcessingState: { [weak self] processing in
                guard let self else { return }
                await MainActor.run { self.isProcessing = processing }
            },
            emitAssistantMessage: { [weak self] text in
                guard let self else { return UUID() }
                return await MainActor.run { self.appendAssistantMessage(text) }
            },
            beginStreamingAssistantMessage: { [weak self] initial in
                guard let self else { return UUID() }
                return await MainActor.run { self.beginAssistantStream(initialText: initial) }
            },
            updateStreamingAssistantMessage: { [weak self] id, text in
                guard let self else { return }
                await MainActor.run { self.updateAssistantStream(id: id, text: text) }
            },
            finalizeStreamingAssistantMessage: { [weak self] id, text in
                guard let self else { return }
                await MainActor.run { self.finalizeAssistantStream(id: id, text: text) }
            },
            updateReasoningSummary: { [weak self] messageId, summary, isFinal in
                guard let self else { return }
                await MainActor.run { self.updateReasoningSummary(summary, for: messageId, isFinal: isFinal) }
            },
            handleWaitingState: { [weak self] waiting in
                guard let self else { return }
                await MainActor.run { self.updateWaitingState(waiting) }
            },
            handleError: { [weak self] message in
                guard let self else { return }
                await MainActor.run { self.recordError(message) }
            },
            storeApplicantProfile: { [weak self] json in
                guard let self else { return }
                await self.storeApplicantProfile(json)
            },
            storeSkeletonTimeline: { [weak self] json in
                guard let self else { return }
                await self.storeSkeletonTimeline(json)
            },
            storeArtifactRecord: { [weak self] artifact in
                guard let self else { return }
                await self.storeArtifactRecord(artifact)
            },
            storeKnowledgeCard: { [weak self] card in
                guard let self else { return }
                await self.storeKnowledgeCard(card)
            },
            setExtractionStatus: { [weak self] status in
                guard let self else { return }
                await MainActor.run { self.setExtractionStatus(status) }
            },
            persistCheckpoint: { [weak self] in
                guard let self else { return }
                await self.persistCheckpoint()
            },
            ledgerStatusMessage: { [weak self] in
                guard let self else { return nil }
                return await self.ledgerStatusMessage()
            }
        )

        return InterviewOrchestrator(
            client: service,
            state: interviewState,
            toolExecutor: toolExecutor,
            callbacks: callbacks,
            systemPrompt: systemPrompt
        )
    }

    private func storeApplicantProfile(_ json: JSON) async {
        dataStoreManager.storeApplicantProfile(json)
        await persistCheckpoint()
        updateObjectiveStatus(
            "applicant_profile",
            status: .completed,
            source: "system_persist",
            details: ["reason": "persisted"]
        )
    }

    private func storeSkeletonTimeline(_ json: JSON) async {
        dataStoreManager.storeSkeletonTimeline(json)
        await persistCheckpoint()
        updateObjectiveStatus(
            "skeleton_timeline",
            status: .completed,
            source: "system_persist",
            details: ["reason": "persisted"]
        )
    }

    private func storeArtifactRecord(_ artifact: JSON) async {
        guard artifact != .null else { return }
        dataStoreManager.storeArtifactRecord(artifact)
    }

    private func storeKnowledgeCard(_ card: JSON) async {
        guard card != .null else { return }
        dataStoreManager.storeKnowledgeCard(card)
        await persistCheckpoint()
    }

    func persistCheckpoint() async {
        let sections = dataStoreManager.artifacts.enabledSections
        await saveCheckpoint(
            applicantProfile: dataStoreManager.applicantProfileJSON,
            skeletonTimeline: dataStoreManager.skeletonTimelineJSON,
            enabledSections: sections.isEmpty ? nil : sections
        )
    }

    private func resetTransientState() {
        resetTranscript()
        toolRouter.reset()
        wizardTracker.reset()
        dataStoreManager.clearArtifacts()
        pendingExtraction = nil
        pendingPhaseAdvanceRequest = nil
        phaseAdvanceContinuationId = nil
        phaseAdvanceBlockCache = nil
        isProcessing = false
        isActive = false
        updateWaitingState(nil)
        lastLedgerSignature = nil
        Task { await self.interviewState.resetLedger() }
    }

    private func buildAwaitingPayload(for request: OnboardingPhaseAdvanceRequest) -> JSON {
        var json = JSON()
        json["status"].string = "awaiting_user_approval"
        json["current_phase"].string = request.currentPhase.rawValue
        json["next_phase"].string = request.nextPhase.rawValue
        json["missing_objectives"] = JSON(request.missingObjectives)
        json["proposed_overrides"] = JSON(request.proposedOverrides)
        if let reason = request.reason, !reason.isEmpty {
            json["reason"].string = reason
        }
        return json
    }

    private struct PhaseAdvanceBlockCache {
        let missing: [String]
        let overrides: [String]
        let response: JSON

        func matches(missing: [String], overrides: [String]) -> Bool {
            missing.sorted() == self.missing.sorted() &&
            overrides.sorted() == self.overrides.sorted()
        }
    }
}
