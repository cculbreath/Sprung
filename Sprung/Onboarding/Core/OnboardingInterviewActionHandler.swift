//
//  OnboardingInterviewActionHandler.swift
//  Sprung
//
//  Thin command facade used by SwiftUI views to drive the onboarding interview
//  runtime. Most advanced actions are stubbed for post-M0 milestones.
//

import Foundation
import SwiftyJSON

@MainActor
struct OnboardingInterviewActionHandler {
    private let service: OnboardingInterviewService
    private let coordinator: OnboardingInterviewCoordinator

    init(service: OnboardingInterviewService, coordinator: OnboardingInterviewCoordinator? = nil) {
        self.service = service
        self.coordinator = coordinator ?? service.coordinator
    }

    // MARK: - Core actions

    func startInterview(modelId: String, backend: LLMFacade.Backend, resumeExisting: Bool) async {
        await service.startInterview(modelId: modelId, backend: backend, resumeExisting: resumeExisting)
    }

    func sendMessage(_ text: String) async {
        await service.sendMessage(text)
    }

    func resetInterview() {
        service.resetInterview()
    }

    func setWritingAnalysisConsent(_ allowed: Bool) {
        service.setWritingAnalysisConsent(allowed)
    }

    // MARK: - Tool-driven actions

    func resolveChoice(selectionIds: [String]) async {
        let result = coordinator.resolveChoice(selectionIds: selectionIds)
        await service.resumeToolContinuation(from: result)
    }

    func cancelChoicePrompt(reason: String) async {
        let result = coordinator.cancelChoicePrompt(reason: reason)
        await service.resumeToolContinuation(from: result)
    }

    func submitValidation(
        status: String,
        updatedData: JSON? = nil,
        changes: JSON? = nil,
        notes: String? = nil
    ) async {
        let result = coordinator.submitValidationResponse(
            status: status,
            updatedData: updatedData,
            changes: changes,
            notes: notes
        )
        await service.resumeToolContinuation(from: result)
    }

    func cancelValidation(reason: String) async {
        let result = coordinator.cancelValidation(reason: reason)
        await service.resumeToolContinuation(from: result)
    }

    // MARK: - Applicant Profile Intake

    func fetchApplicantProfileFromContacts() async {
        coordinator.beginApplicantProfileContactsFetch()
    }

    func approveApplicantProfile(draft: ApplicantProfileDraft) async {
        let result = coordinator.resolveApplicantProfile(with: draft)
        await service.resumeToolContinuation(from: result, waitingState: .set(nil))
    }

    func declineApplicantProfile(reason: String) async {
        let result = coordinator.rejectApplicantProfile(reason: reason)
        await service.resumeToolContinuation(from: result, waitingState: .set(nil))
    }

    func beginApplicantProfileManualEntry() {
        coordinator.beginApplicantProfileManualEntry()
    }

    func beginApplicantProfileURLEntry() {
        coordinator.beginApplicantProfileURL()
    }

    func beginApplicantProfileUpload() async {
        guard let result = coordinator.beginApplicantProfileUpload() else { return }
        service.presentUploadRequest(result.request, continuationId: result.continuationId)
    }

    func resetApplicantProfileIntake() {
        coordinator.resetApplicantProfileIntakeToOptions()
    }

    func submitApplicantProfileURL(_ urlString: String) async {
        let result = coordinator.submitApplicantProfileURL(urlString)
        await service.resumeToolContinuation(from: result, waitingState: .set(nil))
    }

    func completeApplicantProfileDraft(_ draft: ApplicantProfileDraft, source: OnboardingApplicantProfileIntakeState.Source) async {
        let result = coordinator.completeApplicantProfileDraft(draft, source: source)
        await service.resumeToolContinuation(from: result, waitingState: .set(nil))
    }

    func cancelApplicantProfileIntake(reason: String) async {
        let result = coordinator.cancelApplicantProfileIntake(reason: reason)
        await service.resumeToolContinuation(from: result, waitingState: .set(nil))
    }

    func approvePhaseAdvance() async {
        await service.approvePhaseAdvanceRequest()
    }

    func denyPhaseAdvance(reason: String?) async {
        await service.denyPhaseAdvanceRequest(feedback: reason)
    }

    func completeSectionToggleSelection(enabled: [String]) async {
        let result = coordinator.resolveSectionToggle(enabled: enabled)
        await service.resumeToolContinuation(from: result, waitingState: .set(nil), persistCheckpoint: true)
    }

    func cancelSectionToggleSelection(reason: String) async {
        let result = coordinator.rejectSectionToggle(reason: reason)
        await service.resumeToolContinuation(from: result, waitingState: .set(nil))
    }

    func completeUploadRequest(id: UUID, fileURLs: [URL]) async {
        let result = await coordinator.completeUpload(id: id, fileURLs: fileURLs)
        await service.resumeToolContinuation(from: result, waitingState: .set(nil))
    }

    func completeUploadRequest(id: UUID, link: URL) async {
        let result = await coordinator.completeUpload(id: id, link: link)
        await service.resumeToolContinuation(from: result, waitingState: .set(nil))
    }

    func declineUploadRequest(id: UUID) async {
        let result = await coordinator.skipUpload(id: id)
        await service.resumeToolContinuation(from: result, waitingState: .set(nil))
    }

    func confirmPendingExtraction(_ json: JSON, notes: String?) async {
        Logger.debug("Extraction confirmation is not implemented in milestone M0.")
    }

    func cancelPendingExtraction() {
        service.setExtractionStatus(nil)
    }
}
