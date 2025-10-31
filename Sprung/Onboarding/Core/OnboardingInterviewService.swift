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

    var messages: [OnboardingMessage] { coordinator.messages }
    var pendingChoicePrompt: OnboardingChoicePrompt? { coordinator.pendingChoicePrompt }
    var pendingValidationPrompt: OnboardingValidationPrompt? { coordinator.pendingValidationPrompt }
    var pendingApplicantProfileRequest: OnboardingApplicantProfileRequest? { coordinator.pendingApplicantProfileRequest }
   var pendingApplicantProfileIntake: OnboardingApplicantProfileIntakeState? { coordinator.pendingApplicantProfileIntake }
   var pendingSectionToggleRequest: OnboardingSectionToggleRequest? { coordinator.pendingSectionToggleRequest }
   var pendingUploadRequests: [OnboardingUploadRequest] { coordinator.pendingUploadRequests }
    var pendingExtraction: OnboardingPendingExtraction? { coordinator.pendingExtraction }
    var pendingPhaseAdvanceRequest: OnboardingPhaseAdvanceRequest? { coordinator.pendingPhaseAdvanceRequest }
   var uploadedItems: [OnboardingUploadedItem] { coordinator.uploadedItems }
   var artifacts: OnboardingArtifacts { coordinator.artifacts }
   private(set) var schemaIssues: [String] = []
   private(set) var nextQuestions: [OnboardingQuestion] = []

   private var photoPromptIssued = false
   private var hasContactPhoto = false

    var wizardStep: OnboardingWizardStep { coordinator.wizardStep }
    var completedWizardSteps: Set<OnboardingWizardStep> { coordinator.completedWizardSteps }
    var wizardStepStatuses: [OnboardingWizardStep: OnboardingWizardStepStatus] { coordinator.wizardStepStatuses }

    var isProcessing: Bool { coordinator.isProcessing }
    var isActive: Bool { coordinator.isActive }
    var allowWebSearch: Bool { coordinator.preferences.allowWebSearch }
    var allowWritingAnalysis: Bool { coordinator.preferences.allowWritingAnalysis }
    var lastError: String? { coordinator.lastError }

    var preferredModelIdForDisplay: String? {
        coordinator.preferences.preferredModelId
    }

    var preferredBackend: LLMFacade.Backend {
        coordinator.preferences.preferredBackend
    }

    enum ToolWaitingStateInstruction {
        case leaveUnchanged
        case set(InterviewSession.Waiting?)
    }

    // MARK: - Internal state

    private let openAIService: OpenAIService?
    private let applicantProfileStore: ApplicantProfileStore
    private let documentExtractionService: DocumentExtractionService
    @ObservationIgnored private let dataStore = InterviewDataStore()
    @ObservationIgnored private let knowledgeCardAgent: KnowledgeCardAgent?
    @ObservationIgnored let coordinator: OnboardingInterviewCoordinator // All onboarding state lives here; service only exposes a façade
    private var validationRetryCounts: [String: Int] = [:]
    var applicantProfileJSON: JSON? { coordinator.applicantProfileJSON }
    var skeletonTimelineJSON: JSON? { coordinator.skeletonTimelineJSON }

    // MARK: - Init

    init(
        openAIService: OpenAIService?,
        applicantProfileStore: ApplicantProfileStore,
        documentExtractionService: DocumentExtractionService
    ) {
        self.openAIService = openAIService
        self.applicantProfileStore = applicantProfileStore
        self.documentExtractionService = documentExtractionService
        self.knowledgeCardAgent = openAIService.map { KnowledgeCardAgent(client: $0) }

        let interviewState = InterviewState()
        let checkpoints = Checkpoints()
        let promptHandler = PromptInteractionHandler()
        let uploadHandler = UploadInteractionHandler(
            uploadFileService: UploadFileService(),
            uploadStorage: OnboardingUploadStorage(),
            applicantProfileStore: applicantProfileStore,
            dataStore: dataStore,
            extractionProgressHandler: nil
        )
        let profileHandler = ProfileInteractionHandler(contactsImportService: ContactsImportService())
        let sectionHandler = SectionToggleHandler()
        let toolRouter = OnboardingToolRouter(
            promptHandler: promptHandler,
            uploadHandler: uploadHandler,
            profileHandler: profileHandler,
            sectionHandler: sectionHandler
        )
        let wizardTracker = WizardProgressTracker()
        let phaseRegistry = PhaseScriptRegistry()

        self.coordinator = OnboardingInterviewCoordinator(
            chatTranscriptStore: ChatTranscriptStore(),
            toolRouter: toolRouter,
            applicantProfileStore: applicantProfileStore,
            dataStore: dataStore,
            checkpoints: checkpoints,
            wizardTracker: wizardTracker,
            phaseRegistry: phaseRegistry,
            interviewState: interviewState,
            openAIService: openAIService
        )

        let progressHandler: ExtractionProgressHandler = { [weak coordinator] update in
            guard let coordinator else { return }
            await MainActor.run {
                coordinator.updateExtractionProgress(with: update)
            }
        }
        uploadHandler.updateExtractionProgressHandler(progressHandler)
        coordinator.addObjectiveStatusObserver { [weak self] update in
            guard let self else { return }
            self.handleObjectiveStatusUpdate(update)
        }
        registerTools(progressHandler: progressHandler)
    }

    // MARK: - Tool Registration

    private func registerTools(progressHandler: ExtractionProgressHandler?) {
        let registry = coordinator.toolRegistry
        registry.register(GetUserOptionTool(service: self))
        registry.register(SubmitForValidationTool(service: self))
        registry.register(ValidateApplicantProfileTool(service: self))
        registry.register(PersistDataTool(dataStore: dataStore))
        registry.register(GetMacOSContactCardTool())
        registry.register(GetApplicantProfileTool(service: self))
        registry.register(GetUserUploadTool(service: self))
        registry.register(
            ExtractDocumentTool(
                extractionService: documentExtractionService,
                progressHandler: progressHandler
            )
        )
        registry.register(SetObjectiveStatusTool(service: self))
        registry.register(NextPhaseTool(service: self))
        registry.register(ListArtifactsTool(service: self))
        registry.register(GetArtifactRecordTool(service: self))
        registry.register(CancelUserUploadTool(service: self))
        registry.register(RequestRawArtifactFileTool(service: self))
        registry.register(
            GenerateKnowledgeCardTool(agentProvider: { [weak self] in
                self?.knowledgeCardAgent
            })
        )
        registry.register(CreateTimelineCardTool(service: self))
        registry.register(UpdateTimelineCardTool(service: self))
        registry.register(ReorderTimelineCardsTool(service: self))
        registry.register(DeleteTimelineCardTool(service: self))
    }

    func currentSession() async -> InterviewSession {
        await coordinator.currentSession()
    }

    func hasRestorableCheckpoint() async -> Bool {
        await coordinator.hasRestorableCheckpoint()
    }

    func artifactSummaries() -> [JSON] {
        coordinator.artifacts.artifactRecords.map { record in
            var summary = JSON()
            summary["id"].string = record["id"].stringValue
            summary["filename"].string = record["filename"].stringValue
            summary["content_type"].string = record["content_type"].stringValue
            if let size = record["size_bytes"].int {
                summary["size_bytes"].int = size
            }
            if let sha = record["sha256"].string, !sha.isEmpty {
                summary["sha256"].string = sha
            }

            let metadata = record["metadata"]
            if metadata != .null {
                var sanitized = metadata
                if sanitized["inline_base64"] != .null {
                    sanitized["inline_base64"] = .null
                    summary["has_inline_payload"].bool = true
                }
                summary["metadata"] = sanitized
            }

            return summary
        }
    }

    func artifactRecordDetail(id: String) -> JSON? {
        coordinator.artifactRecord(id: id)
    }

    func hasArtifacts() -> Bool {
        !coordinator.artifacts.artifactRecords.isEmpty
    }

    func hasPendingUploadRequests() -> Bool {
        !coordinator.pendingUploadRequests.isEmpty
    }

    func missingObjectives() async -> [String] {
        await coordinator.missingObjectives()
    }

    func nextPhaseIdentifier() async -> InterviewPhase? {
        await coordinator.nextPhase()
    }

    func advancePhase() async -> InterviewPhase? {
        await coordinator.advancePhase()
    }

    func updateObjectiveStatus(objectiveId: String, status: String) async throws -> JSON {
        try await coordinator.updateObjectiveStatus(objectiveId: objectiveId, status: status)
    }

    func hasActivePhaseAdvanceRequest() -> Bool {
        coordinator.hasActivePhaseAdvanceRequest()
    }

    func currentPhaseAdvanceAwaitingPayload() -> JSON? {
        coordinator.currentPhaseAdvanceAwaitingPayload()
    }

    func cachedPhaseAdvanceBlockedResponse(missing: [String], overrides: [String]) async -> JSON? {
        await coordinator.cachedPhaseAdvanceBlockedResponse(missing: missing, overrides: overrides)
    }

    func cachePhaseAdvanceBlockedResponse(missing: [String], overrides: [String], response: JSON) async {
        await coordinator.cachePhaseAdvanceBlockedResponse(missing: missing, overrides: overrides, response: response)
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
        await coordinator.logPhaseAdvanceEvent(
            status: status,
            overrides: overrides,
            missing: missing,
            reason: reason,
            userDecision: userDecision,
            advancedTo: advancedTo,
            currentPhase: currentPhase
        )
    }

    func presentPhaseAdvanceRequest(_ request: OnboardingPhaseAdvanceRequest, continuationId: UUID) {
        coordinator.presentPhaseAdvanceRequest(request, continuationId: continuationId)
    }

    func approvePhaseAdvanceRequest() async {
        await coordinator.approvePhaseAdvanceRequest()
    }

    func denyPhaseAdvanceRequest(feedback: String?) async {
        await coordinator.denyPhaseAdvanceRequest(feedback: feedback)
    }

    // MARK: - Interview Lifecycle

    func startInterview(modelId: String, backend: LLMFacade.Backend, resumeExisting: Bool) async {
        resetLocalTransientState()
        await coordinator.startInterview(modelId: modelId, backend: backend, resumeExisting: resumeExisting)
    }

    func sendMessage(_ text: String) async {
        await coordinator.sendMessage(text)
    }

    func resetInterview() {
        coordinator.resetInterview()
        resetLocalTransientState()
    }

    // MARK: - Phase Handling

    func setPhase(_ step: OnboardingWizardStep) {
        coordinator.setWizardStep(step)
    }

    // MARK: - Preferences

    func setPreferredDefaults(
        modelId: String,
        backend: LLMFacade.Backend,
        webSearchAllowed: Bool
    ) {
        coordinator.setPreferredDefaults(
            modelId: modelId,
            backend: backend,
            webSearchAllowed: webSearchAllowed
        )
    }

    func setWritingAnalysisConsent(_ allowed: Bool) {
        coordinator.setWritingAnalysisConsent(allowed)
    }

    func recordObjective(
        _ id: String,
        status: ObjectiveStatus,
        source: String,
        details: [String: String]? = nil
    ) {
        Logger.info("🧾 Recording objective id=\(id) status=\(status.rawValue) source=\(source)", category: .ai, metadata: details ?? [:])
        coordinator.recordObjectiveStatus(id, status: status, source: source, details: details)
    }

    // MARK: - Tool continuation helpers

    func resumeToolContinuation(
        from result: (UUID, JSON)?,
        waitingState: ToolWaitingStateInstruction = .leaveUnchanged,
        persistCheckpoint shouldPersist: Bool = false
    ) async {
        guard let (continuationId, payload) = result else { return }

        switch waitingState {
        case .leaveUnchanged:
            break
        case .set(let waiting):
            coordinator.updateWaitingState(waiting)
        }

        if shouldPersist {
            await coordinator.persistCheckpoint()
        }

        await coordinator.resumeToolContinuation(id: continuationId, payload: payload)
    }

    // MARK: - Choice Prompt Handling

    func presentChoicePrompt(prompt: OnboardingChoicePrompt, continuationId: UUID) {
        coordinator.presentChoicePrompt(prompt, continuationId: continuationId)
        coordinator.setProcessingState(false)
    }

    func clearChoicePrompt(continuationId: UUID) {
        coordinator.clearChoicePrompt(continuationId: continuationId)
    }

    func resolveChoice(selectionIds: [String]) async {
        guard let result = coordinator.resolveChoice(selectionIds: selectionIds) else { return }
        let (continuationId, payload) = result
        await coordinator.resumeToolContinuation(id: continuationId, payload: payload)
    }

    func cancelChoicePrompt(reason: String) async {
        guard let result = coordinator.cancelChoicePrompt(reason: reason) else { return }
        let (continuationId, payload) = result
        Logger.debug("User cancelled choice prompt: \(reason)")
        await coordinator.resumeToolContinuation(id: continuationId, payload: payload)
    }

    // MARK: - Applicant Profile Handling

    func presentApplicantProfileRequest(_ request: OnboardingApplicantProfileRequest, continuationId: UUID) {
        coordinator.presentApplicantProfileRequest(request, continuationId: continuationId)
        coordinator.setProcessingState(false)
        coordinator.updateWaitingState(.validation)
    }

    func clearApplicantProfileRequest(continuationId: UUID) {
        coordinator.clearApplicantProfileRequest(continuationId: continuationId)
    }

    // MARK: - Applicant Profile Intake

    func presentApplicantProfileIntake(continuationId: UUID) {
        coordinator.presentApplicantProfileIntake(continuationId: continuationId)
        coordinator.setProcessingState(false)
        coordinator.updateWaitingState(.selection)
    }

    func resetApplicantProfileIntakeToOptions() {
        coordinator.resetApplicantProfileIntakeToOptions()
    }

    func beginApplicantProfileManualEntry() {
        coordinator.beginApplicantProfileManualEntry()
        recordObjective("contact_source_selected", status: .completed, source: "user_manual")
    }

    func beginApplicantProfileURL() {
        coordinator.beginApplicantProfileURL()
        recordObjective("contact_source_selected", status: .completed, source: "user_url")
    }

    func beginApplicantProfileUpload() {
        guard let result = coordinator.beginApplicantProfileUpload() else { return }
        presentUploadRequest(result.request, continuationId: result.continuationId)
        recordObjective("contact_source_selected", status: .completed, source: "resume_upload")
    }

    func beginApplicantProfileContactsFetch() {
        coordinator.beginApplicantProfileContactsFetch()
        recordObjective("contact_source_selected", status: .completed, source: "contacts")
    }

    func submitApplicantProfileURL(_ urlString: String) async {
        guard let result = coordinator.submitApplicantProfileURL(urlString) else { return }
        let (continuationId, payload) = result
        coordinator.updateWaitingState(nil)
        let trimmedURL = payload["url"].stringValue
        sendApplicantProfileURLStatus(url: trimmedURL, payload: payload)
        recordObjective(
            "contact_data_collected",
            status: .completed,
            source: "user_url",
            details: ["url": urlString]
        )
        await coordinator.resumeToolContinuation(id: continuationId, payload: payload)
    }

    func completeApplicantProfileDraft(_ draft: ApplicantProfileDraft, source: OnboardingApplicantProfileIntakeState.Source) async {
        guard let result = coordinator.completeApplicantProfileDraft(draft, source: source) else { return }
        let (continuationId, payload) = result
        coordinator.updateWaitingState(nil)
        let sourceTag: String = (source == .contacts) ? "contacts" : "manual"
        let dataJSON = payload["data"]
        if dataJSON != .null {
            let note: String
            if source == .contacts {
                note = "Data imported from macOS Contacts. User confirmed details in the intake card; treat as authoritative."
            } else {
                note = "User manually entered and confirmed data in the intake form."
            }
            sendApplicantProfileIntakeStatus(
                source: sourceTag,
                note: note,
                payload: dataJSON
            )
            await persistApplicantProfile(dataJSON)
        }
        recordObjective(
            "contact_data_collected",
            status: .completed,
            source: sourceTag
        )
        if source == .contacts || source == .manual {
            recordObjective(
                "contact_data_validated",
                status: .completed,
                source: source == .contacts ? "contacts_auto" : "manual_auto"
            )
        }
        await coordinator.resumeToolContinuation(id: continuationId, payload: payload)
    }

    func cancelApplicantProfileIntake(reason: String) async {
        guard let result = coordinator.cancelApplicantProfileIntake(reason: reason) else { return }
        let (continuationId, payload) = result
        Logger.debug("Applicant profile intake cancelled: \(reason)")
        coordinator.updateWaitingState(nil)
        recordObjective(
            "contact_data_collected",
            status: .pending,
            source: "user_cancelled",
            details: reason.isEmpty ? nil : ["reason": reason]
        )
        await coordinator.resumeToolContinuation(id: continuationId, payload: payload)
    }

    func resolveApplicantProfile(with draft: ApplicantProfileDraft) async {
        guard let result = coordinator.resolveApplicantProfile(with: draft) else { return }
        let (continuationId, payload) = result
        coordinator.updateWaitingState(nil)
        let dataJSON = payload["data"]
        if dataJSON != .null {
            sendApplicantProfileValidationStatus(
                status: payload["status"].stringValue,
                details: ["source": "user_validation"],
                payload: dataJSON
            )
            await persistApplicantProfile(dataJSON)
        } else {
            sendApplicantProfileValidationStatus(
                status: payload["status"].stringValue,
                details: ["source": "user_validation"],
                payload: nil
            )
        }
        recordObjective(
            "contact_data_collected",
            status: .completed,
            source: "llm_validation"
        )
        recordObjective(
            "contact_data_validated",
            status: .completed,
            source: "user_validation"
        )
        await coordinator.resumeToolContinuation(id: continuationId, payload: payload)
    }

    func rejectApplicantProfile(reason: String) async {
        guard let result = coordinator.rejectApplicantProfile(reason: reason) else { return }
        let (continuationId, payload) = result
        coordinator.updateWaitingState(nil)
        var details: [String: String] = ["source": "user_validation"]
        if !reason.isEmpty {
            details["user_notes"] = reason
        }
        sendApplicantProfileValidationStatus(
            status: payload["status"].stringValue,
            details: details,
            payload: nil
        )
        recordObjective(
            "contact_data_validated",
            status: .pending,
            source: "user_rejected",
            details: reason.isEmpty ? nil : ["reason": reason]
        )
        await coordinator.resumeToolContinuation(id: continuationId, payload: payload)
    }

    // MARK: - Validation Prompt Handling

    func resolveSectionToggle(enabled: [String]) async {
        guard let result = coordinator.resolveSectionToggle(enabled: enabled) else { return }
        let (continuationId, payload) = result
        coordinator.updateWaitingState(nil)
        await coordinator.persistCheckpoint()
        recordObjective(
            "enabled_sections",
            status: .completed,
            source: "user_selection",
            details: ["count": "\(enabled.count)"]
        )
        await coordinator.resumeToolContinuation(id: continuationId, payload: payload)
    }

    func rejectSectionToggle(reason: String) async {
        guard let result = coordinator.rejectSectionToggle(reason: reason) else { return }
        let (continuationId, payload) = result
        coordinator.updateWaitingState(nil)
        recordObjective(
            "enabled_sections",
            status: .pending,
            source: "user_rejected",
            details: reason.isEmpty ? nil : ["reason": reason]
        )
        await coordinator.resumeToolContinuation(id: continuationId, payload: payload)
    }

    func presentValidationPrompt(prompt: OnboardingValidationPrompt, continuationId: UUID) {
        coordinator.presentValidationPrompt(prompt, continuationId: continuationId)
        coordinator.setProcessingState(false)
        coordinator.updateWaitingState(.validation)
    }

    func presentUploadRequest(_ request: OnboardingUploadRequest, continuationId: UUID) {
        coordinator.presentUploadRequest(request, continuationId: continuationId)
        coordinator.setProcessingState(false)
        coordinator.updateWaitingState(.upload)
    }

    func clearValidationPrompt(continuationId: UUID) {
        coordinator.clearValidationPrompt(continuationId: continuationId)
    }

    func submitValidationResponse(
        status: String,
        updatedData: JSON?,
        changes: JSON?,
        notes: String?
    ) async {
        guard let result = coordinator.submitValidationResponse(
            status: status,
            updatedData: updatedData,
            changes: changes,
            notes: notes
        ) else { return }
        let (continuationId, payload) = result
        await coordinator.resumeToolContinuation(id: continuationId, payload: payload)
    }

    func cancelValidation(reason: String) async {
        guard let result = coordinator.cancelValidation(reason: reason) else { return }
        let (continuationId, payload) = result
        Logger.debug("User cancelled validation request: \(reason)")
        recordObjective(
            "contact_data_validated",
            status: .pending,
            source: "user_cancelled",
            details: reason.isEmpty ? nil : ["reason": reason]
        )
        await coordinator.resumeToolContinuation(id: continuationId, payload: payload)
    }

    func completeUploadRequest(id: UUID, fileURLs: [URL]) async {
        guard let result = await coordinator.completeUpload(id: id, fileURLs: fileURLs) else { return }
        let (continuationId, payload) = result
        coordinator.updateWaitingState(nil)
        sendUploadStatus(payload)
        await coordinator.resumeToolContinuation(id: continuationId, payload: payload)
    }

    func completeUploadRequest(id: UUID, link: URL) async {
        guard let result = await coordinator.completeUpload(id: id, link: link) else { return }
        let (continuationId, payload) = result
        coordinator.updateWaitingState(nil)
        sendUploadStatus(payload)
        await coordinator.resumeToolContinuation(id: continuationId, payload: payload)
    }

    func skipUploadRequest(id: UUID) async {
        guard let result = await coordinator.skipUpload(id: id) else { return }
        let (continuationId, payload) = result
        coordinator.updateWaitingState(nil)
        sendUploadStatus(payload)
        await coordinator.resumeToolContinuation(id: continuationId, payload: payload)
    }

    func cancelPendingUploadRequest(reason: String?) async -> JSON? {
        guard let request = coordinator.pendingUploadRequests.first else { return nil }
        guard let result = await coordinator.cancelUpload(id: request.id, reason: reason) else { return nil }
        let (continuationId, payload) = result
        coordinator.updateWaitingState(nil)
        sendUploadStatus(payload)
        await coordinator.resumeToolContinuation(id: continuationId, payload: payload)
        return payload
    }

    // MARK: - Callback Handling

    @discardableResult
    func appendAssistantMessage(_ text: String, reasoningExpected: Bool = false) -> UUID {
        let id = coordinator.appendAssistantMessage(text, reasoningExpected: reasoningExpected)
        Logger.debug("[Stream] Assistant message posted immediately (len: \(text.count))")
        return id
    }

    func beginAssistantStream(initialText: String = "", reasoningExpected: Bool = false) -> UUID {
        let id = coordinator.beginAssistantStream(initialText: initialText, reasoningExpected: reasoningExpected)
        Logger.debug("[Stream] Started assistant stream \(id.uuidString) (len: \(initialText.count))")
        return id
    }

    func updateAssistantStream(id: UUID, text: String) {
        coordinator.updateAssistantStream(id: id, text: text)
        Logger.debug("[Stream] Update for message \(id.uuidString) (len: \(text.count))")
    }

    func finalizeAssistantStream(id: UUID, text: String) {
        let elapsed = coordinator.finalizeAssistantStream(id: id, text: text)
        Logger.debug("[Stream] Completed message \(id.uuidString) in \(String(format: "%.3f", elapsed))s (len: \(text.count))")
    }

    func updateReasoningSummary(_ summary: String, for messageId: UUID, isFinal: Bool) {
        coordinator.updateReasoningSummary(summary, for: messageId, isFinal: isFinal)
        let tag = isFinal ? "finalized" : "update"
        Logger.debug("[Stream] Reasoning summary \(tag) for message \(messageId.uuidString) (len: \(summary.count))")
    }

    func appendSystemMessage(_ text: String) {
        coordinator.appendSystemMessage(text)
    }

    func recordError(_ message: String) {
        coordinator.recordError(message)
    }

    func updateWaitingState(_ waiting: InterviewSession.Waiting?) {
        coordinator.updateWaitingState(waiting)
    }

    func setExtractionStatus(_ status: OnboardingPendingExtraction?) {
        coordinator.setExtractionStatus(status)
    }

    func updateExtractionProgress(_ update: ExtractionProgressUpdate) {
        coordinator.updateExtractionProgress(with: update)
    }

    // MARK: - Private Helpers

    private func appendUserMessage(_ text: String) {
        coordinator.appendUserMessage(text)
    }

    private func resetLocalTransientState() {
        schemaIssues.removeAll()
        nextQuestions.removeAll()
        photoPromptIssued = false
        if let imageValue = coordinator.applicantProfileJSON?["image"],
           imageValue != .null,
           !(imageValue.stringValue.isEmpty) {
            hasContactPhoto = true
        } else {
            hasContactPhoto = false
        }
    }

    private func sendDeveloperStatus(
        title: String,
        details: [String: String] = [:],
        payload: JSON? = nil
    ) {
        let readableDetails = details
            .filter { !$0.value.isEmpty }
            .sorted { $0.key < $1.key }
            .map { "• \($0.key): \($0.value)" }
            .joined(separator: "\n")

        var payloadText: String?
        if let payload, payload != .null {
            payloadText = payload.rawString(options: [.sortedKeys]) ?? payload.description
        }

        var logMetadata = details
        if let payloadText {
            logMetadata["payload"] = payloadText
        }

        Logger.log(.info, "📤 Developer status queued: \(title)", category: .ai, metadata: logMetadata)

        var message = "Developer status: \(title)"
        if !readableDetails.isEmpty {
            message += "\n\nDetails:\n\(readableDetails)"
        }
        if let payloadText {
            message += "\n\nPayload:\n\(payloadText)"
        }

        coordinator.addDeveloperStatus(message)
    }

    private func sendApplicantProfileIntakeStatus(
        source: String,
        note: String,
        payload: JSON
    ) {
        let message = DeveloperMessageTemplates.contactIntakeCompleted(
            source: source,
            note: note,
            payload: payload
        )
        sendDeveloperStatus(title: message.title, details: message.details, payload: message.payload)
    }

    private func sendApplicantProfileURLStatus(url: String, payload: JSON) {
        let message = DeveloperMessageTemplates.contactURLSubmitted(
            mode: payload["mode"].stringValue,
            status: payload["status"].stringValue,
            url: url,
            payload: payload
        )
        sendDeveloperStatus(title: message.title, details: message.details, payload: message.payload)
    }

    private func sendApplicantProfileValidationStatus(
        status: String,
        details extraDetails: [String: String] = [:],
        payload: JSON?
    ) {
        let message = DeveloperMessageTemplates.contactValidation(
            status: status,
            extraDetails: extraDetails,
            payload: payload
        )
        sendDeveloperStatus(title: message.title, details: message.details, payload: message.payload)
    }

    private func sendUploadStatus(_ payload: JSON) {
        let message = DeveloperMessageTemplates.uploadStatus(
            status: payload["status"].stringValue,
            kind: payload["kind"].string,
            targetKey: payload["targetKey"].string,
            payload: payload
        )
        sendDeveloperStatus(title: message.title, details: message.details, payload: message.payload)
    }

    func persistApplicantProfile(_ json: JSON) async {
        let displayName = applicantDisplayName(from: json)

        if let existing = coordinator.applicantProfileJSON, existing == json {
            Logger.info("ℹ️ Applicant profile unchanged; skipping persistence.", category: .ai)
            let message = DeveloperMessageTemplates.profileUnchanged(displayName: displayName, payload: json)
            sendDeveloperStatus(title: message.title, details: message.details, payload: message.payload)
            return
        }

        coordinator.storeApplicantProfile(json)
        await coordinator.persistCheckpoint()
        let message = DeveloperMessageTemplates.profilePersisted(displayName: displayName, payload: json)
        sendDeveloperStatus(title: message.title, details: message.details, payload: message.payload)
    }

    private func enqueuePhotoFollowUp(extraDetails: [String: String]) {
        guard photoPromptIssued == false else { return }
        guard hasContactPhoto == false else { return }

        photoPromptIssued = true

        var details = extraDetails
        if let photoStatus = coordinator.applicantProfileJSON?["meta"]["photo_status"].string,
           !photoStatus.isEmpty {
            details["photo_status"] = photoStatus
        }

        let uploadPayload = """
        {
          \"upload_type\": \"generic\",
          \"prompt_to_user\": \"Upload a profile headshot. You can drag in a JPG, PNG, HEIC, or WEBP image, or paste an image URL.\",
          \"allowed_types\": [\"jpg\", \"jpeg\", \"png\", \"heic\", \"webp\"],
          \"allow_multiple\": false,
          \"allow_url\": true,
          \"target_key\": \"basics.image\"
        }
        """

        let instructions = "Contact details validated. Immediately call get_user_upload using the payload below so the user sees the upload card right away. After the tool call, send a brief chat message asking whether they’d like to add a photo (let them know they can skip). If they decline in chat, acknowledge and move on without re-calling the tool.\n\nget_user_upload payload:\n\(uploadPayload)"

        Logger.info("🎯 Triggering photo follow-up after validation", category: .ai, metadata: details)
        sendDeveloperStatus(title: instructions, details: details)
    }

    func requestPhotoFollowUp(reason: String) {
        enqueuePhotoFollowUp(extraDetails: ["reason": reason])
    }

    func storeApplicantProfileImage(data: Data, mimeType: String?) {
        let mimeString = mimeType ?? "unknown"
        coordinator.storeApplicantProfileImage(data: data, mimeType: mimeType)
        Task { await coordinator.persistCheckpoint() }
        Logger.debug("Applicant profile image updated (\(data.count) bytes, mime: \(mimeString)")
        recordObjective(
            "contact_photo_collected",
            status: .completed,
            source: "photo_upload",
            details: ["bytes": "\(data.count)"]
        )
        hasContactPhoto = true
    }

    func fetchRawArtifactFile(artifactId: String) -> (id: String, data: Data, mimeType: String, filename: String, sha256: String?)? {
        guard let payload = coordinator.rawArtifactFile(for: artifactId) else {
            return nil
        }
        return (
            id: artifactId,
            data: payload.data,
            mimeType: payload.mimeType,
            filename: payload.filename,
            sha256: payload.sha256
        )
    }

    // MARK: - Timeline Card Management

    func createTimelineCard(fields: JSON) async -> JSON {
        var state = currentTimelineState()
        var newCard = TimelineCard(id: UUID().uuidString, fields: fields)
        while state.cards.contains(where: { $0.id == newCard.id }) {
            newCard.id = UUID().uuidString
        }
        state.cards.append(newCard)
        let updated = await persistTimeline(cards: state.cards, meta: state.meta)
        Logger.info("🆕 Timeline card created (id: \(newCard.id))", category: .ai)

        var response = JSON()
        response["card"] = newCard.json
        response["timeline"] = updated
        return response
    }

    func updateTimelineCard(id: String, fields: JSON) async throws -> JSON {
        var state = currentTimelineState()
        guard let index = state.cards.firstIndex(where: { $0.id == id }) else {
            throw TimelineCardError.cardNotFound(id)
        }

        let updatedCard = state.cards[index].applying(fields: fields)
        state.cards[index] = updatedCard
        let updatedTimeline = await persistTimeline(cards: state.cards, meta: state.meta)
        Logger.info("✏️ Timeline card updated (id: \(id))", category: .ai)

        var response = JSON()
        response["card"] = updatedCard.json
        response["timeline"] = updatedTimeline
        return response
    }

    func reorderTimelineCards(with orderedIds: [String]) async throws -> JSON {
        var state = currentTimelineState()
        let existingIds = state.cards.map { $0.id }
        guard Set(existingIds) == Set(orderedIds), orderedIds.count == existingIds.count else {
            throw TimelineCardError.invalidOrder(orderedIds)
        }

        var reordered: [TimelineCard] = []
        reordered.reserveCapacity(orderedIds.count)
        for identifier in orderedIds {
            if let card = state.cards.first(where: { $0.id == identifier }) {
                reordered.append(card)
            }
        }
        state.cards = reordered
        let updatedTimeline = await persistTimeline(cards: state.cards, meta: state.meta)
        Logger.info("🔀 Timeline cards reordered", category: .ai)

        return updatedTimeline
    }

    func deleteTimelineCard(id: String) async throws -> JSON {
        var state = currentTimelineState()
        guard let index = state.cards.firstIndex(where: { $0.id == id }) else {
            throw TimelineCardError.cardNotFound(id)
        }

        state.cards.remove(at: index)
        let updatedTimeline = await persistTimeline(cards: state.cards, meta: state.meta)
        Logger.info("🗑️ Timeline card deleted (id: \(id))", category: .ai)

        return updatedTimeline
    }

    private func currentTimelineState() -> (cards: [TimelineCard], meta: JSON?) {
        if let timeline = coordinator.skeletonTimelineJSON {
            let normalized = TimelineCardAdapter.normalizedTimeline(timeline)
            if normalized != timeline {
                coordinator.storeSkeletonTimeline(normalized)
            }
            return TimelineCardAdapter.cards(from: normalized)
        }
        return ([], nil)
    }

    private func persistTimeline(cards: [TimelineCard], meta: JSON?) async -> JSON {
        let updatedTimeline = TimelineCardAdapter.makeTimelineJSON(cards: cards, meta: meta)
        coordinator.storeSkeletonTimeline(updatedTimeline)
        await coordinator.persistCheckpoint()
        return updatedTimeline
    }

    private func applicantDisplayName(from json: JSON) -> String? {
        func cleaned(_ value: String?) -> String? {
            guard let value else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        if let direct = cleaned(json["name"].string) {
            return direct
        }
        if let basicsName = cleaned(json["basics"]["name"].string) {
            return basicsName
        }
        if let full = cleaned(json["full_name"].string) {
            return full
        }
        if let basicsFull = cleaned(json["basics"]["full_name"].string) {
            return basicsFull
        }

        let given = cleaned(json["basics"]["given"].string ?? json["first_name"].string)
        let family = cleaned(json["basics"]["family"].string ?? json["last_name"].string)
        if let given, let family {
            return "\(given) \(family)"
        }
        return given ?? family
    }

    private func handleObjectiveStatusUpdate(_ update: OnboardingInterviewCoordinator.ObjectiveStatusUpdate) {
        switch update.id {
        case "contact_photo_collected":
            hasContactPhoto = update.status == .completed
        default:
            break
        }

        Task { @MainActor in
            let session = await coordinator.currentSession()
            guard let script = coordinator.phaseRegistry.currentScript(for: session),
                  let workflow = script.workflow(for: update.id) else { return }

            let context = ObjectiveWorkflowContext(
                session: session,
                status: update.status,
                details: update.details ?? ["source": update.source]
            )

            let outputs = workflow.outputs(for: update.status, context: context)
            applyWorkflowOutputs(outputs)
        }
    }

    private func applyWorkflowOutputs(_ outputs: [ObjectiveWorkflowOutput]) {
        guard !outputs.isEmpty else { return }

        for output in outputs {
            switch output {
            case let .developerMessage(title, details, payload):
                sendDeveloperStatus(title: title, details: details, payload: payload)
            case let .triggerPhotoFollowUp(extraDetails):
                enqueuePhotoFollowUp(extraDetails: extraDetails)
            }
        }
    }

    // MARK: - Validation Retry Tracking

    /// Records a missing validation payload occurrence and returns the updated attempt count.
    func registerMissingValidationPayload(for canonicalType: String) -> Int {
        let key = canonicalType
        let next = (validationRetryCounts[key] ?? 0) + 1
        validationRetryCounts[key] = next
        Logger.warning("⚠️ Missing validation payload for \(canonicalType) (attempt \(next))", category: .ai)
        return next
    }

    /// Resets the retry counter for a validation data type after a successful submission.
    func resetValidationRetry(for canonicalType: String) {
        validationRetryCounts[canonicalType] = 0
    }

    /// Provides a cached payload for validation fallback when the LLM omits data repeatedly.
    func fallbackValidationPayload(for canonicalType: String) -> JSON? {
        guard canonicalType == "applicant_profile" else { return nil }
        if let draft = coordinator.toolRouter.profileHandler.lastSubmittedDraft, draft != .null {
            return draft
        }
        return applicantProfileJSON
    }
}
