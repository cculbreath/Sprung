import AppKit
import SwiftyJSON
import SwiftUI
import UniformTypeIdentifiers
struct OnboardingInterviewToolPane: View {
    @Environment(ApplicantProfileStore.self) private var applicantProfileStore
    @Environment(ExperienceDefaultsStore.self) private var experienceDefaultsStore
    @Bindable var coordinator: OnboardingInterviewCoordinator
    @Binding var isOccupied: Bool
    var body: some View {
        let paneOccupied = isPaneOccupied(coordinator: coordinator)
        let isLLMActive = coordinator.ui.isProcessing || coordinator.ui.pendingStreamingStatus != nil
        // Always show spinner during any busy state, regardless of what cards are shown
        let showSpinner = coordinator.ui.pendingExtraction != nil || isLLMActive
        return VStack(alignment: .leading, spacing: 16) {
            if coordinator.ui.pendingExtraction != nil {
                Spacer(minLength: 0)
            } else {
                let uploads = uploadRequests()
                if !uploads.isEmpty {
                    uploadRequestsView(uploads)
                } else if let intake = coordinator.pendingApplicantProfileIntake {
                    ApplicantProfileIntakeCard(
                        state: intake,
                        coordinator: coordinator
                    )
                } else if let prompt = coordinator.pendingChoicePrompt {
                    InterviewChoicePromptCard(
                        prompt: prompt,
                        onSubmit: { selection in
                            Task {
                                await coordinator.submitChoiceSelection(selection)
                            }
                        },
                        onCancel: {
                            // Note: Choice cancellation not implemented - user must make a selection
                        }
                    )
                } else if let validation = coordinator.pendingValidationPrompt {
                    if validation.dataType == "knowledge_card" {
                        KnowledgeCardValidationHost(
                            prompt: validation,
                            artifactsJSON: coordinator.ui.artifactRecords,
                            coordinator: coordinator
                        )
                    } else if validation.dataType == "skeleton_timeline" {
                        // Check mode to determine which UI to show
                        TimelineCardEditorView(
                            timeline: validation.payload,
                            coordinator: coordinator,
                            mode: validation.mode == .editor ? .editor : .validation,
                            onValidationSubmit: validation.mode == .validation ? { status in
                                Task {
                                    await coordinator.submitValidationAndResume(
                                        status: status,
                                        updatedData: nil,  // Timeline already saved, no modifications
                                        changes: nil,
                                        notes: nil
                                    )
                                }
                            } : nil,
                            onSubmitChangesOnly: validation.mode == .validation ? {
                                Task {
                                    // Clear validation prompt and let LLM reassess changes
                                    await coordinator.clearValidationPromptAndNotifyLLM(
                                        message: "User made changes to the timeline cards and submitted them for review. Please reassess the updated timeline, ask any clarifying questions if needed, or submit for validation again when ready."
                                    )
                                }
                            } : nil
                        )
                    } else {
                        OnboardingValidationReviewCard(
                            prompt: validation,
                            onSubmit: { decision, updated, notes in
                                Task {
                                    await coordinator.submitValidationAndResume(
                                        status: decision.rawValue,
                                        updatedData: updated,
                                        changes: nil,
                                        notes: notes
                                    )
                                }
                            },
                            onCancel: {
                                // Note: Validation cancellation not implemented - user must approve or reject
                            }
                        )
                    }
                } else if let phaseAdvanceRequest = coordinator.ui.pendingPhaseAdvanceRequest {
                    OnboardingPhaseAdvanceDialog(
                        request: phaseAdvanceRequest,
                        onSubmit: { decision, feedback in
                            Task {
                                switch decision {
                                case .approved:
                                    await coordinator.approvePhaseAdvance()
                                case .denied:
                                    await coordinator.denyPhaseAdvance(feedback: nil)
                                case .deniedWithFeedback:
                                    await coordinator.denyPhaseAdvance(feedback: feedback)
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
                            Task {
                                await coordinator.confirmApplicantProfile(draft: draft)
                            }
                        },
                        onCancel: {
                            Task {
                                await coordinator.rejectApplicantProfile(reason: "User cancelled")
                            }
                        }
                    )
                } else if let sectionToggle = coordinator.pendingSectionToggleRequest {
                    ResumeSectionsToggleCard(
                        request: sectionToggle,
                        existingDraft: experienceDefaultsStore.loadDraft(),
                        onConfirm: { enabled in
                            Task {
                                await coordinator.confirmSectionToggle(enabled: enabled)
                            }
                        },
                        onCancel: {
                            Task {
                                await coordinator.rejectSectionToggle(reason: "User cancelled")
                            }
                        }
                    )
                } else if let profileSummary = coordinator.pendingApplicantProfileSummary {
                    ApplicantProfileSummaryCard(
                        profile: profileSummary,
                        imageData: nil  // Image data is in the JSON profile
                    )
                } else {
                    supportingContent()
                }
            }
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .overlay {
            ZStack {
                if let extraction = coordinator.ui.pendingExtraction {
                    ExtractionProgressOverlay(
                        items: extraction.progressItems,
                        statusText: coordinator.ui.currentStatusMessage
                    )
                    .transition(.opacity.combined(with: .scale))
                    .zIndex(1)
                } else if showSpinner {
                    // Use currentStatusMessage if available, otherwise fall back to pendingStreamingStatusSync
                    let statusText = coordinator.ui.currentStatusMessage ?? coordinator.ui.pendingStreamingStatus?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    AnimatedThinkingText(statusMessage: statusText)
                        .padding(.vertical, 32)
                        .padding(.horizontal, 32)
                        .background(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(.regularMaterial)
                                .shadow(color: Color.black.opacity(0.15), radius: 20, y: 10)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
                                .blendMode(.plusLighter)
                        )
                        .allowsHitTesting(false)
                        .transition(.opacity.combined(with: .scale))
                        .zIndex(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(
            .easeInOut(duration: 0.2),
            value: showSpinner
        )
        .onAppear { isOccupied = paneOccupied }
        .onChange(of: paneOccupied) { _, newValue in
            isOccupied = newValue
        }
    }
    @ViewBuilder
    private func supportingContent() -> some View {
        if let extraction = coordinator.ui.pendingExtraction {
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
        if coordinator.ui.phase == .phase2DeepDive {
            VStack(spacing: 16) {
                EvidenceRequestView(coordinator: coordinator)
                DraftKnowledgeListView(coordinator: coordinator)
            }
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
                                await coordinator.completeUploadAndResume(id: request.id, fileURLs: urls)
                            }
                        },
                        onDecline: {
                            Task {
                                await coordinator.skipUploadAndResume(id: request.id)
                            }
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
            filtered = coordinator.pendingUploadRequests.filter {
                [.resume, .linkedIn].contains($0.kind) ||
                    ($0.kind == .generic && $0.metadata.targetKey == "basics.image")
            }
        case .artifactDiscovery:
            filtered = coordinator.pendingUploadRequests.filter { [.artifact, .generic].contains($0.kind) }
        case .writingCorpus:
            filtered = coordinator.pendingUploadRequests.filter { $0.kind == .writingSample }
        case .wrapUp:
            filtered = coordinator.pendingUploadRequests
        case .introduction:
            filtered = coordinator.pendingUploadRequests.filter {
                $0.kind == .generic && $0.metadata.targetKey == "basics.image"
            }
        }
        if filtered.count != coordinator.pendingUploadRequests.count {
            let headshotRequests = coordinator.pendingUploadRequests.filter { $0.metadata.targetKey == "basics.image" }
            for request in headshotRequests where filtered.contains(where: { $0.id == request.id }) == false {
                filtered.append(request)
            }
        }
        if !filtered.isEmpty {
            let kinds = filtered.map { $0.kind.rawValue }.joined(separator: ",")
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
                await coordinator.completeUploadAndResume(id: request.id, fileURLs: urls)
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
    private func isPaneOccupied(coordinator: OnboardingInterviewCoordinator) -> Bool {
        hasInteractiveCard(coordinator: coordinator) ||
            hasSummaryCard(coordinator: coordinator)
    }
    private func hasInteractiveCard(coordinator: OnboardingInterviewCoordinator) -> Bool {
        if coordinator.ui.pendingExtraction != nil { return true }
        if !uploadRequests().isEmpty { return true }
        // Don't count loading state as occupying the pane - allow spinner to show
        if let intake = coordinator.pendingApplicantProfileIntake {
            if case .loading = intake.mode { return false }
            return true
        }
        if coordinator.pendingChoicePrompt != nil { return true }
        if coordinator.pendingValidationPrompt != nil { return true }
        if coordinator.pendingApplicantProfileRequest != nil { return true }
        if coordinator.pendingSectionToggleRequest != nil { return true }
        if coordinator.ui.pendingPhaseAdvanceRequest != nil { return true }
        return false
    }
    private func hasSummaryCard(
        coordinator: OnboardingInterviewCoordinator
    ) -> Bool {
        // ApplicantProfileSummaryCard occupies the pane and should prevent spinner
        if coordinator.pendingApplicantProfileSummary != nil {
            return true
        }
        return false
    }
}
private struct ExtractionProgressOverlay: View {
    let items: [ExtractionProgressItem]
    let statusText: String?
    private var trimmedStatus: String? {
        guard let statusText else { return nil }
        let trimmed = statusText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    var body: some View {
        VStack(spacing: 28) {
            AnimatedThinkingText(statusMessage: statusText)
            VStack(alignment: .leading, spacing: 18) {
                Text("Processing résumé…")
                    .font(.headline)
                ExtractionProgressChecklistView(items: items)
            }
            .padding(.vertical, 26)
            .padding(.horizontal, 26)
            .frame(maxWidth: 420, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(Color.white.opacity(0.4), lineWidth: 0.5)
                    .blendMode(.plusLighter)
            )
            .shadow(color: Color.black.opacity(0.18), radius: 28, y: 22)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}
private struct KnowledgeCardValidationHost: View {
    let prompt: OnboardingValidationPrompt
    let coordinator: OnboardingInterviewCoordinator
    @State private var draft: KnowledgeCardDraft
    private let artifactRecords: [ArtifactRecord]
    init(
        prompt: OnboardingValidationPrompt,
        artifactsJSON: [JSON],
        coordinator: OnboardingInterviewCoordinator
    ) {
        self.prompt = prompt
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
                    await coordinator.submitValidationAndResume(
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
                    await coordinator.submitValidationAndResume(
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
private struct EnabledSectionsSummaryCard: View {
    let sections: Set<String>
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
        sections.sorted().compactMap { identifier in
            ExperienceSectionKey.fromOnboardingIdentifier(identifier)?.metadata.title
        }
    }
}
