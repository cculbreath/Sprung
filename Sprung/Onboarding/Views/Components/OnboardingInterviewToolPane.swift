import AppKit
import SwiftyJSON
import SwiftUI
import UniformTypeIdentifiers

struct OnboardingInterviewToolPane: View {
    @Environment(ApplicantProfileStore.self) private var applicantProfileStore
    @Environment(ExperienceDefaultsStore.self) private var experienceDefaultsStore

    @Bindable var service: OnboardingInterviewService
    @Bindable var coordinator: OnboardingInterviewCoordinator
    @Binding var isOccupied: Bool

    var body: some View {
        let paneOccupied = isPaneOccupied(service: service, coordinator: coordinator)
        let showSpinner = service.isProcessing && (service.pendingExtraction != nil || !paneOccupied)

        return VStack(alignment: .leading, spacing: 16) {
            if service.pendingExtraction != nil {
                Spacer(minLength: 0)
            } else {
                let uploads = uploadRequests()

                if !uploads.isEmpty {
                    uploadRequestsView(uploads)
                } else if let intake = coordinator.pendingApplicantProfileIntake {
                    ApplicantProfileIntakeCard(
                        state: intake,
                        service: service,
                        coordinator: coordinator
                    )
                } else if let prompt = coordinator.pendingChoicePrompt {
                    InterviewChoicePromptCard(
                        prompt: prompt,
                        onSubmit: { selection in
                            Task {
                                let result = coordinator.resolveChoice(selectionIds: selection)
                                await service.resumeToolContinuation(from: result)
                            }
                        },
                        onCancel: {
                            Task {
                                let result = coordinator.cancelChoicePrompt(reason: "User dismissed choice prompt")
                                await service.resumeToolContinuation(from: result)
                            }
                        }
                    )
                } else if let validation = coordinator.pendingValidationPrompt {
                    if validation.dataType == "knowledge_card" {
                        KnowledgeCardValidationHost(
                            prompt: validation,
                            artifactsJSON: service.artifacts.artifactRecords,
                            service: service,
                            coordinator: coordinator
                        )
                    } else {
                        OnboardingValidationReviewCard(
                            prompt: validation,
                            onSubmit: { decision, updated, notes in
                                Task {
                                    let result = coordinator.submitValidationResponse(
                                        status: decision.rawValue,
                                        updatedData: updated,
                                        changes: nil,
                                        notes: notes
                                    )
                                    await service.resumeToolContinuation(from: result)
                                }
                            },
                            onCancel: {
                                Task {
                                    let result = coordinator.cancelValidation(reason: "User cancelled validation review")
                                    await service.resumeToolContinuation(from: result)
                                }
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
                                    await service.approvePhaseAdvanceRequest()
                                case .denied:
                                    await service.denyPhaseAdvanceRequest(feedback: nil)
                                case .deniedWithFeedback:
                                    await service.denyPhaseAdvanceRequest(feedback: feedback)
                                }
                            }
                        },
                        onCancel: nil
                    )
                } else if let profileRequest = coordinator.pendingApplicantProfileRequest {
                    ApplicantProfileReviewCard(
                        request: profileRequest,
                        fallbackDraft: ApplicantProfileDraft(profile: applicantProfileStore.currentProfile()),
                        onConfirm: { draft in
                            Task { await service.resolveApplicantProfile(with: draft) }
                        },
                        onCancel: {
                            Task { await service.rejectApplicantProfile(reason: "User cancelled applicant profile validation") }
                        }
                    )
                } else if let sectionToggle = coordinator.pendingSectionToggleRequest {
                    ResumeSectionsToggleCard(
                        request: sectionToggle,
                        existingDraft: experienceDefaultsStore.loadDraft(),
                        onConfirm: { enabled in
                            Task {
                                let result = coordinator.resolveSectionToggle(enabled: enabled)
                                await service.resumeToolContinuation(from: result, waitingState: .set(nil), persistCheckpoint: true)
                            }
                        },
                        onCancel: {
                            Task {
                                let result = coordinator.rejectSectionToggle(reason: "User cancelled section toggle")
                                await service.resumeToolContinuation(from: result, waitingState: .set(nil))
                            }
                        }
                    )
                } else {
                    supportingContent()
                }
            }
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .center) {
            if showSpinner {
                VStack(spacing: 18) {
                    AnimatedThinkingText()
                    if let extraction = service.pendingExtraction, !extraction.progressItems.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Processing résumé…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            ExtractionProgressChecklistView(items: extraction.progressItems)
                        }
                        .padding(18)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    } else if let status = coordinator.pendingStreamingStatus, !status.isEmpty {
                        Text(status)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .transition(.opacity)
                    }
                }
                .padding(.vertical, 24)
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
                .transition(.opacity.combined(with: .scale))
                .zIndex(1)
            }
        }
        .animation(
            .easeInOut(duration: 0.2),
            value: showSpinner
        )
        .onAppear { isOccupied = paneOccupied }
        .onChange(of: paneOccupied) { newValue in
            isOccupied = newValue
        }
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
        if coordinator.wizardStep == .wrapUp {
            WrapUpSummaryView(
                artifacts: service.artifacts,
                schemaIssues: service.schemaIssues
            )
        } else if coordinator.wizardStep == .resumeIntake, let profile = service.applicantProfileJSON {
            ApplicantProfileSummaryCard(
                profile: profile,
                imageData: applicantProfileStore.currentProfile().pictureData
            )
        } else if coordinator.wizardStep == .artifactDiscovery, let timeline = service.skeletonTimelineJSON {
            TimelineCardEditorView(service: service, timeline: timeline)
        } else if coordinator.wizardStep == .artifactDiscovery,
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
                        onDropFiles: { urls in
                            Task {
                                let result = await coordinator.completeUpload(id: request.id, fileURLs: urls)
                                await service.resumeToolContinuation(from: result, waitingState: .set(nil))
                            }
                        },
                        onDecline: {
                            Task {
                                let result = await coordinator.skipUpload(id: request.id)
                                await service.resumeToolContinuation(from: result, waitingState: .set(nil))
                            }
                        }
                    )
                }
            }
        }
    }

    private func uploadRequests() -> [OnboardingUploadRequest] {
        var filtered: [OnboardingUploadRequest]
        switch service.wizardStep {
        case .resumeIntake:
            filtered = service.pendingUploadRequests.filter {
                [.resume, .linkedIn].contains($0.kind) ||
                    ($0.kind == .generic && $0.metadata.targetKey == "basics.image")
            }
        case .artifactDiscovery:
            filtered = service.pendingUploadRequests.filter { [.artifact, .generic].contains($0.kind) }
        case .writingCorpus:
            filtered = service.pendingUploadRequests.filter { $0.kind == .writingSample }
        case .wrapUp:
            filtered = service.pendingUploadRequests
        case .introduction:
            filtered = service.pendingUploadRequests.filter {
                $0.kind == .generic && $0.metadata.targetKey == "basics.image"
            }
        }

        if filtered.count != service.pendingUploadRequests.count {
            let headshotRequests = service.pendingUploadRequests.filter { $0.metadata.targetKey == "basics.image" }
            for request in headshotRequests where filtered.contains(where: { $0.id == request.id }) == false {
                filtered.append(request)
            }
        }

        if !filtered.isEmpty {
            let kinds = filtered.map { $0.kind.rawValue }.joined(separator: ",")
            Logger.debug("📤 Pending upload requests surfaced in tool pane (step: \(service.wizardStep.rawValue), kinds: \(kinds))", category: .ai)
        }

        return filtered
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
            Task {
                let result = await coordinator.completeUpload(id: request.id, fileURLs: urls)
                await service.resumeToolContinuation(from: result, waitingState: .set(nil))
            }
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

    private func isPaneOccupied(
        service: OnboardingInterviewService,
        coordinator: OnboardingInterviewCoordinator
    ) -> Bool {
        hasInteractiveCard(service: service, coordinator: coordinator) ||
            hasSummaryCard(service: service, coordinator: coordinator)
    }

    private func hasInteractiveCard(
        service: OnboardingInterviewService,
        coordinator: OnboardingInterviewCoordinator
    ) -> Bool {
        if service.pendingExtraction != nil { return true }
        if !uploadRequests().isEmpty { return true }
        if coordinator.pendingApplicantProfileIntake != nil { return true }
        if coordinator.pendingChoicePrompt != nil { return true }
        if service.pendingValidationPrompt != nil { return true }
        if coordinator.pendingApplicantProfileRequest != nil { return true }
        if coordinator.pendingSectionToggleRequest != nil { return true }
        if service.pendingPhaseAdvanceRequest != nil { return true }
        return false
    }

    private func hasSummaryCard(
        service: OnboardingInterviewService,
        coordinator: OnboardingInterviewCoordinator
    ) -> Bool {
        switch coordinator.wizardStep {
        case .wrapUp:
            return true
        case .resumeIntake:
            return service.applicantProfileJSON != nil
        case .artifactDiscovery:
            if service.skeletonTimelineJSON != nil { return true }
            if !service.artifacts.enabledSections.isEmpty { return true }
            return false
        case .writingCorpus, .introduction:
            return false
        }
    }
}

