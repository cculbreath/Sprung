import Foundation
import Observation

@MainActor
@Observable
final class OnboardingInterviewRequestManager {
    private(set) var pendingUploadRequests: [OnboardingUploadRequest] = []
    private(set) var pendingChoicePrompt: OnboardingChoicePrompt?
    private(set) var pendingApplicantProfileRequest: OnboardingApplicantProfileRequest?
    private(set) var pendingSectionToggleRequest: OnboardingSectionToggleRequest?
    private(set) var pendingSectionEntryRequests: [OnboardingSectionEntryRequest] = []
    private(set) var pendingContactsRequest: OnboardingContactsFetchRequest?
    private(set) var pendingExtraction: OnboardingPendingExtraction?

    func reset() {
        pendingUploadRequests.removeAll()
        pendingChoicePrompt = nil
        pendingApplicantProfileRequest = nil
        pendingSectionToggleRequest = nil
        pendingSectionEntryRequests.removeAll()
        pendingContactsRequest = nil
        pendingExtraction = nil
    }

    // MARK: - Upload Request Management

    func addUploadRequest(_ request: OnboardingUploadRequest) {
        if !pendingUploadRequests.contains(where: { $0.toolCallId == request.toolCallId }) {
            pendingUploadRequests.append(request)
        }
    }

    func removeUploadRequest(id: UUID) -> OnboardingUploadRequest? {
        guard let index = pendingUploadRequests.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        return pendingUploadRequests.remove(at: index)
    }

    func uploadRequest(id: UUID) -> OnboardingUploadRequest? {
        pendingUploadRequests.first(where: { $0.id == id })
    }

    // MARK: - Choice Prompt Management

    func setChoicePrompt(_ prompt: OnboardingChoicePrompt?) {
        pendingChoicePrompt = prompt
    }

    func clearChoicePrompt() -> OnboardingChoicePrompt? {
        let prompt = pendingChoicePrompt
        pendingChoicePrompt = nil
        return prompt
    }

    // MARK: - Applicant Profile Request Management

    func setApplicantProfileRequest(_ request: OnboardingApplicantProfileRequest?) {
        pendingApplicantProfileRequest = request
    }

    func clearApplicantProfileRequest() -> OnboardingApplicantProfileRequest? {
        let request = pendingApplicantProfileRequest
        pendingApplicantProfileRequest = nil
        return request
    }

    // MARK: - Section Toggle Request Management

    func setSectionToggleRequest(_ request: OnboardingSectionToggleRequest?) {
        pendingSectionToggleRequest = request
    }

    func clearSectionToggleRequest() -> OnboardingSectionToggleRequest? {
        let request = pendingSectionToggleRequest
        pendingSectionToggleRequest = nil
        return request
    }

    // MARK: - Section Entry Request Management

    func addSectionEntryRequest(_ request: OnboardingSectionEntryRequest) {
        if !pendingSectionEntryRequests.contains(where: { $0.toolCallId == request.toolCallId }) {
            pendingSectionEntryRequests.append(request)
        }
    }

    func removeSectionEntryRequest(id: UUID) -> OnboardingSectionEntryRequest? {
        guard let index = pendingSectionEntryRequests.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        return pendingSectionEntryRequests.remove(at: index)
    }

    // MARK: - Contacts Request Management

    func setContactsRequest(_ request: OnboardingContactsFetchRequest?) {
        pendingContactsRequest = request
    }

    func clearContactsRequest() -> OnboardingContactsFetchRequest? {
        let request = pendingContactsRequest
        pendingContactsRequest = nil
        return request
    }

    // MARK: - Extraction Management

    func setPendingExtraction(_ extraction: OnboardingPendingExtraction?) {
        pendingExtraction = extraction
    }

    func clearPendingExtraction() -> OnboardingPendingExtraction? {
        let extraction = pendingExtraction
        pendingExtraction = nil
        return extraction
    }
}
