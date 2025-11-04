//
//  OnboardingInterviewServiceSimplified.swift
//  Sprung
//
//  Simplified bridge between UI and the event-driven coordinator
//

import Foundation
import Observation
import SwiftyJSON
import SwiftOpenAI
import SwiftData

@Observable
@MainActor
final class OnboardingInterviewService {
    // MARK: - Core Dependencies

    let coordinator: OnboardingInterviewCoordinator
    private let documentExtractionService: DocumentExtractionService
    private let knowledgeCardAgent: KnowledgeCardAgent?

    // MARK: - UI State (Synchronous for SwiftUI binding)

    // These need to be cached locally for synchronous access by SwiftUI
    private(set) var messages: [OnboardingMessage] = []
    private(set) var isProcessing: Bool = false
    private(set) var isActive: Bool = false
    private(set) var currentPhase: InterviewPhase = .phase1CoreFacts
    private(set) var wizardStep: OnboardingWizardStep = .introduction

    // Tool-related state from router
    var pendingChoicePrompt: OnboardingChoicePrompt? {
        coordinator.pendingChoicePrompt
    }
    var pendingValidationPrompt: OnboardingValidationPrompt? {
        coordinator.pendingValidationPrompt
    }
    var pendingApplicantProfileRequest: OnboardingApplicantProfileRequest? {
        coordinator.pendingApplicantProfileRequest
    }
    var pendingApplicantProfileIntake: OnboardingApplicantProfileIntakeState? {
        coordinator.pendingApplicantProfileIntake
    }
    var pendingSectionToggleRequest: OnboardingSectionToggleRequest? {
        coordinator.pendingSectionToggleRequest
    }
    var pendingUploadRequests: [OnboardingUploadRequest] {
        coordinator.pendingUploadRequests
    }

    // Preferences
    var allowWebSearch: Bool {
        coordinator.preferences.allowWebSearch
    }
    var allowWritingAnalysis: Bool {
        coordinator.preferences.allowWritingAnalysis
    }

    // Empty stubs for now - will be populated from state
    var pendingExtraction: OnboardingPendingExtraction? { nil }
    var pendingPhaseAdvanceRequest: OnboardingPhaseAdvanceRequest? { nil }
    var uploadedItems: [OnboardingUploadedItem] { [] }
    var artifacts: OnboardingArtifacts { OnboardingArtifacts() }
    var completedWizardSteps: Set<OnboardingWizardStep> { [] }
    var wizardStepStatuses: [OnboardingWizardStep: OnboardingWizardStepStatus] { [:] }
    var lastError: String? { nil }
    var modelAvailabilityMessage: String? { nil }

    // MARK: - Initialization

    init(
        modelContext: ModelContext,
        openAIService: OpenAIService?,
        documentExtractionService: DocumentExtractionService,
        applicantProfileStore: ApplicantProfileStore,
        dataStore: InterviewDataStore
    ) {
        self.documentExtractionService = documentExtractionService
        self.knowledgeCardAgent = openAIService.map { KnowledgeCardAgent(client: $0) }

        let checkpoints = Checkpoints()
        let preferences = OnboardingPreferences()

        self.coordinator = OnboardingInterviewCoordinator(
            openAIService: openAIService,
            applicantProfileStore: applicantProfileStore,
            dataStore: dataStore,
            checkpoints: checkpoints,
            preferences: preferences
        )

        // Subscribe to coordinator state updates
        Task {
            await subscribeToStateUpdates()
        }
    }

    // MARK: - State Synchronization

