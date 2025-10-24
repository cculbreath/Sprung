import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct OnboardingInterviewToolPane: View {
    @Environment(ApplicantProfileStore.self) private var applicantProfileStore
    @Environment(ExperienceDefaultsStore.self) private var experienceDefaultsStore

    @Bindable var service: OnboardingInterviewService
    let actions: OnboardingInterviewActionHandler

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let badge = statusBadgeText() {
                badge
            }

            if let contactsRequest = service.pendingContactsRequest {
                ContactsPermissionCard(
                    request: contactsRequest,
                    onAllow: { Task { await actions.fetchApplicantProfileFromContacts() } },
                    onDecline: { Task { await actions.declineContactsFetch(reason: "User declined contacts access") } }
                )
            } else if let prompt = service.pendingChoicePrompt {
                InterviewChoicePromptCard(
                    prompt: prompt,
                    onSubmit: { selection in
                        Task { await actions.resolveChoice(selectionIds: selection) }
                    },
                    onCancel: {
                        Task { await actions.cancelChoicePrompt(reason: "User dismissed choice prompt") }
                    }
                )
            } else if let validation = service.pendingValidationPrompt {
                OnboardingValidationReviewCard(
                    prompt: validation,
                    onSubmit: { decision, updated, notes in
                        Task {
                            await actions.submitValidation(
                                status: decision.rawValue,
                                updatedData: updated,
                                changes: nil,
                                notes: notes
                            )
                        }
                    },
                    onCancel: {
                        Task { await actions.cancelValidation(reason: "User cancelled validation review") }
                    }
                )
            } else if let profileRequest = service.pendingApplicantProfileRequest {
                ApplicantProfileReviewCard(
                    request: profileRequest,
                    fallbackDraft: ApplicantProfileDraft(profile: applicantProfileStore.currentProfile()),
                    onConfirm: { draft in
                        Task { await actions.approveApplicantProfile(draft: draft) }
                    },
                    onCancel: {
                        Task { await actions.declineApplicantProfile(reason: "User cancelled applicant profile validation") }
                    }
                )
            } else if let sectionToggle = service.pendingSectionToggleRequest {
                ResumeSectionsToggleCard(
                    request: sectionToggle,
                    existingDraft: experienceDefaultsStore.loadDraft(),
                    onConfirm: { enabled in
                        Task { await actions.completeSectionToggleSelection(enabled: enabled) }
                    },
                    onCancel: {
                        Task { await actions.cancelSectionToggleSelection(reason: "User cancelled section toggle") }
                    }
                )
            } else if let entryRequest = service.pendingSectionEntryRequests.first {
                ResumeSectionEntriesCard(
                    request: entryRequest,
                    existingDraft: experienceDefaultsStore.loadDraft(),
                    onConfirm: { approved in
                        Task { await actions.completeSectionEntryRequest(id: entryRequest.id, approvedEntries: approved) }
                    },
                    onCancel: {
                        Task { await actions.declineSectionEntryRequest(id: entryRequest.id, reason: "User cancelled section validation") }
                    }
                )
            } else {
                supportingContent()
            }
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func supportingContent() -> some View {
        let requests = uploadRequests()
        if !requests.isEmpty {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(requests) { request in
                        UploadRequestCard(
                            request: request,
                            onSelectFile: { openPanel(for: request) },
                            onProvideLink: { url in
                                Task { await actions.completeUploadRequest(id: request.id, link: url) }
                            },
                            onDecline: {
                                Task { await actions.declineUploadRequest(id: request.id) }
                            }
                        )
                    }
                }
            }
        } else if service.wizardStep == .wrapUp {
            WrapUpSummaryView(
                artifacts: service.artifacts,
                schemaIssues: service.schemaIssues
            )
        } else {
            Spacer()
        }
    }

    private func uploadRequests() -> [OnboardingUploadRequest] {
        switch service.wizardStep {
        case .resumeIntake:
            return service.pendingUploadRequests.filter { [.resume, .linkedIn].contains($0.kind) }
        case .artifactDiscovery:
            return service.pendingUploadRequests.filter { [.artifact, .generic].contains($0.kind) }
        case .writingCorpus:
            return service.pendingUploadRequests.filter { $0.kind == .writingSample }
        case .wrapUp:
            return service.pendingUploadRequests
        case .introduction:
            return []
        }
    }

    private func openPanel(for request: OnboardingUploadRequest) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = request.metadata.allowMultiple
        panel.canChooseDirectories = false
        if let allowed = allowedContentTypes(for: request) {
            panel.allowedContentTypes = allowed
        }

        panel.begin { result in
            guard result == .OK else { return }
            let urls: [URL]
            if request.metadata.allowMultiple {
                urls = panel.urls
            } else {
                urls = panel.urls.prefix(1).map { $0 }
            }
            for url in urls {
                Task { await actions.completeUploadRequest(id: request.id, fileURL: url) }
            }
        }
    }

    private func allowedContentTypes(for request: OnboardingUploadRequest) -> [UTType]? {
        var candidates = request.metadata.accepts.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        if candidates.isEmpty {
            switch request.kind {
            case .resume:
                candidates = ["pdf", "docx", "txt", "json"]
            case .artifact, .generic:
                candidates = ["pdf", "pptx", "docx", "txt", "json"]
            case .writingSample:
                candidates = ["pdf", "docx", "txt", "md"]
            case .linkedIn:
                return nil
            }
        }

        let mapped = candidates.compactMap { UTType(filenameExtension: $0) }
        return mapped.isEmpty ? nil : mapped
    }

    private func statusBadgeText() -> Text? {
        switch service.wizardStep {
        case .resumeIntake:
            let text = badgeText(introCompleted: service.completedWizardSteps.contains(.resumeIntake))
            return text.isEmpty ? nil : Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .artifactDiscovery:
            let text = badgeText(introCompleted: true)
            return text.isEmpty ? nil : Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .writingCorpus, .wrapUp, .introduction:
            return nil
        }
    }

    private func badgeText(introCompleted: Bool) -> String {
        if !service.pendingUploadRequests.isEmpty {
            return "Upload the requested files"
        }
        if service.pendingContactsRequest != nil {
            return "Allow access to macOS Contacts"
        }
        if let choicePrompt = service.pendingChoicePrompt {
            return "Action required: " + (choicePrompt.prompt.isEmpty ? "please choose an option" : choicePrompt.prompt)
        }
        if service.pendingApplicantProfileRequest != nil {
            return "Action required: review applicant profile"
        }
        if service.pendingSectionToggleRequest != nil {
            return "Confirm applicable résumé sections"
        }
        if service.pendingSectionEntryRequests.first != nil {
            return "Review section entries"
        }
        if service.pendingUploadRequests.isEmpty && introCompleted == false {
            return ""
        }
        return ""
    }
}
