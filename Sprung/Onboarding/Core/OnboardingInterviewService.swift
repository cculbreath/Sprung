//
//  OnboardingInterviewService.swift
//  Sprung
//
//  Main runtime for the onboarding interview feature. Bridges the orchestrator,
//  tool execution layer, and SwiftUI-facing state.
//

import AppKit
import Contacts
import Foundation
import Observation
import SwiftyJSON
import SwiftOpenAI
import UniformTypeIdentifiers

@MainActor
@Observable
final class OnboardingInterviewService {
    // MARK: - Publicly observed state

    private(set) var messages: [OnboardingMessage] = []
    private(set) var pendingChoicePrompt: OnboardingChoicePrompt?
    private(set) var pendingValidationPrompt: OnboardingValidationPrompt?
    private(set) var pendingApplicantProfileRequest: OnboardingApplicantProfileRequest?
    private(set) var pendingApplicantProfileIntake: OnboardingApplicantProfileIntakeState?
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
    @ObservationIgnored private let knowledgeCardAgent: KnowledgeCardAgent?

    private var orchestrator: InterviewOrchestrator?
    private var preferredModelId: String?
    private var preferredBackendValue: LLMFacade.Backend = .openAI
    private var pendingChoiceContinuationId: UUID?
    private var pendingValidationContinuationId: UUID?
    private var applicantProfileContinuationId: UUID?
    private var applicantIntakeContinuationId: UUID?
    private var uploadContinuationIds: [UUID: UUID] = [:]
    private var sectionToggleContinuationId: UUID?
    private var phaseAdvanceContinuationId: UUID?
    private(set) var applicantProfileJSON: JSON?
    private(set) var skeletonTimelineJSON: JSON?
    private var phaseAdvanceBlockCache: PhaseAdvanceBlockCache?
    private var systemPrompt: String
    private var streamingMessageStart: [UUID: Date] = [:]

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
        self.knowledgeCardAgent = openAIService.map { KnowledgeCardAgent(client: $0) }
        registerTools()
    }

    // MARK: - Tool Registration

    private func registerTools() {
        toolRegistry.register(GetUserOptionTool(service: self))
        toolRegistry.register(SubmitForValidationTool(service: self))
        toolRegistry.register(PersistDataTool(dataStore: dataStore))
        toolRegistry.register(GetMacOSContactCardTool())
        toolRegistry.register(GetApplicantProfileTool(service: self))
        toolRegistry.register(GetUserUploadTool(service: self))
        toolRegistry.register(ExtractDocumentTool(extractionService: documentExtractionService))
        toolRegistry.register(CapabilitiesDescribeTool(service: self))
        toolRegistry.register(SetObjectiveStatusTool(service: self))
        toolRegistry.register(NextPhaseTool(service: self))
        toolRegistry.register(
            GenerateKnowledgeCardTool(agentProvider: { [weak self] in
                self?.knowledgeCardAgent
            })
        )
    }

    func capabilityManifest() -> JSON {
        var manifest = JSON()
        manifest["version"].int = 2

        var toolsJSON = JSON()

        toolsJSON["capabilities_describe"]["status"].string = "ready"

        toolsJSON["get_user_option"]["status"].string = "ready"

        toolsJSON["get_user_upload"]["status"].string = "ready"
        toolsJSON["get_user_upload"]["accepts"] = JSON(["pdf", "docx", "txt", "md"])
        toolsJSON["get_user_upload"]["max_bytes"].int = 10 * 1024 * 1024

        toolsJSON["get_macos_contact_card"]["status"].string = "ready"

        toolsJSON["get_applicant_profile"]["status"].string = "ready"
        toolsJSON["get_applicant_profile"]["paths"] = JSON(["upload", "url", "contacts", "manual"])

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

        let knowledgeCardStatus = knowledgeCardAgent == nil ? "locked" : "ready"
        toolsJSON["generate_knowledge_card"]["status"].string = knowledgeCardStatus

        manifest["tools"] = toolsJSON
        return manifest
    }

    func currentSession() async -> InterviewSession {
        await interviewState.currentSession()
    }

    func hasRestorableCheckpoint() async -> Bool {
        await checkpoints.hasCheckpoint()
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

    func startInterview(modelId: String, backend: LLMFacade.Backend, resumeExisting: Bool) async {
        guard backend == .openAI else {
            lastError = "Only the OpenAI backend is supported for onboarding interviews."
            return
        }

        guard let openAIService else {
            lastError = "OpenAI API key is not configured."
            return
        }

        guard isActive == false else {
            Logger.debug("startInterview called while interview is already active; ignoring request.")
            return
        }

        resetTransientState()
        messages.removeAll()
        nextQuestions.removeAll()

        let restoredFromCheckpoint: Bool

        if resumeExisting {
            await loadPersistedArtifacts()
            await interviewState.restore(from: InterviewSession())
            let restored = await restoreFromCheckpointIfAvailable()
            if !restored {
                await checkpoints.clear()
                await dataStore.reset()
            }
            restoredFromCheckpoint = restored
        } else {
            await checkpoints.clear()
            await dataStore.reset()
            await interviewState.restore(from: InterviewSession())
            restoredFromCheckpoint = false
        }

        orchestrator = makeOrchestrator(service: openAIService)
        isActive = true
        isProcessing = true
        if !restoredFromCheckpoint {
            wizardStep = .resumeIntake
            wizardStepStatuses[wizardStep] = .current
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

        Logger.debug("User cancelled choice prompt: \(reason)")
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

    // MARK: - Applicant Profile Intake

    func presentApplicantProfileIntake(continuationId: UUID) {
        pendingApplicantProfileIntake = .options()
        applicantIntakeContinuationId = continuationId
        isProcessing = false
        updateWaitingState(.selection)
    }

    func resetApplicantProfileIntakeToOptions() {
        guard applicantIntakeContinuationId != nil else { return }
        pendingApplicantProfileIntake = .options()
    }

    func beginApplicantProfileManualEntry() {
        guard applicantIntakeContinuationId != nil else { return }
        pendingApplicantProfileIntake = OnboardingApplicantProfileIntakeState(
            mode: .manual(source: .manual),
            draft: ApplicantProfileDraft(),
            urlString: "",
            errorMessage: nil
        )
    }

    func beginApplicantProfileURL() {
        guard applicantIntakeContinuationId != nil else { return }
        pendingApplicantProfileIntake = OnboardingApplicantProfileIntakeState(
            mode: .urlEntry,
            draft: ApplicantProfileDraft(),
            urlString: "",
            errorMessage: nil
        )
    }

    func beginApplicantProfileUpload() {
        guard let continuationId = applicantIntakeContinuationId else { return }

        let metadata = OnboardingUploadMetadata(
            title: "Upload Résumé",
            instructions: "Select your latest resume (PDF, DOCX, or text).",
            accepts: ["pdf", "doc", "docx", "txt", "md"],
            allowMultiple: false
        )

        let request = OnboardingUploadRequest(kind: .resume, metadata: metadata)
        presentUploadRequest(request, continuationId: continuationId)
    }

    func beginApplicantProfileContactsFetch() {
        guard applicantIntakeContinuationId != nil else { return }
        pendingApplicantProfileIntake = OnboardingApplicantProfileIntakeState(
            mode: .loading("Fetching your contact card…"),
            draft: ApplicantProfileDraft(),
            urlString: "",
            errorMessage: nil
        )

        Task { @MainActor in
            do {
                let draft = try await Self.fetchMeCardAsDraft()
                pendingApplicantProfileIntake = OnboardingApplicantProfileIntakeState(
                    mode: .manual(source: .contacts),
                    draft: draft,
                    urlString: "",
                    errorMessage: nil
                )
            } catch let error as ContactFetchError {
                pendingApplicantProfileIntake = OnboardingApplicantProfileIntakeState(
                    mode: .options,
                    draft: ApplicantProfileDraft(),
                    urlString: "",
                    errorMessage: error.message
                )
            } catch {
                pendingApplicantProfileIntake = OnboardingApplicantProfileIntakeState(
                    mode: .options,
                    draft: ApplicantProfileDraft(),
                    urlString: "",
                    errorMessage: "Failed to access macOS contacts."
                )
            }
        }
    }

    func submitApplicantProfileURL(_ urlString: String) async {
        guard let continuationId = applicantIntakeContinuationId else { return }

        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme != nil else {
            pendingApplicantProfileIntake = OnboardingApplicantProfileIntakeState(
                mode: .urlEntry,
                draft: ApplicantProfileDraft(),
                urlString: urlString,
                errorMessage: "Please enter a valid URL including the scheme (https://)."
            )
            return
        }

        var payload = JSON()
        payload["mode"].string = "url"
        payload["status"].string = "provided"
        payload["url"].string = url.absoluteString
        await completeApplicantProfileIntake(continuationId: continuationId, payload: payload)
    }

    func completeApplicantProfileDraft(_ draft: ApplicantProfileDraft, source: OnboardingApplicantProfileIntakeState.Source) async {
        guard let continuationId = applicantIntakeContinuationId else { return }

        var payload = JSON()
        payload["mode"].string = source == .contacts ? "contacts" : "manual"
        payload["status"].string = "completed"
        payload["data"] = draft.toJSON()
        await completeApplicantProfileIntake(continuationId: continuationId, payload: payload)
    }

    func cancelApplicantProfileIntake(reason: String) async {
        guard let continuationId = applicantIntakeContinuationId else { return }

        Logger.debug("Applicant profile intake cancelled: \(reason)")
        var payload = JSON()
        payload["cancelled"].boolValue = true
        await completeApplicantProfileIntake(continuationId: continuationId, payload: payload)
    }

    private func completeApplicantProfileIntake(continuationId: UUID, payload: JSON) async {
        pendingApplicantProfileIntake = nil
        applicantIntakeContinuationId = nil
        isProcessing = true
        updateWaitingState(nil)
        await orchestrator?.resumeToolContinuation(id: continuationId, payload: payload)
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
        Logger.debug("User cancelled validation request: \(reason)")

        var payload = JSON()
        payload["cancelled"].boolValue = true
        isProcessing = true
        await orchestrator?.resumeToolContinuation(id: continuationId, payload: payload)
    }

    func completeUploadRequest(id: UUID, fileURLs: [URL]) async {
        await handleUploadCompletion(id: id, fileURLs: fileURLs, originalURL: nil)
    }

    func completeUploadRequest(id: UUID, link: URL) async {
        do {
            let temporaryURL = try await downloadRemoteFile(from: link)
            await handleUploadCompletion(id: id, fileURLs: [temporaryURL], originalURL: link)
            try? FileManager.default.removeItem(at: temporaryURL)
        } catch {
            await resumeUpload(id: id, withError: error.localizedDescription)
        }
    }

    func skipUploadRequest(id: UUID) async {
        await completeUploadRequest(id: id, fileURLs: [])
    }

    // MARK: - Callback Handling

    func handleProcessingStateChange(_ processing: Bool) {
        isProcessing = processing
    }

    func appendAssistantMessage(_ text: String) {
        let message = OnboardingMessage(role: .assistant, text: text)
        messages.append(message)
        Logger.debug("[Stream] Assistant message posted immediately (len: \(text.count))")
    }

    func beginAssistantStream(initialText: String = "") -> UUID {
        let message = OnboardingMessage(role: .assistant, text: initialText)
        messages.append(message)
        streamingMessageStart[message.id] = Date()
        Logger.debug("[Stream] Started assistant stream \(message.id.uuidString) (len: \(initialText.count))")
        return message.id
    }

    func updateAssistantStream(id: UUID, text: String) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].text = text
        Logger.debug("[Stream] Update for message \(id.uuidString) (len: \(text.count))")
    }

    func finalizeAssistantStream(id: UUID, text: String) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].text = text
        let elapsed: TimeInterval
        if let start = streamingMessageStart.removeValue(forKey: id) {
            elapsed = Date().timeIntervalSince(start)
        } else {
            elapsed = 0
        }
        Logger.debug("[Stream] Completed message \(id.uuidString) in \(String(format: "%.3f", elapsed))s (len: \(text.count))")
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
        pendingApplicantProfileIntake = nil
        applicantIntakeContinuationId = nil
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
        artifacts.knowledgeCards = []
        nextQuestions.removeAll()
        lastError = nil
        wizardStep = .introduction
        completedWizardSteps.removeAll()
        wizardStepStatuses.removeAll()
        updateWaitingState(nil)
        phaseAdvanceBlockCache = nil
        streamingMessageStart.removeAll()
    }

    func storeApplicantProfileImage(data: Data, mimeType: String?) {
        let profile = applicantProfileStore.currentProfile()
        profile.pictureData = data
        profile.pictureMimeType = mimeType
        applicantProfileStore.save(profile)

        var json = applicantProfileJSON ?? JSON()
        json["image"].string = data.base64EncodedString()
        if let mimeType {
            json["image_mime_type"].string = mimeType
        }
        applicantProfileJSON = json
        artifacts.applicantProfile = json
        Task { await persistCheckpoint() }
        Logger.debug("Applicant profile image updated (\(data.count) bytes, mime: \(mimeType ?? "unknown"))")
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
                await MainActor.run { service.handleProcessingStateChange(processing) }
            },
            emitAssistantMessage: { [weak self] text in
                guard let service = self else { return }
                await MainActor.run { service.appendAssistantMessage(text) }
            },
            beginStreamingAssistantMessage: { [weak self] initial in
                guard let service = self else { return UUID() }
                return await MainActor.run { service.beginAssistantStream(initialText: initial) }
            },
            updateStreamingAssistantMessage: { [weak self] id, text in
                guard let service = self else { return }
                await MainActor.run { service.updateAssistantStream(id: id, text: text) }
            },
            finalizeStreamingAssistantMessage: { [weak self] id, text in
                guard let service = self else { return }
                await MainActor.run { service.finalizeAssistantStream(id: id, text: text) }
            },
            handleWaitingState: { [weak self] waiting in
                guard let service = self else { return }
                await MainActor.run { service.updateWaitingState(waiting) }
            },
            handleError: { [weak self] message in
                guard let service = self else { return }
                await MainActor.run { service.recordError(message) }
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
            storeKnowledgeCard: { [weak self] card in
                guard let service = self else { return }
                await service.storeKnowledgeCard(card)
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
        draft.apply(to: profile, replaceMissing: false)
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

    private func storeKnowledgeCard(_ card: JSON) async {
        guard card != .null else { return }

        if let identifier = card["id"].string, !identifier.isEmpty {
            artifacts.knowledgeCards.removeAll { $0["id"].stringValue == identifier }
        }
        artifacts.knowledgeCards.append(card)
        await persistCheckpoint()
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

    private func handleUploadCompletion(id: UUID, fileURLs: [URL], originalURL: URL?) async {
        guard let continuationId = uploadContinuationIds[id] else { return }
        guard let requestIndex = pendingUploadRequests.firstIndex(where: { $0.id == id }) else { return }
        let request = pendingUploadRequests[requestIndex]
        pendingUploadRequests.remove(at: requestIndex)
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

        let storage = OnboardingUploadStorage()
        var processed: [OnboardingProcessedUpload] = []
        var payload = JSON()
        if let target = request.metadata.targetKey {
            payload["targetKey"].string = target
        }

        do {
            if fileURLs.isEmpty {
                payload["status"].string = "skipped"
            } else {
                processed = try fileURLs.map { try storage.processFile(at: $0) }
                var filesJSON: [JSON] = []
                for item in processed {
                    var json = item.toJSON()
                    if let originalURL {
                        json["source"].string = "url"
                        json["original_url"].string = originalURL.absoluteString
                    }
                    filesJSON.append(json)
                }
                payload["status"].string = "uploaded"
                payload["files"] = JSON(filesJSON)

                if let target = request.metadata.targetKey {
                    try await handleTargetedUpload(target: target, processed: processed)
                    payload["updates"] = JSON([target])
                }
            }
        } catch {
            payload["status"].string = "failed"
            payload["error"].string = error.localizedDescription
            for item in processed {
                storage.removeFile(at: item.storageURL)
            }
        }

        if let intakeContinuation = applicantIntakeContinuationId, intakeContinuation == continuationId {
            payload["mode"].string = "upload"
            await completeApplicantProfileIntake(continuationId: intakeContinuation, payload: payload)
            return
        }

        isProcessing = true
        updateWaitingState(nil)
        await orchestrator?.resumeToolContinuation(id: continuationId, payload: payload)
    }

    private func resumeUpload(id: UUID, withError message: String) async {
        guard let continuationId = uploadContinuationIds[id] else { return }
        removeUploadRequest(id: id)
        uploadContinuationIds.removeValue(forKey: id)

        var payload = JSON()
        payload["status"].string = "failed"
        payload["error"].string = message
        isProcessing = true
        updateWaitingState(nil)
        await orchestrator?.resumeToolContinuation(id: continuationId, payload: payload)
    }

    private func handleTargetedUpload(target: String, processed: [OnboardingProcessedUpload]) async throws {
        switch target {
        case "basics.image":
            guard let first = processed.first else {
                throw ToolError.executionFailed("No file received for basics.image")
            }
            let data = try Data(contentsOf: first.storageURL)
            try validateImageData(data: data, fileExtension: first.storageURL.pathExtension)
            storeApplicantProfileImage(data: data, mimeType: first.contentType)
        default:
            throw ToolError.invalidParameters("Unsupported target_key: \(target)")
        }
    }

    private func validateImageData(data: Data, fileExtension: String) throws {
        if data.isEmpty {
            throw ToolError.executionFailed("Image upload is empty")
        }
        if #available(macOS 12.0, *) {
            if let type = UTType(filenameExtension: fileExtension.lowercased()), type.conforms(to: .image) {
                return
            }
        }
        if NSImage(data: data) == nil {
            throw ToolError.executionFailed("Uploaded file is not a valid image")
        }
    }

    private func downloadRemoteFile(from url: URL) async throws -> URL {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw ToolError.executionFailed("Failed to download file from URL")
        }
        if data.isEmpty {
            throw ToolError.executionFailed("Downloaded file is empty")
        }
        let filename = url.lastPathComponent.isEmpty ? UUID().uuidString : url.lastPathComponent
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)_\(filename)")
        try data.write(to: temporary)
        return temporary
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

        let storedKnowledgeCards = await dataStore.list(dataType: "knowledge_card")
        artifacts.knowledgeCards = storedKnowledgeCards
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

    private enum ContactFetchError: Error {
        case permissionDenied
        case notFound
        case system(String)

        var message: String {
            switch self {
            case .permissionDenied:
                return "Sprung does not have permission to access your contacts."
            case .notFound:
                return "We couldn't find a 'Me' contact on this Mac."
            case .system(let description):
                return "Unable to access contacts: \(description)"
            }
        }
    }

    private static func fetchMeCardAsDraft() async throws -> ApplicantProfileDraft {
        try await requestContactsAccess()

        let store = CNContactStore()
        let keys: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactJobTitleKey as CNKeyDescriptor
        ]

        let contact: CNContact
        do {
            contact = try store.unifiedMeContactWithKeys(toFetch: keys)
        } catch {
            if let cnError = error as? CNError, cnError.code == .recordDoesNotExist {
                throw ContactFetchError.notFound
            }
            throw ContactFetchError.system(error.localizedDescription)
        }

        return draft(from: contact)
    }

    private static func requestContactsAccess() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            CNContactStore().requestAccess(for: .contacts) { granted, error in
                if let error {
                    continuation.resume(throwing: ContactFetchError.system(error.localizedDescription))
                } else if granted {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: ContactFetchError.permissionDenied)
                }
            }
        }
    }

    private static func draft(from contact: CNContact) -> ApplicantProfileDraft {
        var draft = ApplicantProfileDraft()

        let fullName = [contact.givenName, contact.familyName]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if !fullName.isEmpty {
            draft.name = fullName
        }

        if !contact.jobTitle.isEmpty {
            draft.label = contact.jobTitle
        }

        if !contact.organizationName.isEmpty {
            draft.summary = "Current role at \(contact.organizationName)."
        }

        let emailValues = contact.emailAddresses
            .compactMap { ($0.value as String).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !emailValues.isEmpty {
            draft.suggestedEmails = emailValues.reduce(into: [String]()) { result, email in
                if !result.contains(email) {
                    result.append(email)
                }
            }
            if draft.email.isEmpty {
                draft.email = draft.suggestedEmails.first ?? ""
            }
        }

        if let phone = contact.phoneNumbers.first?.value.stringValue {
            draft.phone = phone
        }

        return draft
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

        2. Immediately call get_applicant_profile to collect the user's contact information (ApplicantProfile).
           This tool presents the user with four deterministic paths:
           - Upload a resume file
           - Paste a resume/profile URL
           - Import details from their macOS contact card / vCard
           - Enter information manually

           The app handles UI for each option and returns the user's choice along with any collected data.

        3. When any tool returns with status "waiting for user input", respond with a brief, contextual message:
           "Once you complete the form to the left we can continue."
           This keeps the conversation flowing while the user interacts with UI elements.

        4. After the user completes their choice, proceed naturally based on their selection.

        CAPABILITY-DRIVEN WORKFLOW:
        - Call capabilities_describe at the start of each phase to see what tools are currently available
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
