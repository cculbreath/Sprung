//
//  OnboardingInterviewService.swift
//  Sprung
//
//  Main runtime for the onboarding interview feature. Bridges the orchestrator,
//  tool execution layer, and SwiftUI-facing state.
//

import Foundation
import Observation
import SwiftyJSON
import SwiftOpenAI

@MainActor
@Observable
final class OnboardingInterviewService {
    // MARK: - Publicly observed state

    private(set) var messages: [OnboardingMessage] = []
    private(set) var pendingChoicePrompt: OnboardingChoicePrompt?
    private(set) var pendingValidationPrompt: OnboardingValidationPrompt?
    private(set) var pendingApplicantProfileRequest: OnboardingApplicantProfileRequest?
    private(set) var pendingContactsRequest: OnboardingContactsFetchRequest?
    private(set) var pendingSectionToggleRequest: OnboardingSectionToggleRequest?
    private(set) var pendingSectionEntryRequests: [OnboardingSectionEntryRequest] = []
    private(set) var pendingUploadRequests: [OnboardingUploadRequest] = []
    private(set) var pendingExtraction: OnboardingPendingExtraction?
    private(set) var pendingPhaseAdvanceRequest: OnboardingPhaseAdvanceRequest?
    private(set) var uploadedItems: [OnboardingUploadedItem] = []
    private(set) var artifacts = OnboardingArtifacts()
    private(set) var schemaIssues: [String] = []
    private(set) var nextQuestions: [OnboardingQuestion] = []

    private(set) var wizardStep: OnboardingWizardStep = .introduction
    private(set) var completedWizardSteps: Set<OnboardingWizardStep> = []
    private(set) var wizardStepStatuses: [OnboardingWizardStep: OnboardingWizardStepStatus] = [:]

    private(set) var isProcessing = false
    private(set) var isActive = false
    private(set) var allowWebSearch = true
    private(set) var allowWritingAnalysis = false
    private(set) var lastError: String?

    var preferredModelIdForDisplay: String? {
        preferredModelId
    }

    var preferredBackend: LLMFacade.Backend {
        preferredBackendValue
    }

    // MARK: - Internal state

    private let openAIService: OpenAIService?
    private let applicantProfileStore: ApplicantProfileStore
    private let documentExtractionService: DocumentExtractionService
    private let interviewState = InterviewState()
    private let checkpoints = Checkpoints()
    private let dataStore = InterviewDataStore()
    @ObservationIgnored private let toolRegistry = ToolRegistry()
    @ObservationIgnored private let toolExecutor: ToolExecutor

    private var orchestrator: InterviewOrchestrator?
    private var preferredModelId: String?
    private var preferredBackendValue: LLMFacade.Backend = .openAI
    private var pendingChoiceContinuationId: UUID?
    private var pendingValidationContinuationId: UUID?
    private var applicantProfileContinuationId: UUID?
    private var uploadContinuationIds: [UUID: UUID] = [:]
    private var sectionToggleContinuationId: UUID?
    private var phaseAdvanceContinuationId: UUID?
    private(set) var applicantProfileJSON: JSON?
    private(set) var skeletonTimelineJSON: JSON?
    private var phaseAdvanceBlockCache: PhaseAdvanceBlockCache?
    private var systemPrompt: String

    // MARK: - Init

    init(
        openAIService: OpenAIService?,
        applicantProfileStore: ApplicantProfileStore,
        documentExtractionService: DocumentExtractionService
    ) {
        self.openAIService = openAIService
        self.applicantProfileStore = applicantProfileStore
        self.documentExtractionService = documentExtractionService
        self.toolExecutor = ToolExecutor(registry: toolRegistry)
        self.systemPrompt = Self.defaultSystemPrompt()
        registerTools()
    }

    // MARK: - Tool Registration

    private func registerTools() {
        toolRegistry.register(GetUserOptionTool(service: self))
        toolRegistry.register(SubmitForValidationTool(service: self))
        toolRegistry.register(PersistDataTool(dataStore: dataStore))
        toolRegistry.register(GetMacOSContactCardTool())
        toolRegistry.register(GetUserUploadTool(service: self))
        toolRegistry.register(ExtractDocumentTool(extractionService: documentExtractionService))
        toolRegistry.register(CapabilitiesDescribeTool(service: self))
        toolRegistry.register(SetObjectiveStatusTool(service: self))
        toolRegistry.register(NextPhaseTool(service: self))
    }

