import Foundation
import SwiftyJSON

@MainActor
struct OnboardingInterviewActionHandler {
    private let service: OnboardingInterviewService

    init(service: OnboardingInterviewService) {
        self.service = service
    }

    func startInterview(modelId: String, backend: LLMFacade.Backend) async {
        await service.startInterview(modelId: modelId, backend: backend)
    }

    func resetInterview() {
        service.reset()
    }

    func setWritingAnalysisConsent(_ isAllowed: Bool) {
        service.setWritingAnalysisConsent(isAllowed)
    }

    func sendMessage(_ text: String) async {
        await service.send(userMessage: text)
    }

    func resolveChoice(selectionIds: [String]) async {
        await service.resolveChoicePrompt(selectionIds: selectionIds)
    }

    func cancelChoicePrompt(reason: String?) async {
        await service.cancelChoicePrompt(reason: reason)
    }

    func approveApplicantProfile(draft: ApplicantProfileDraft) async {
        await service.approveApplicantProfileDraft(draft)
    }

    func declineApplicantProfile(reason: String?) async {
        await service.declineApplicantProfileValidation(reason: reason)
    }

    func fetchApplicantProfileFromContacts() async {
        await service.fetchApplicantProfileFromContacts()
    }

    func declineContactsFetch(reason: String?) async {
        await service.declineContactsFetch(reason: reason)
    }

    func completeSectionToggleSelection(enabled: [String]) async {
        await service.completeSectionToggleSelection(enabledSections: enabled)
    }

    func cancelSectionToggleSelection(reason: String?) async {
        await service.cancelSectionToggleSelection(reason: reason)
    }

    func completeSectionEntryRequest(id: UUID, approvedEntries: [JSON]) async {
        await service.completeSectionEntryRequest(id: id, approvedEntries: approvedEntries)
    }

    func declineSectionEntryRequest(id: UUID, reason: String?) async {
        await service.declineSectionEntryRequest(id: id, reason: reason)
    }

    func completeUploadRequest(id: UUID, fileURL: URL) async {
        await service.fulfillUploadRequest(id: id, fileURL: fileURL)
    }

    func completeUploadRequest(id: UUID, link: URL) async {
        await service.fulfillUploadRequest(id: id, link: link)
    }

    func declineUploadRequest(id: UUID, reason: String? = nil) async {
        await service.declineUploadRequest(id: id, reason: reason)
    }

    func cancelPendingExtraction() {
        service.cancelPendingExtraction()
    }

    func confirmPendingExtraction(_ extraction: JSON, notes: String?) async {
        await service.confirmPendingExtraction(updatedExtraction: extraction, notes: notes)
    }
}
