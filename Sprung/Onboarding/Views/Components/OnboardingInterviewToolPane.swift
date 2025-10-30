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
        let showSpinner = service.isProcessing && !paneOccupied

        return VStack(alignment: .leading, spacing: 16) {
            if service.pendingExtraction != nil {
                Spacer(minLength: 0)
            } else {
                let uploads = uploadRequests()

                if !uploads.isEmpty {
                    uploadRequestsView(uploads)
                } else if let intake = coordinator.toolRouter.pendingApplicantProfileIntake {
                    ApplicantProfileIntakeCard(
                        state: intake,
                        service: service,
                        coordinator: coordinator
                    )
                } else if let prompt = coordinator.toolRouter.pendingChoicePrompt {
                    InterviewChoicePromptCard(
                        prompt: prompt,
                        onSubmit: { selection in
                            handleToolResult { coordinator.resolveChoice(selectionIds: selection) }
                        },
                        onCancel: {
                            handleToolResult { coordinator.cancelChoicePrompt(reason: "User dismissed choice prompt") }
                        }
                    )
                } else if let validation = coordinator.toolRouter.pendingValidationPrompt {
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
                                handleToolResult {
                                    coordinator.submitValidationResponse(
                                        status: decision.rawValue,
                                        updatedData: updated,
                                        changes: nil,
                                        notes: notes
                                    )
                                }
                            },
                            onCancel: {
                                handleToolResult { coordinator.cancelValidation(reason: "User cancelled validation review") }
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
                } else if let profileRequest = coordinator.toolRouter.pendingApplicantProfileRequest {
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
                } else if let sectionToggle = coordinator.toolRouter.pendingSectionToggleRequest {
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
                            handleToolResult { coordinator.rejectSectionToggle(reason: "User cancelled section toggle") }
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
        if coordinator.wizardTracker.currentStep == .wrapUp {
            WrapUpSummaryView(
                artifacts: service.artifacts,
                schemaIssues: service.schemaIssues
            )
        } else if coordinator.wizardTracker.currentStep == .resumeIntake, let profile = service.applicantProfileJSON {
            ApplicantProfileSummaryCard(profile: profile)
        } else if coordinator.wizardTracker.currentStep == .artifactDiscovery, let timeline = service.skeletonTimelineJSON {
            SkeletonTimelineSummaryCard(timeline: timeline)
        } else if coordinator.wizardTracker.currentStep == .artifactDiscovery,
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
                            handleToolResult { await coordinator.completeUpload(id: request.id, fileURLs: urls) }
                        },
                        onDecline: {
                            handleToolResult { await coordinator.skipUpload(id: request.id) }
                        }
                    )
                }
            }
        }
    }

    private func uploadRequests() -> [OnboardingUploadRequest] {
        var filtered: [OnboardingUploadRequest]
        switch coordinator.wizardTracker.currentStep {
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
            let kinds = filtered.map(\.kind.rawValue).joined(separator: ",")
            Logger.debug("📤 Pending upload requests surfaced in tool pane (step: \(coordinator.wizardTracker.currentStep.rawValue), kinds: \(kinds))", category: .ai)
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
        if coordinator.toolRouter.pendingApplicantProfileIntake != nil { return true }
        if coordinator.toolRouter.pendingChoicePrompt != nil { return true }
        if coordinator.toolRouter.pendingValidationPrompt != nil { return true }
        if coordinator.toolRouter.pendingApplicantProfileRequest != nil { return true }
        if coordinator.toolRouter.pendingSectionToggleRequest != nil { return true }
        if service.pendingPhaseAdvanceRequest != nil { return true }
        return false
    }

    private func hasSummaryCard(
        service: OnboardingInterviewService,
        coordinator: OnboardingInterviewCoordinator
    ) -> Bool {
        switch coordinator.wizardTracker.currentStep {
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

    /// Helper to wrap coordinator method calls with tool continuation resume
    private func handleToolResult(_ action: @escaping () async -> (UUID, JSON)?) {
        Task {
            let result = await action()
            await service.resumeToolContinuation(from: result)
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
        guard let base64 = profile["image"].string,
              let data = Data(base64Encoded: base64),
              let nsImage = NSImage(data: data) else {
            return nil
        }
        return Image(nsImage: nsImage)
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