    private func subscribeToStateUpdates() async {
        // Poll coordinator state periodically to update cached values
        // This is a temporary solution until we can properly refactor the UI
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            Task { @MainActor in
                await self.syncStateFromCoordinator()
            }
        }
    }

    private func syncStateFromCoordinator() async {
        self.isProcessing = await coordinator.isProcessing
        self.isActive = await coordinator.isActive
        self.currentPhase = await coordinator.currentPhase
        self.wizardStep = OnboardingWizardStep(
            rawValue: (await coordinator.wizardStep).rawValue
        ) ?? .introduction
    }

    // MARK: - Interview Lifecycle

    func startInterview(modelId: String, backend: LLMFacade.Backend, resumeExisting: Bool) async {
        _ = await coordinator.startInterview(resumeExisting: resumeExisting)
    }

    func endInterview() async {
        await coordinator.endInterview()
    }

    // MARK: - Tool UI Presentation (for Tool Implementations)

    /// Present a choice prompt card (used by get_user_option tool)
    func presentChoicePrompt(_ prompt: OnboardingChoicePrompt, continuationId: UUID) {
        coordinator.toolRouter.presentChoicePrompt(prompt, continuationId: continuationId)
    }

    /// Clear a choice prompt card
    func clearChoicePrompt(continuationId: UUID) {
        coordinator.toolRouter.clearChoicePrompt(continuationId: continuationId)
    }

    /// Present a validation prompt card (used by submit_for_validation tool)
    func presentValidationPrompt(_ prompt: OnboardingValidationPrompt, continuationId: UUID) {
        coordinator.toolRouter.presentValidationPrompt(prompt, continuationId: continuationId)
    }

    /// Clear a validation prompt card
    func clearValidationPrompt(continuationId: UUID) {
        coordinator.toolRouter.clearValidationPrompt(continuationId: continuationId)
    }

    /// Present an upload request (used by get_user_upload tool)
    func presentUploadRequest(_ request: OnboardingUploadRequest, continuationId: UUID) {
        coordinator.toolRouter.presentUploadRequest(request, continuationId: continuationId)
    }

    /// Present applicant profile intake (used by get_applicant_profile tool)
    func presentApplicantProfileIntake(continuationId: UUID) {
        coordinator.toolRouter.presentApplicantProfileIntake(continuationId: continuationId)
    }

    /// Clear applicant profile intake
    func clearApplicantProfileIntake() {
        coordinator.toolRouter.clearApplicantProfileIntake()
    }

    func hasCheckpoint() -> Bool {
        coordinator.checkpoints.hasCheckpoint()
    }

    // MARK: - Message Handling

    func sendUserMessage(_ text: String) async {
        let messageId = coordinator.appendUserMessage(text)
        messages.append(OnboardingMessage(
            id: messageId,
            role: .user,
            text: text,
            timestamp: Date()
        ))

        // The orchestrator will handle sending to LLM via events
    }

    // MARK: - Tool Interactions

    func submitChoice(optionId: String) {
        if let result = coordinator.submitChoice(optionId: optionId) {
            Task {
                await coordinator.resumeToolContinuation(from: result)
            }
        }
    }

    func submitValidationResponse(
        status: String,
        updatedData: JSON?,
        changes: JSON?,
        notes: String?
    ) {
        let result = coordinator.submitValidationResponse(
            status: status,
            updatedData: updatedData,
            changes: changes,
            notes: notes
        )
        if let result = result {
            Task {
                await coordinator.resumeToolContinuation(from: result)
            }
        }
    }

    func completeUpload(id: UUID, fileURLs: [URL]) async {
        if let result = await coordinator.completeUpload(id: id, fileURLs: fileURLs) {
            await coordinator.resumeToolContinuation(from: result)
        }
    }

    func skipUpload(id: UUID) async {
        if let result = await coordinator.skipUpload(id: id) {
            await coordinator.resumeToolContinuation(from: result)
        }
    }


    // MARK: - Phase Management

    func currentPhase() async -> InterviewPhase {
        await coordinator.currentPhase
    }

    func missingObjectives() async -> [String] {
        await coordinator.missingObjectives()
    }

    func approvePhaseAdvance() async {
        await coordinator.approvePhaseAdvance()
    }

    func denyPhaseAdvance(feedback: String?) async {
        await coordinator.denyPhaseAdvance(feedback: feedback)
    }

    // MARK: - Artifacts

    func hasArtifacts() -> Bool {
        false // Will be implemented when we sync artifacts
    }

    func artifactSummaries() -> [JSON] {
        []
    }

    // MARK: - Cleanup

    func resetStore() async {
        await coordinator.resetStore()
        messages.removeAll()
        isProcessing = false
        isActive = false
    }
}