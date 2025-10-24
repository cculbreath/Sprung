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
    private(set) var applicantProfileJSON: JSON?
    private(set) var skeletonTimelineJSON: JSON?
    private var systemPrompt: String

    // MARK: - Init

    init(openAIService: OpenAIService?, applicantProfileStore: ApplicantProfileStore) {
        self.openAIService = openAIService
        self.applicantProfileStore = applicantProfileStore
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
        applicantProfileJSON = nil
        skeletonTimelineJSON = nil
        artifacts.applicantProfile = nil
        artifacts.skeletonTimeline = nil
        nextQuestions.removeAll()
        lastError = nil
        wizardStep = .introduction
        completedWizardSteps.removeAll()
        wizardStepStatuses.removeAll()
        updateWaitingState(nil)
    }

    private func restoreFromCheckpointIfAvailable() async -> Bool {
        guard let snapshot = await checkpoints.restoreLatest() else {
            return false
        }

        let (session, profileJSON, timelineJSON) = snapshot
        await interviewState.restore(from: session)
        applyWizardProgress(from: session)

        if let profileJSON {
            storeApplicantProfile(profileJSON)
        }
        if let timelineJSON {
            storeSkeletonTimeline(timelineJSON)
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
            }
        )

        return InterviewOrchestrator(
            client: service,
            state: interviewState,
            toolExecutor: toolExecutor,
            checkpoints: checkpoints,
            callbacks: callbacks,
            systemPrompt: systemPrompt
        )
    }

    private func storeApplicantProfile(_ json: JSON) {
        applicantProfileJSON = json
        let draft = ApplicantProfileDraft(json: json)
        let profile = applicantProfileStore.currentProfile()
        draft.apply(to: profile)
        applicantProfileStore.save(profile)
        artifacts.applicantProfile = json
    }

    private func storeSkeletonTimeline(_ json: JSON) {
        skeletonTimelineJSON = json
        artifacts.skeletonTimeline = json
    }

    private func removeUploadRequest(id: UUID) {
        pendingUploadRequests.removeAll { $0.id == id }
    }

    private static func defaultSystemPrompt() -> String {
        """
        You are the Sprung onboarding interviewer. Coordinate a structured interview that uses tools for
        collecting information, validating data with the user, and persisting progress. Always prefer tools
        instead of free-form instructions when gathering data. Keep responses concise unless additional detail
        is requested. Confirm major milestones with the user and respect their decisions.
        """
    }
}