    func capabilityManifest() -> JSON {
        var manifest = JSON()
        manifest["version"].int = 2

        var toolsJSON = JSON()

        toolsJSON["capabilities.describe"]["status"].string = "ready"

        toolsJSON["get_user_option"]["status"].string = "ready"

        toolsJSON["get_user_upload"]["status"].string = "ready"
        toolsJSON["get_user_upload"]["accepts"] = JSON(["pdf", "docx", "txt", "md"])
        toolsJSON["get_user_upload"]["max_bytes"].int = 10 * 1024 * 1024

        toolsJSON["get_macos_contact_card"]["status"].string = "ready"

        toolsJSON["extract_document"]["status"].string = "ready"
        toolsJSON["extract_document"]["supports"] = JSON(["pdf", "docx"])
        toolsJSON["extract_document"]["ocr"].bool = true
        toolsJSON["extract_document"]["layout_preservation"].bool = true
        toolsJSON["extract_document"]["return_types"] = JSON(["artifact_record", "applicant_profile", "skeleton_timeline"])

        toolsJSON["submit_for_validation"]["status"].string = "ready"
        toolsJSON["submit_for_validation"]["data_types"] = JSON([
            "applicant_profile",
            "skeleton_timeline",
            "experience",
            "education",
            "knowledge_card"
        ])

        toolsJSON["persist_data"]["status"].string = "ready"
        toolsJSON["persist_data"]["data_types"] = JSON([
            "applicant_profile",
            "skeleton_timeline",
            "knowledge_card",
            "artifact_record",
            "writing_sample",
            "candidate_dossier"
        ])

        toolsJSON["set_objective_status"]["status"].string = "ready"
        toolsJSON["next_phase"]["status"].string = "ready"

        manifest["tools"] = toolsJSON
        return manifest
    }

    func currentSession() async -> InterviewSession {
        await interviewState.currentSession()
    }

    func missingObjectives() async -> [String] {
        await interviewState.missingObjectives()
    }

    func nextPhaseIdentifier() async -> InterviewPhase? {
        await interviewState.nextPhase()
    }

    func advancePhase() async -> InterviewPhase? {
        await interviewState.advanceToNextPhase()
        let session = await interviewState.currentSession()
        applyWizardProgress(from: session)
        phaseAdvanceBlockCache = nil
        return session.phase
    }

    func updateObjectiveStatus(objectiveId: String, status: String) async throws -> JSON {
        let normalized = status.lowercased()
        switch normalized {
        case "completed":
            await interviewState.completeObjective(objectiveId)
        case "pending", "reset":
            await interviewState.resetObjective(objectiveId)
        default:
            throw ToolError.invalidParameters("Unsupported status: \(status)")
        }

        let session = await interviewState.currentSession()
        applyWizardProgress(from: session)
        phaseAdvanceBlockCache = nil

        var response = JSON()
        response["status"].string = "ok"
        response["objective"].string = objectiveId
        response["state"].string = normalized == "completed" ? "completed" : "pending"
        return response
    }

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