private struct KnowledgeCardValidationHost: View {
    let prompt: OnboardingValidationPrompt
    let service: OnboardingInterviewService
    let coordinator: OnboardingInterviewCoordinator

    @State private var draft: KnowledgeCardDraft
    private let artifactRecords: [ArtifactRecord]

    init(
        prompt: OnboardingValidationPrompt,
        artifactsJSON: [JSON],
        service: OnboardingInterviewService,
        coordinator: OnboardingInterviewCoordinator
    ) {
        self.prompt = prompt
        self.service = service
        self.coordinator = coordinator
        _draft = State(initialValue: KnowledgeCardDraft(json: prompt.payload))
        artifactRecords = artifactsJSON.map { ArtifactRecord(json: $0) }
    }

    var body: some View {
        KnowledgeCardReviewCard(
            card: $draft,
            artifacts: artifactRecords,
            onApprove: { approved in
                Task {
                    let result = coordinator.submitValidationResponse(
                        status: "approved",
                        updatedData: approved.toJSON(),
                        changes: nil,
                        notes: nil
                    )
                    await service.resumeToolContinuation(from: result)
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
                    let result = coordinator.submitValidationResponse(
                        status: "rejected",
                        updatedData: nil,
                        changes: changePayload,
                        notes: reason.isEmpty ? nil : reason
                    )
                    await service.resumeToolContinuation(from: result)
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
    let imageData: Data?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Applicant Profile")
                .font(.headline)
            if let avatar = avatarImage {
                avatar
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 64, height: 64)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.7), lineWidth: 1)
                    )
                    .shadow(radius: 2, y: 1)
            }
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
            if let location = formattedLocation(profile["location"]) {
                Label(location, systemImage: "mappin.and.ellipse")
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

    private var avatarImage: Image? {
        if let base64 = profile["image"].string?.trimmingCharacters(in: .whitespacesAndNewlines),
           let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters),
           let nsImage = NSImage(data: data) {
            return Image(nsImage: nsImage)
        }

        if let imageData,
           let nsImage = NSImage(data: imageData) {
            return Image(nsImage: nsImage)
        }

        return nil
    }

    private func formattedLocation(_ json: JSON) -> String? {
        guard json != .null else { return nil }
        var components: [String] = []
        if let address = nonEmpty(json["address"].string) {
            components.append(address)
        }
        let cityComponents = [json["city"].string, json["region"].string]
            .compactMap(nonEmpty)
            .joined(separator: ", ")
        if !cityComponents.isEmpty {
            components.append(cityComponents)
        }
        if let postal = nonEmpty(json["postalCode"].string) {
            if components.isEmpty {
                components.append(postal)
            } else {
                components[components.count - 1] += " \(postal)"
            }
        }
        if let country = nonEmpty(json["countryCode"].string) {
            components.append(country)
        }
        return components.isEmpty ? nil : components.joined(separator: ", ")
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
                Text(formattedSections().joined(separator: ", "))
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func formattedSections() -> [String] {
        sections.compactMap { identifier in
            ExperienceSectionKey.fromOnboardingIdentifier(identifier)?.metadata.title
        }
    }
}
