import Foundation
import SwiftyJSON

@MainActor
final class OnboardingInterviewRequestHandler {
    private let requestManager: OnboardingInterviewRequestManager
    private let wizardManager: OnboardingInterviewWizardManager
    private let artifactStore: OnboardingArtifactStore
    private let applicantProfileStore: ApplicantProfileStore
    private let experienceDefaultsStore: ExperienceDefaultsStore
    private let sendToolResponses: ([JSON]) async -> Void
    private let broadcastResumeSnapshot: (String) async -> Void

    init(
        requestManager: OnboardingInterviewRequestManager,
        wizardManager: OnboardingInterviewWizardManager,
        artifactStore: OnboardingArtifactStore,
        applicantProfileStore: ApplicantProfileStore,
        experienceDefaultsStore: ExperienceDefaultsStore,
        sendToolResponses: @escaping ([JSON]) async -> Void,
        broadcastResumeSnapshot: @escaping (String) async -> Void
    ) {
        self.requestManager = requestManager
        self.wizardManager = wizardManager
        self.artifactStore = artifactStore
        self.applicantProfileStore = applicantProfileStore
        self.experienceDefaultsStore = experienceDefaultsStore
        self.sendToolResponses = sendToolResponses
        self.broadcastResumeSnapshot = broadcastResumeSnapshot
    }

    // MARK: - Upload Requests

    func completeUploadRequest(id: UUID, with item: OnboardingUploadedItem) async {
        guard let request = requestManager.removeUploadRequest(id: id) else { return }
        wizardManager.currentSnapshot()

        let result = JSON([
            "tool": "prompt_user_for_upload",
            "id": request.toolCallId,
            "status": "user_uploaded",
            "result": [
                "file_id": item.id,
                "filename": item.name,
                "kind": item.kind.rawValue
            ]
        ])

        await sendToolResponses([result])
    }

    func declineUploadRequest(id: UUID, reason: String? = nil) async {
        guard let request = requestManager.removeUploadRequest(id: id) else { return }
        wizardManager.currentSnapshot()

        var payload: [String: Any] = [
            "tool": "prompt_user_for_upload",
            "id": request.toolCallId,
            "status": "declined"
        ]
        if let reason {
            payload["message"] = reason
        }

        await sendToolResponses([JSON(payload)])
    }

    // MARK: - Choice Prompts

    func resolveChoicePrompt(selectionIds: [String]) async {
        guard let prompt = requestManager.clearChoicePrompt() else { return }

        let result = JSON([
            "tool": "ask_user_options",
            "id": prompt.toolCallId,
            "status": "ok",
            "selection": JSON(selectionIds)
        ])

        await sendToolResponses([result])
    }

    func cancelChoicePrompt(reason: String? = nil) async {
        guard let prompt = requestManager.clearChoicePrompt() else { return }
        var payload: [String: Any] = [
            "tool": "ask_user_options",
            "id": prompt.toolCallId,
            "status": "cancelled"
        ]
        if let reason {
            payload["message"] = reason
        }
        await sendToolResponses([JSON(payload)])
    }

    // MARK: - Applicant Profile

    func approveApplicantProfileDraft(_ draft: ApplicantProfileDraft) async {
        let profile = applicantProfileStore.currentProfile()
        draft.apply(to: profile)
        applicantProfileStore.save(profile)
        let json = draft.toJSON()
        _ = artifactStore.mergeApplicantProfile(patch: json)
        await broadcastResumeSnapshot("applicant_profile_validated")
        await completeApplicantProfileValidation(approvedProfile: json)
    }

    func completeApplicantProfileValidation(approvedProfile: JSON) async {
        guard let request = requestManager.clearApplicantProfileRequest() else { return }

        let payload = JSON([
            "tool": "validate_applicant_profile",
            "id": request.toolCallId,
            "status": "ok",
            "profile": approvedProfile
        ])
        await sendToolResponses([payload])
    }

    func declineApplicantProfileValidation(reason: String? = nil) async {
        guard let request = requestManager.clearApplicantProfileRequest() else { return }

        var payload: [String: Any] = [
            "tool": "validate_applicant_profile",
            "id": request.toolCallId,
            "status": "cancelled"
        ]
        if let reason {
            payload["message"] = reason
        }
        await sendToolResponses([JSON(payload)])
    }

    // MARK: - Section Toggle

