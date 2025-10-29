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

    init(service: OnboardingInterviewService) {
        self.service = service
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
        await service.resolveChoice(selectionIds: selectionIds)
    }

    func cancelChoicePrompt(reason: String) async {
        await service.cancelChoicePrompt(reason: reason)
    }

    func submitValidation(
        status: String,
        updatedData: JSON? = nil,
        changes: JSON? = nil,
        notes: String? = nil
    ) async {
        await service.submitValidationResponse(
            status: status,
            updatedData: updatedData,
            changes: changes,
            notes: notes
        )
    }

    func cancelValidation(reason: String) async {
        await service.cancelValidation(reason: reason)
    }

    // MARK: - Applicant Profile Intake

    func fetchApplicantProfileFromContacts() async {
        service.beginApplicantProfileContactsFetch()
    }

    func declineContactsFetch(reason: String) async {
        Logger.debug("Contacts fetch declined: \(reason)")
    }

    func approveApplicantProfile(draft: ApplicantProfileDraft) async {
        await service.resolveApplicantProfile(with: draft)
    }

    func declineApplicantProfile(reason: String) async {
        await service.rejectApplicantProfile(reason: reason)
    }

    func beginApplicantProfileManualEntry() {
        service.beginApplicantProfileManualEntry()
    }

    func beginApplicantProfileURLEntry() {
        service.beginApplicantProfileURL()
    }

    func beginApplicantProfileUpload() async {
        service.beginApplicantProfileUpload()
    }

    func resetApplicantProfileIntake() {
        service.resetApplicantProfileIntakeToOptions()
    }

    func submitApplicantProfileURL(_ urlString: String) async {
        await service.submitApplicantProfileURL(urlString)
    }

    func completeApplicantProfileDraft(_ draft: ApplicantProfileDraft, source: OnboardingApplicantProfileIntakeState.Source) async {
        await service.completeApplicantProfileDraft(draft, source: source)
    }

    func cancelApplicantProfileIntake(reason: String) async {
        await service.cancelApplicantProfileIntake(reason: reason)
    }

    func approvePhaseAdvance() async {
        await service.approvePhaseAdvanceRequest()
    }

    func denyPhaseAdvance(reason: String?) async {
        await service.denyPhaseAdvanceRequest(feedback: reason)
    }

    func completeSectionToggleSelection(enabled: [String]) async {
        await service.resolveSectionToggle(enabled: enabled)
    }

    func cancelSectionToggleSelection(reason: String) async {
        await service.rejectSectionToggle(reason: reason)
    }

    func completeSectionEntryRequest(id: UUID, approvedEntries: [JSON]) async {
        Logger.debug("Section entry review is not implemented in milestone M0.")
    }

    func declineSectionEntryRequest(id: UUID, reason: String) async {
        Logger.debug("Section entry request declined: \(reason)")
    }

    func completeUploadRequest(id: UUID, fileURLs: [URL]) async {
        await service.completeUploadRequest(id: id, fileURLs: fileURLs)
    }

    func completeUploadRequest(id: UUID, link: URL) async {
        await service.completeUploadRequest(id: id, link: link)
    }

    func declineUploadRequest(id: UUID) async {
        await service.skipUploadRequest(id: id)
    }

    func confirmPendingExtraction(_ json: JSON, notes: String?) async {
        Logger.debug("Extraction confirmation is not implemented in milestone M0.")
    }

    func cancelPendingExtraction() {
        Logger.debug("Pending extraction cancelled.")
    }
}
