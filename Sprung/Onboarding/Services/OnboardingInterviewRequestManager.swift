import Foundation

@MainActor
final class OnboardingInterviewRequestManager {
    // Callbacks to update service's observable properties
    private let onStateChanged: (RequestState) -> Void

    private var pendingUploadRequests: [OnboardingUploadRequest] = []
    private var pendingChoicePrompt: OnboardingChoicePrompt?
    private var pendingApplicantProfileRequest: OnboardingApplicantProfileRequest?
    private var pendingSectionToggleRequest: OnboardingSectionToggleRequest?
    private var pendingSectionEntryRequests: [OnboardingSectionEntryRequest] = []
    private var pendingContactsRequest: OnboardingContactsFetchRequest?
    private var pendingExtraction: OnboardingPendingExtraction?

    struct RequestState {
        var pendingUploadRequests: [OnboardingUploadRequest]
        var pendingChoicePrompt: OnboardingChoicePrompt?
        var pendingApplicantProfileRequest: OnboardingApplicantProfileRequest?
        var pendingSectionToggleRequest: OnboardingSectionToggleRequest?
        var pendingSectionEntryRequests: [OnboardingSectionEntryRequest]
        var pendingContactsRequest: OnboardingContactsFetchRequest?
        var pendingExtraction: OnboardingPendingExtraction?
    }

    init(onStateChanged: @escaping (RequestState) -> Void) {
        self.onStateChanged = onStateChanged
    }

    private func notifyStateChanged() {
        onStateChanged(RequestState(
            pendingUploadRequests: pendingUploadRequests,
            pendingChoicePrompt: pendingChoicePrompt,
            pendingApplicantProfileRequest: pendingApplicantProfileRequest,
            pendingSectionToggleRequest: pendingSectionToggleRequest,
            pendingSectionEntryRequests: pendingSectionEntryRequests,
            pendingContactsRequest: pendingContactsRequest,
            pendingExtraction: pendingExtraction
        ))
    }

    func reset() {
        pendingUploadRequests.removeAll()
        pendingChoicePrompt = nil
        pendingApplicantProfileRequest = nil
        pendingSectionToggleRequest = nil
        pendingSectionEntryRequests.removeAll()
        pendingContactsRequest = nil
        pendingExtraction = nil
        notifyStateChanged()
    }

    // MARK: - Upload Request Management

    func addUploadRequest(_ request: OnboardingUploadRequest) {
        if !pendingUploadRequests.contains(where: { $0.toolCallId == request.toolCallId }) {
            pendingUploadRequests.append(request)
            notifyStateChanged()
        }
    }

    func removeUploadRequest(id: UUID) -> OnboardingUploadRequest? {
        guard let index = pendingUploadRequests.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        let removed = pendingUploadRequests.remove(at: index)
        notifyStateChanged()
        return removed
    }

    func uploadRequest(id: UUID) -> OnboardingUploadRequest? {
        pendingUploadRequests.first(where: { $0.id == id })
    }

    // MARK: - Choice Prompt Management

    func setChoicePrompt(_ prompt: OnboardingChoicePrompt?) {
        pendingChoicePrompt = prompt
        notifyStateChanged()
    }

    func clearChoicePrompt() -> OnboardingChoicePrompt? {
        let prompt = pendingChoicePrompt
        pendingChoicePrompt = nil
        notifyStateChanged()
        return prompt
    }

    // MARK: - Applicant Profile Request Management

    func setApplicantProfileRequest(_ request: OnboardingApplicantProfileRequest?) {
        pendingApplicantProfileRequest = request
        notifyStateChanged()
    }

    func clearApplicantProfileRequest() -> OnboardingApplicantProfileRequest? {
        let request = pendingApplicantProfileRequest
        pendingApplicantProfileRequest = nil
        notifyStateChanged()
        return request
    }

    // MARK: - Section Toggle Request Management

    func setSectionToggleRequest(_ request: OnboardingSectionToggleRequest?) {
        pendingSectionToggleRequest = request
        notifyStateChanged()
    }

    func clearSectionToggleRequest() -> OnboardingSectionToggleRequest? {
        let request = pendingSectionToggleRequest
        pendingSectionToggleRequest = nil
        notifyStateChanged()
        return request
    }

    // MARK: - Section Entry Request Management

    func addSectionEntryRequest(_ request: OnboardingSectionEntryRequest) {
        if !pendingSectionEntryRequests.contains(where: { $0.toolCallId == request.toolCallId }) {
            pendingSectionEntryRequests.append(request)
            notifyStateChanged()
        }
    }

    func removeSectionEntryRequest(id: UUID) -> OnboardingSectionEntryRequest? {
        guard let index = pendingSectionEntryRequests.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        let removed = pendingSectionEntryRequests.remove(at: index)
        notifyStateChanged()
        return removed
    }

    // MARK: - Contacts Request Management

    func setContactsRequest(_ request: OnboardingContactsFetchRequest?) {
        pendingContactsRequest = request
        notifyStateChanged()
    }

    func clearContactsRequest() -> OnboardingContactsFetchRequest? {
        let request = pendingContactsRequest
        pendingContactsRequest = nil
        notifyStateChanged()
        return request
    }

    // MARK: - Extraction Management

    func setPendingExtraction(_ extraction: OnboardingPendingExtraction?) {
        pendingExtraction = extraction
        notifyStateChanged()
    }

    func clearPendingExtraction() -> OnboardingPendingExtraction? {
        let extraction = pendingExtraction
        pendingExtraction = nil
        notifyStateChanged()
        return extraction
    }
}