    func completeSectionToggleSelection(enabledSections: [String]) async {
        guard let request = requestManager.clearSectionToggleRequest() else { return }

        let keys = Set(
            enabledSections.compactMap { ExperienceSectionKey.fromOnboardingIdentifier($0) }
        )

        var draft = experienceDefaultsStore.loadDraft()
        draft.setEnabledSections(keys)
        experienceDefaultsStore.save(draft: draft)
        updateDefaultValuesArtifact(from: draft)
        await broadcastResumeSnapshot("resume_sections_enabled")

        let payload = JSON([
            "tool": "validate_enabled_resume_sections",
            "id": request.toolCallId,
            "status": "ok",
            "enabled_sections": JSON(enabledSections)
        ])
        await sendToolResponses([payload])
    }

    func cancelSectionToggleSelection(reason: String? = nil) async {
        guard let request = requestManager.clearSectionToggleRequest() else { return }

        var payload: [String: Any] = [
            "tool": "validate_enabled_resume_sections",
            "id": request.toolCallId,
            "status": "cancelled"
        ]
        if let reason {
            payload["message"] = reason
        }
        await sendToolResponses([JSON(payload)])
    }

    // MARK: - Section Entries

    func completeSectionEntryRequest(id: UUID, approvedEntries: [JSON]) async {
        guard let request = requestManager.removeSectionEntryRequest(id: id) else { return }

        if let sectionKey = ExperienceSectionKey.fromOnboardingIdentifier(request.section) {
            do {
                try await applySectionEntries(sectionKey: sectionKey, entries: approvedEntries)
            } catch {
                Logger.error("OnboardingInterviewRequestHandler.completeSectionEntryRequest failed: \(error)")
            }
        } else {
            Logger.warning("OnboardingInterviewRequestHandler: Unknown section \(request.section)")
        }

        let payload = JSON([
            "tool": "validate_section_entries",
            "id": request.toolCallId,
            "status": "ok",
            "validated_entries": JSON(approvedEntries)
        ])
        await sendToolResponses([payload])
    }

    func declineSectionEntryRequest(id: UUID, reason: String? = nil) async {
        guard let request = requestManager.removeSectionEntryRequest(id: id) else { return }

        var payload: [String: Any] = [
            "tool": "validate_section_entries",
            "id": request.toolCallId,
            "status": "cancelled"
        ]
        if let reason {
            payload["message"] = reason
        }
        await sendToolResponses([JSON(payload)])
    }

    // MARK: - Contacts Fetch

    func completeContactsFetch(profile: JSON) async {
        guard let request = requestManager.clearContactsRequest() else { return }

        let payload = JSON([
            "tool": "fetch_from_system_contacts",
            "id": request.toolCallId,
            "status": "ok",
            "profile": profile
        ])
        await sendToolResponses([payload])
    }

    func declineContactsFetch(reason: String? = nil) async {
        guard let request = requestManager.clearContactsRequest() else { return }

        var payload: [String: Any] = [
            "tool": "fetch_from_system_contacts",
            "id": request.toolCallId,
            "status": "cancelled"
        ]
        if let reason {
            payload["message"] = reason
        }
        await sendToolResponses([JSON(payload)])
    }

    func fetchApplicantProfileFromContacts() async {
        guard let request = requestManager.pendingContactsRequest else { return }
        do {
            let profileJSON = try await SystemContactsFetcher.fetchApplicantProfile(requestedFields: request.requestedFields)
            await completeContactsFetch(profile: profileJSON)
        } catch {
            await declineContactsFetch(reason: error.localizedDescription)
        }
    }

    // MARK: - Private Helpers

    private func applySectionEntries(sectionKey: ExperienceSectionKey, entries: [JSON]) async throws {
        guard let codec = ExperienceSectionCodecs.all.first(where: { $0.key == sectionKey }) else {
            throw OnboardingError.invalidArguments("Unsupported section \(sectionKey.rawValue)")
        }

        var decodedDraft = ExperienceDefaultsDraft()
        let jsonArray = JSON(entries)
        codec.decodeSection(from: jsonArray, into: &decodedDraft)

        var draft = experienceDefaultsStore.loadDraft()
        draft.replaceSection(sectionKey, with: decodedDraft)
        experienceDefaultsStore.save(draft: draft)
        updateDefaultValuesArtifact(from: draft)
        await broadcastResumeSnapshot("resume_section_updated_\(sectionKey.rawValue)")
    }

    private func updateDefaultValuesArtifact(from draft: ExperienceDefaultsDraft) {
        let seed = ExperienceDefaultsEncoder.makeSeedDictionary(from: draft)
        let json = JSON(seed)
        _ = artifactStore.mergeDefaultValues(patch: json)
    }

    enum OnboardingError: Error, LocalizedError {
        case invalidArguments(String)

        var errorDescription: String? {
            switch self {
            case .invalidArguments(let message):
                return message
            }
        }
    }
}