    func startInterview(modelId: String, backend: LLMFacade.Backend) async {
        guard backend == .openAI else {
            lastError = "Only the OpenAI backend is supported for onboarding interviews."
            return
        }

        guard let openAIService else {
            lastError = "OpenAI API key is not configured."
            return
        }

        resetTransientState()
        await loadPersistedArtifacts()
        await interviewState.restore(from: InterviewSession())
        let restoredFromCheckpoint = await restoreFromCheckpointIfAvailable()

        orchestrator = makeOrchestrator(service: openAIService)
        isActive = true
        isProcessing = true
        if !restoredFromCheckpoint {
            wizardStep = .resumeIntake
            wizardStepStatuses[wizardStep] = .current
        }

        appendSystemMessage("🚀 Starting onboarding interview using \(modelId).")
        if restoredFromCheckpoint {
            appendSystemMessage("♻️ Resuming your previous onboarding progress.")
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
        isActive = false
        isProcessing = false
        resetTransientState()
        messages.removeAll()
        nextQuestions.removeAll()
        lastError = nil
        let state = interviewState
        Task { await state.restore(from: InterviewSession()) }
        Task { await self.loadPersistedArtifacts() }
    }

    // MARK: - Phase Handling

    func setPhase(_ step: OnboardingWizardStep) {
        let previous = wizardStep
        wizardStep = step
        wizardStepStatuses[step] = .current
        if previous != step {
            wizardStepStatuses[previous] = .completed
        }
        if step != .introduction {
            completedWizardSteps.insert(step)
        }
    }

    // MARK: - Preferences

    func setPreferredDefaults(
        modelId: String,
        backend: LLMFacade.Backend,
        webSearchAllowed: Bool
    ) {
        preferredModelId = modelId
        preferredBackendValue = backend
        allowWebSearch = webSearchAllowed
    }

    func setWritingAnalysisConsent(_ allowed: Bool) {
        allowWritingAnalysis = allowed
    }

    // MARK: - Choice Prompt Handling

    func presentChoicePrompt(prompt: OnboardingChoicePrompt, continuationId: UUID) {
        pendingChoicePrompt = prompt
        pendingChoiceContinuationId = continuationId
        isProcessing = false
    }

    func clearChoicePrompt(continuationId: UUID) {
        if pendingChoiceContinuationId == continuationId {
            pendingChoicePrompt = nil
            pendingChoiceContinuationId = nil
        }
    }

    func resolveChoice(selectionIds: [String]) async {
        guard
            let continuationId = pendingChoiceContinuationId,
            !selectionIds.isEmpty
        else { return }

        var payload = JSON()
        payload["selectedIds"] = JSON(selectionIds)

        isProcessing = true
        await orchestrator?.resumeToolContinuation(id: continuationId, payload: payload)
    }

    func cancelChoicePrompt(reason: String) async {
        guard let continuationId = pendingChoiceContinuationId else { return }

        debugLog("User cancelled choice prompt: \(reason)")
        var payload = JSON()
        payload["cancelled"].boolValue = true

        isProcessing = true
        await orchestrator?.resumeToolContinuation(id: continuationId, payload: payload)
    }

    // MARK: - Applicant Profile Handling

    func presentApplicantProfileRequest(_ request: OnboardingApplicantProfileRequest, continuationId: UUID) {
        pendingApplicantProfileRequest = request
        applicantProfileContinuationId = continuationId
        isProcessing = false
        updateWaitingState(.validation)
    }

    func clearApplicantProfileRequest(continuationId: UUID) {
        guard applicantProfileContinuationId == continuationId else { return }
        pendingApplicantProfileRequest = nil
        applicantProfileContinuationId = nil
    }

    func resolveApplicantProfile(with draft: ApplicantProfileDraft) async {
        guard
            let continuationId = applicantProfileContinuationId,
            let request = pendingApplicantProfileRequest
        else { return }

        let resolvedJSON = draft.toJSON()
        let status: String = resolvedJSON == request.proposedProfile ? "approved" : "modified"

        var payload = JSON()
        payload["status"].string = status
        payload["data"] = resolvedJSON

        clearApplicantProfileRequest(continuationId: continuationId)
        isProcessing = true
        updateWaitingState(nil)
        await orchestrator?.resumeToolContinuation(id: continuationId, payload: payload)
    }

    func rejectApplicantProfile(reason: String) async {
        guard let continuationId = applicantProfileContinuationId else { return }

        var payload = JSON()
        payload["status"].string = "rejected"
        if !reason.isEmpty {
            payload["userNotes"].string = reason
        }

        clearApplicantProfileRequest(continuationId: continuationId)
        isProcessing = true
        updateWaitingState(nil)
        await orchestrator?.resumeToolContinuation(id: continuationId, payload: payload)
    }

    // MARK: - Validation Prompt Handling

    func resolveSectionToggle(enabled: [String]) async {
        guard let continuationId = sectionToggleContinuationId else { return }

        var payload = JSON()
        payload["enabledSections"] = JSON(enabled)

        pendingSectionToggleRequest = nil
        sectionToggleContinuationId = nil
        isProcessing = true
        updateWaitingState(nil)
        artifacts.enabledSections = enabled
        await persistCheckpoint()
        await orchestrator?.resumeToolContinuation(id: continuationId, payload: payload)
    }

    func rejectSectionToggle(reason: String) async {
        guard let continuationId = sectionToggleContinuationId else { return }

        var payload = JSON()
        payload["cancelled"].boolValue = true
        if !reason.isEmpty {
            payload["userNotes"].string = reason
        }

        pendingSectionToggleRequest = nil
        sectionToggleContinuationId = nil
        isProcessing = true
        updateWaitingState(nil)
        await orchestrator?.resumeToolContinuation(id: continuationId, payload: payload)
    }

    func presentValidationPrompt(prompt: OnboardingValidationPrompt, continuationId: UUID) {
        pendingValidationPrompt = prompt
        pendingValidationContinuationId = continuationId
        isProcessing = false
        updateWaitingState(.validation)
    }

    func presentUploadRequest(_ request: OnboardingUploadRequest, continuationId: UUID) {
        removeUploadRequest(id: request.id)
        pendingUploadRequests.append(request)
        uploadContinuationIds[request.id] = continuationId
        isProcessing = false
        updateWaitingState(.upload)
    }

    func clearValidationPrompt(continuationId: UUID) {
        if pendingValidationContinuationId == continuationId {
            pendingValidationPrompt = nil
            pendingValidationContinuationId = nil
        }
    }

    func submitValidationResponse(
        status: String,
        updatedData: JSON?,
        changes: JSON?,
        notes: String?
    ) async {
        guard let continuationId = pendingValidationContinuationId else { return }

        var payload = JSON()
        payload["status"].string = status
        if let updatedData, updatedData != .null {
            payload["data"] = updatedData
        }
        if let changes, changes != .null {
            payload["changes"] = changes
        }
        if let notes, !notes.isEmpty {
            payload["userNotes"].string = notes
        }

        isProcessing = true
        await orchestrator?.resumeToolContinuation(id: continuationId, payload: payload)
    }

    func cancelValidation(reason: String) async {
        guard let continuationId = pendingValidationContinuationId else { return }
        debugLog("User cancelled validation request: \(reason)")

        var payload = JSON()
        payload["cancelled"].boolValue = true
        isProcessing = true
        await orchestrator?.resumeToolContinuation(id: continuationId, payload: payload)
    }

    func completeUploadRequest(id: UUID, fileURLs: [URL]) async {
        guard let continuationId = uploadContinuationIds[id] else { return }
        removeUploadRequest(id: id)
        uploadContinuationIds.removeValue(forKey: id)

        if !fileURLs.isEmpty {
            let newItems = fileURLs.map {
                OnboardingUploadedItem(
                    id: UUID(),
                    filename: $0.lastPathComponent,
                    url: $0,
                    uploadedAt: Date()
                )
            }
            uploadedItems.append(contentsOf: newItems)
        }

        var payload = JSON()
        if fileURLs.isEmpty {
            payload["status"].string = "skipped"
        } else {
            payload["status"].string = "uploaded"
            let filesJSON = fileURLs.map { url -> JSON in
                var json = JSON()
                json["url"].string = url.absoluteString
                json["filename"].string = url.lastPathComponent
                return json
            }
            payload["files"] = JSON(filesJSON)
        }

        isProcessing = true
        updateWaitingState(nil)
        await orchestrator?.resumeToolContinuation(id: continuationId, payload: payload)
    }

    func skipUploadRequest(id: UUID) async {
        await completeUploadRequest(id: id, fileURLs: [])
    }

    // MARK: - Callback Handling

    func handleProcessingStateChange(_ processing: Bool) {
        isProcessing = processing
    }

    func appendAssistantMessage(_ text: String) {
        messages.append(OnboardingMessage(role: .assistant, text: text))
    }

    func appendSystemMessage(_ text: String) {
        messages.append(OnboardingMessage(role: .system, text: text))
    }

    func recordError(_ message: String) {
        lastError = message
        appendSystemMessage("⚠️ \(message)")
    }

    func updateWaitingState(_ waiting: InterviewSession.Waiting?) {
        switch waiting {
        case .selection, .validation, .upload:
            wizardStepStatuses[wizardStep] = .current
        case .none:
            wizardStepStatuses[wizardStep] = nil
        }
    }

    // MARK: - Private Helpers

    private func appendUserMessage(_ text: String) {
        messages.append(OnboardingMessage(role: .user, text: text))
    }

    private func resetTransientState() {
        pendingChoicePrompt = nil
        pendingValidationPrompt = nil
        pendingChoiceContinuationId = nil
        pendingValidationContinuationId = nil
        pendingApplicantProfileRequest = nil
        applicantProfileContinuationId = nil
        pendingUploadRequests.removeAll()
        uploadContinuationIds.removeAll()
        uploadedItems.removeAll()
        pendingExtraction = nil
        pendingPhaseAdvanceRequest = nil
        phaseAdvanceContinuationId = nil
        applicantProfileJSON = nil
        skeletonTimelineJSON = nil
        artifacts.applicantProfile = nil
        artifacts.skeletonTimeline = nil
        artifacts.artifactRecords = []
        artifacts.enabledSections = []
        nextQuestions.removeAll()
        lastError = nil
        wizardStep = .introduction
        completedWizardSteps.removeAll()
        wizardStepStatuses.removeAll()
        updateWaitingState(nil)
        phaseAdvanceBlockCache = nil
    }

    private func restoreFromCheckpointIfAvailable() async -> Bool {
        guard let snapshot = await checkpoints.restoreLatest() else {
            return false
        }

        let (session, profileJSON, timelineJSON, enabledSections) = snapshot
        await interviewState.restore(from: session)
        applyWizardProgress(from: session)

        if let profileJSON {
            await storeApplicantProfile(profileJSON)
        }
        if let timelineJSON {
            await storeSkeletonTimeline(timelineJSON)
        }
        if let enabledSections, !enabledSections.isEmpty {
            artifacts.enabledSections = enabledSections
        }

        isProcessing = false
        return true
    }

    private func applyWizardProgress(from session: InterviewSession) {
        completedWizardSteps.removeAll()
        wizardStepStatuses.removeAll()

        let objectives = session.objectivesDone
        var currentStep: OnboardingWizardStep = .resumeIntake

        if objectives.contains("applicant_profile") {
            completedWizardSteps.insert(.resumeIntake)
        }

        if objectives.contains("skeleton_timeline") {
            currentStep = .artifactDiscovery
        }

        switch session.phase {
        case .phase1CoreFacts:
            if !objectives.contains("skeleton_timeline") {
                currentStep = .resumeIntake
            }
        case .phase2DeepDive:
            completedWizardSteps.insert(.resumeIntake)
            if objectives.contains("skeleton_timeline") {
                completedWizardSteps.insert(.artifactDiscovery)
            }
            currentStep = .artifactDiscovery
        case .phase3WritingCorpus:
            completedWizardSteps.insert(.resumeIntake)
            completedWizardSteps.insert(.artifactDiscovery)
            currentStep = .writingCorpus
        case .complete:
            completedWizardSteps.insert(.resumeIntake)
            completedWizardSteps.insert(.artifactDiscovery)
            completedWizardSteps.insert(.writingCorpus)
            currentStep = .wrapUp
        }

        for step in completedWizardSteps {
            wizardStepStatuses[step] = .completed
        }

        wizardStep = currentStep
        wizardStepStatuses[currentStep] = .current
    }

    private func makeOrchestrator(service: OpenAIService) -> InterviewOrchestrator {
        let callbacks = InterviewOrchestrator.Callbacks(
            updateProcessingState: { [weak self] processing in
                guard let service = self else { return }
                await service.handleProcessingStateChange(processing)
            },
            emitAssistantMessage: { [weak self] text in
                guard let service = self else { return }
                await service.appendAssistantMessage(text)
            },
            handleWaitingState: { [weak self] waiting in
                guard let service = self else { return }
                await service.updateWaitingState(waiting)
            },
            handleError: { [weak self] message in
                guard let service = self else { return }
                await service.recordError(message)
            },
            storeApplicantProfile: { [weak self] json in
                guard let service = self else { return }
                await service.storeApplicantProfile(json)
            },
            storeSkeletonTimeline: { [weak self] json in
                guard let service = self else { return }
                await service.storeSkeletonTimeline(json)
            },
            storeArtifactRecord: { [weak self] artifact in
                guard let service = self else { return }
                await service.storeArtifactRecord(artifact)
            },
            setExtractionStatus: { [weak self] status in
                guard let service = self else { return }
                await service.setExtractionStatus(status)
            },
            persistCheckpoint: { [weak self] in
                guard let service = self else { return }
                await service.persistCheckpoint()
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
        applicantProfileJSON = json
        let draft = ApplicantProfileDraft(json: json)
        let profile = applicantProfileStore.currentProfile()
        draft.apply(to: profile)
        applicantProfileStore.save(profile)
        artifacts.applicantProfile = json
        await persistCheckpoint()
    }

    private func storeSkeletonTimeline(_ json: JSON) async {
        skeletonTimelineJSON = json
        artifacts.skeletonTimeline = json
        await persistCheckpoint()
    }

    private func storeArtifactRecord(_ artifact: JSON) async {
        guard artifact != .null else { return }

        if let sha = artifact["sha256"].string {
            artifacts.artifactRecords.removeAll { $0["sha256"].stringValue == sha }
        }
        artifacts.artifactRecords.append(artifact)
    }

    private func persistCheckpoint() async {
        let session = await interviewState.currentSession()
        let sections = artifacts.enabledSections
        await checkpoints.save(
            from: session,
            applicantProfile: applicantProfileJSON,
            skeletonTimeline: skeletonTimelineJSON,
            enabledSections: sections.isEmpty ? nil : sections
        )
    }

    func setExtractionStatus(_ status: OnboardingPendingExtraction?) {
        pendingExtraction = status
    }

    private func loadPersistedArtifacts() async {
        let records = await dataStore.list(dataType: "artifact_record")
        var deduped: [JSON] = []
        var seen: Set<String> = []
        for record in records {
            if let sha = record["sha256"].string, !sha.isEmpty {
                if seen.contains(sha) { continue }
                seen.insert(sha)
            }
            deduped.append(record)
        }
        artifacts.artifactRecords = deduped
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

    private func removeUploadRequest(id: UUID) {
        pendingUploadRequests.removeAll { $0.id == id }
    }

    private static func defaultSystemPrompt() -> String {
        """
        You are the Sprung onboarding interviewer. Coordinate a structured interview that uses tools for
        collecting information, validating data with the user, and persisting progress.

        PHASE 1 OPENING SEQUENCE:
        When you receive the initial trigger message "Begin the onboarding interview", follow this exact flow:
        1. Greet the user warmly (do not echo the trigger message): "Welcome. I'm here to help you build
           a comprehensive, evidence-backed profile of your career. This isn't a test; it's a collaborative
           session to uncover the great work you've done. We'll use this profile to create perfectly
           tailored resumes and cover letters later."

        2. Immediately call get_user_option to offer profile collection methods with these four options:
           - id: "upload_file", label: "Upload Resume", description: "Upload your resume PDF or DOCX"
           - id: "paste_url", label: "Paste Resume URL", description: "Provide a URL to your resume or LinkedIn"
           - id: "use_contacts", label: "Import from Contacts", description: "Use macOS Contacts to pre-fill your profile"
           - id: "manual_entry", label: "Enter Manually", description: "Fill out your profile information step by step"

        3. When any tool returns with status "waiting for user input", respond with a brief, contextual message:
           "Once you complete the form to the left we can continue."
           This keeps the conversation flowing while the user interacts with UI elements.

        4. After the user completes their choice, proceed naturally based on their selection.

        CAPABILITY-DRIVEN WORKFLOW:
        - Call capabilities.describe at the start of each phase to see what tools are currently available
        - Choose the right tool for each micro-step based on the capabilities manifest
        - All tools return vendor-agnostic outputs—you never see implementation details or provider names

        TOOL USAGE RULES:
        - Always prefer tools instead of free-form instructions when gathering data
        - Use extract_document for ALL PDF/DOCX files—it returns semantically-enhanced text with layout preservation
        - After extraction, YOU parse the text yourself to build structured data (applicant profiles, timelines)
        - Ask clarifying questions when data is ambiguous or incomplete before submitting for validation
        - Mark objectives complete with set_objective_status as you achieve each one
        - When ready to advance phases, call next_phase (you may propose overrides for unmet objectives with a clear reason)

        EXTRACTION & PARSING WORKFLOW:
        1. User uploads resume → you call extract_document(file_url)
        2. Tool returns artifact with extracted_content (semantically-enhanced Markdown/text)
        3. YOU read the text and construct applicant_profile JSON
        4. YOU read the text and construct skeleton_timeline JSON
        5. If dates/companies are unclear, ASK the user for clarification
        6. Only after clarification, call submit_for_validation for user approval
        7. Call persist_data to save approved data
        8. Call set_objective_status to mark objectives complete

        PHASE ADVANCEMENT:
        - Track your progress by marking objectives complete as you finish them
        - When all required objectives for a phase are done, call next_phase with empty overrides
        - If user wants to skip ahead, call next_phase with overrides array listing incomplete objectives
        - Always provide a clear reason when proposing overrides

        STYLE:
        - Keep responses concise unless additional detail is requested
        - Be encouraging and explain why you need each piece of information
        - Confirm major milestones with the user and respect their decisions
        - Act as a supportive career coach, not a chatbot or form
        """
    }
}
