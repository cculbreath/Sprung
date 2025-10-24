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

    func startInterview(modelId: String, backend: LLMFacade.Backend) async {
        await service.startInterview(modelId: modelId, backend: backend)
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

    // MARK: - Stubs for future milestones

    func fetchApplicantProfileFromContacts() async {
        debugLog("Contacts fetch is not implemented in milestone M0.")
    }

    func declineContactsFetch(reason: String) async {
        debugLog("Contacts fetch declined: \(reason)")
    }

    func approveApplicantProfile(draft: ApplicantProfileDraft) async {
        await service.resolveApplicantProfile(with: draft)
    }

    func declineApplicantProfile(reason: String) async {
        await service.rejectApplicantProfile(reason: reason)
    }

    func completeSectionToggleSelection(enabled: [String]) async {
        await service.resolveSectionToggle(enabled: enabled)
    }

    func cancelSectionToggleSelection(reason: String) async {
        await service.rejectSectionToggle(reason: reason)
    }

    func completeSectionEntryRequest(id: UUID, approvedEntries: [JSON]) async {
        debugLog("Section entry review is not implemented in milestone M0.")
    }

    func declineSectionEntryRequest(id: UUID, reason: String) async {
        debugLog("Section entry request declined: \(reason)")
    }

    func completeUploadRequest(id: UUID, fileURLs: [URL]) async {
        await service.completeUploadRequest(id: id, fileURLs: fileURLs)
    }

    func completeUploadRequest(id: UUID, link: URL) async {
        await service.skipUploadRequest(id: id)
        debugLog("Link-based uploads are not supported yet. Ignored link \(link).")
    }

    func declineUploadRequest(id: UUID) async {
        await service.skipUploadRequest(id: id)
    }

    func confirmPendingExtraction(_ json: JSON, notes: String?) async {
        debugLog("Extraction confirmation is not implemented in milestone M0.")
    }

    func cancelPendingExtraction() {
        debugLog("Pending extraction cancelled.")
    }
}
