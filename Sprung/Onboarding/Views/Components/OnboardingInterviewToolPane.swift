import AppKit
import SwiftyJSON
import SwiftUI
import UniformTypeIdentifiers

struct OnboardingInterviewToolPane: View {
    @Environment(ApplicantProfileStore.self) private var applicantProfileStore
    @Environment(ExperienceDefaultsStore.self) private var experienceDefaultsStore

    @Bindable var service: OnboardingInterviewService
    let actions: OnboardingInterviewActionHandler

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            let uploads = uploadRequests()

            if !uploads.isEmpty {
                uploadRequestsView(uploads)
            } else if let contactsRequest = service.pendingContactsRequest {
                ContactsPermissionCard(
                    request: contactsRequest,
                    onAllow: { Task { await actions.fetchApplicantProfileFromContacts() } },
                    onDecline: { Task { await actions.declineContactsFetch(reason: "User declined contacts access") } }
                )
            } else if let intake = service.pendingApplicantProfileIntake {
                ApplicantProfileIntakeCard(
                    state: intake,
                    actions: actions
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
                if validation.dataType == "knowledge_card" {
                    KnowledgeCardValidationHost(
                        prompt: validation,
                        artifactsJSON: service.artifacts.artifactRecords,
                        actions: actions
                    )
                } else {
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
                }
            } else if let phaseAdvanceRequest = service.pendingPhaseAdvanceRequest {
                OnboardingPhaseAdvanceDialog(
                    request: phaseAdvanceRequest,
                    onSubmit: { decision, feedback in
                        Task {
                            switch decision {
                            case .approved:
                                await actions.approvePhaseAdvance()
                            case .denied:
                                await actions.denyPhaseAdvance(reason: nil)
                            case .deniedWithFeedback:
                                await actions.denyPhaseAdvance(reason: feedback)
                            }
                        }
                    },
                    onCancel: nil
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
        .overlay(alignment: .center) {
            if shouldShowLLMSpinner(for: service) {
                VStack {
                    Spacer()
                    AnimatedThinkingText()
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
                .transition(.opacity.combined(with: .scale))
                .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: shouldShowLLMSpinner(for: service))
    }

    @ViewBuilder
    private func supportingContent() -> some View {
        if let extraction = service.pendingExtraction {
            VStack(alignment: .leading, spacing: 16) {
                ExtractionStatusCard(extraction: extraction)
                summaryContent()
            }
        } else {
            summaryContent()
        }
    }

    @ViewBuilder
    private func summaryContent() -> some View {
        if service.wizardStep == .wrapUp {
            WrapUpSummaryView(
                artifacts: service.artifacts,
                schemaIssues: service.schemaIssues
            )
        } else if service.wizardStep == .resumeIntake, let profile = service.applicantProfileJSON {
            ApplicantProfileSummaryCard(profile: profile)
        } else if service.wizardStep == .artifactDiscovery, let timeline = service.skeletonTimelineJSON {
            SkeletonTimelineSummaryCard(timeline: timeline)
        } else if service.wizardStep == .artifactDiscovery,
                  !service.artifacts.enabledSections.isEmpty {
            EnabledSectionsSummaryCard(sections: service.artifacts.enabledSections)
        } else {
            Spacer()
        }
    }

    @ViewBuilder
    private func uploadRequestsView(_ requests: [OnboardingUploadRequest]) -> some View {
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
                urls = Array(panel.urls.prefix(1))
            }
            Task { await actions.completeUploadRequest(id: request.id, fileURLs: urls) }
        }
    }

    private func allowedContentTypes(for request: OnboardingUploadRequest) -> [UTType]? {
        var candidates = request.metadata.accepts.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        if candidates.isEmpty {
            switch request.kind {
            case .resume, .coverletter:
                candidates = ["pdf", "docx", "txt", "json"]
            case .artifact, .portfolio, .generic:
                candidates = ["pdf", "pptx", "docx", "txt", "json"]
            case .writingSample:
                candidates = ["pdf", "docx", "txt", "md"]
            case .transcript, .certificate:
                candidates = ["pdf", "png", "jpg"]
            case .linkedIn:
                return nil
            }
        }

        let mapped = candidates.compactMap { UTType(filenameExtension: $0) }
        return mapped.isEmpty ? nil : mapped
    }

    private func shouldShowLLMSpinner(for service: OnboardingInterviewService) -> Bool {
        service.isProcessing &&
            service.pendingChoicePrompt == nil &&
            service.pendingApplicantProfileRequest == nil &&
            service.pendingApplicantProfileIntake == nil &&
            service.pendingSectionToggleRequest == nil &&
            service.pendingSectionEntryRequests.isEmpty &&
            service.pendingContactsRequest == nil &&
            service.pendingValidationPrompt == nil &&
            service.pendingPhaseAdvanceRequest == nil
    }
}

private struct KnowledgeCardValidationHost: View {
    let prompt: OnboardingValidationPrompt
    let actions: OnboardingInterviewActionHandler

    @State private var draft: KnowledgeCardDraft
    private let artifactRecords: [ArtifactRecord]

    init(
        prompt: OnboardingValidationPrompt,
        artifactsJSON: [JSON],
        actions: OnboardingInterviewActionHandler
    ) {
        self.prompt = prompt
        self.actions = actions
        _draft = State(initialValue: KnowledgeCardDraft(json: prompt.payload))
        artifactRecords = artifactsJSON.map { ArtifactRecord(json: $0) }
    }

    var body: some View {
        KnowledgeCardReviewCard(
            card: $draft,
            artifacts: artifactRecords,
            onApprove: { approved in
                Task {
                    await actions.submitValidation(
                        status: "approved",
                        updatedData: approved.toJSON(),
                        changes: nil,
                        notes: nil
                    )
                }
            },
            onReject: { rejectedIds, reason in
                Task {
                    var changePayload: JSON?
                    if !rejectedIds.isEmpty {
                        var details = JSON()
                        details["rejected_claims"] = JSON(rejectedIds.map { $0.uuidString })
                        changePayload = details
                    }
                    await actions.submitValidation(
                        status: "rejected",
                        updatedData: nil,
                        changes: changePayload,
                        notes: reason.isEmpty ? nil : reason
                    )
                }
            }
        )
        .onChange(of: prompt.id) { _, _ in
            draft = KnowledgeCardDraft(json: prompt.payload)
        }
    }
}

private struct ApplicantProfileSummaryCard: View {
    let profile: JSON

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Applicant Profile")
                .font(.headline)
            if let name = nonEmpty(profile["name"].string) {
                Label(name, systemImage: "person.fill")
            }
            if let label = nonEmpty(profile["label"].string) {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let email = nonEmpty(profile["email"].string) {
                Label(email, systemImage: "envelope")
                    .font(.footnote)
            }
            if let phone = nonEmpty(profile["phone"].string) {
                Label(phone, systemImage: "phone")
                    .font(.footnote)
            }
            if let url = nonEmpty(profile["url"].string ?? profile["website"].string) {
                Label(url, systemImage: "globe")
                    .font(.footnote)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }
}

private struct SkeletonTimelineSummaryCard: View {
    let timeline: JSON

    var body: some View {
        let experiences = timeline["experiences"].arrayValue
        VStack(alignment: .leading, spacing: 8) {
            Text("Skeleton Timeline")
                .font(.headline)
            if experiences.isEmpty {
                Text("No experiences extracted yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(experiences.prefix(3).indices, id: \.self) { index in
                    let entry = experiences[index]
                    TimelineEntryRow(entry: entry)
                }
                if experiences.count > 3 {
                    Text("…and \(experiences.count - 3) more entries")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct TimelineEntryRow: View {
    let entry: JSON

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry["title"].stringValue.isEmpty ? "Untitled Role" : entry["title"].stringValue)
                .font(.subheadline.weight(.semibold))
            if let org = nonEmpty(entry["organization"].string) {
                Text(org)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            let start = entry["start"].stringValue
            let end = entry["end"].stringValue
            if !start.isEmpty || !end.isEmpty {
                Text("\(start.isEmpty ? "????" : start) – \(end.isEmpty ? "present" : end)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }
}

private struct EnabledSectionsSummaryCard: View {
    let sections: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Enabled Résumé Sections")
                .font(.headline)
            if sections.isEmpty {
                Text("No sections selected yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text(sections.joined(separator: ", "))
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
