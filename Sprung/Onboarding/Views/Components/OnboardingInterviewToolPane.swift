import AppKit
import SwiftyJSON
import SwiftUI
import UniformTypeIdentifiers
struct OnboardingInterviewToolPane: View {
    @Environment(ApplicantProfileStore.self) private var applicantProfileStore
    @Environment(ExperienceDefaultsStore.self) private var experienceDefaultsStore
    @Bindable var coordinator: OnboardingInterviewCoordinator
    @Binding var isOccupied: Bool
    @State private var selectedTab: ToolPaneTabsView<AnyView>.Tab = .interview
    @State private var isPaneDropTargetHighlighted = false

    var body: some View {
        let paneOccupied = isPaneOccupied(coordinator: coordinator)
        let isLLMActive = coordinator.ui.isProcessing || coordinator.ui.pendingStreamingStatus != nil
        let showSpinner = coordinator.ui.pendingExtraction != nil || isLLMActive

        return ToolPaneTabsView(
            coordinator: coordinator,
            interviewContent: { AnyView(interviewTabContent) },
            selectedTab: $selectedTab
        )
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay {
            ZStack {
                // Drop zone highlight border
                if isPaneDropTargetHighlighted {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            Color.accentColor,
                            style: StrokeStyle(lineWidth: 2.5, dash: [10, 6])
                        )
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.accentColor.opacity(0.06))
                                .padding(6)
                        )
                        .allowsHitTesting(false)
                        .transition(.opacity)
                        .zIndex(0)
                }

                if let extraction = coordinator.ui.pendingExtraction {
                    ExtractionProgressOverlay(
                        items: extraction.progressItems,
                        statusText: coordinator.ui.currentStatusMessage
                    )
                    .transition(.opacity.combined(with: .scale))
                    .zIndex(1)
                } else if showSpinner {
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
        .animation(.easeInOut(duration: 0.2), value: showSpinner)
        .animation(.easeInOut(duration: 0.15), value: isPaneDropTargetHighlighted)
        .onAppear { isOccupied = paneOccupied }
        .onChange(of: paneOccupied) { _, newValue in
            isOccupied = newValue
        }
        // Auto-switch to Interview tab when LLM surfaces interactive content
        .onChange(of: hasInteractiveCard(coordinator: coordinator)) { _, hasCard in
            if hasCard && selectedTab != .interview {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedTab = .interview
                }
            }
        }
        // Pane-level drop zone - catches drops anywhere in the tool pane
        .onDrop(of: DropZoneHandler.acceptedDropTypes, isTargeted: $isPaneDropTargetHighlighted) { providers in
            handlePaneDrop(providers: providers)
            return true
        }
    }

    // MARK: - Pane Drop Handling

    private func handlePaneDrop(providers: [NSItemProvider]) {
        DropZoneHandler.handleDrop(providers: providers) { urls in
            guard !urls.isEmpty else { return }

            // Route based on context
            let pendingUploads = uploadRequests()
            if let uploadRequest = pendingUploads.first {
                // Complete the pending upload request
                Task {
                    await coordinator.completeUploadAndResume(id: uploadRequest.id, fileURLs: urls)
                }
            } else {
                // No pending request - route based on phase
                switch coordinator.ui.phase {
                case .phase3WritingCorpus:
                    Task { await coordinator.uploadWritingSamples(urls) }
                case .phase2DeepDive:
                    // Phase 2: upload files and re-activate document collection UI if it was closed
                    let wasDocCollectionActive = coordinator.ui.isDocumentCollectionActive
                    Task {
                        await coordinator.uploadFilesDirectly(urls)
                        // Only re-activate if document collection was previously closed (after Done with Uploads)
                        if !wasDocCollectionActive {
                            await coordinator.activateDocumentCollection()
                        }
                    }
                default:
                    // Phase 1 or complete - use direct upload without document collection
                    Task { await coordinator.uploadFilesDirectly(urls) }
                }
            }
        }
    }

    // MARK: - Interview Tab Content

    @ViewBuilder
    private var interviewTabContent: some View {
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
                onCancel: { }
            )
        } else if let validation = coordinator.pendingValidationPrompt, validation.mode == .editor {
            // Only show editor mode validations in tool pane
            // Validation mode prompts are shown as modal sheets
            validationContent(validation)
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
                imageData: nil
            )
        } else if shouldShowProfileUntilTimelineLoads, let storedProfile = coordinator.ui.lastApplicantProfileSummary {
            ApplicantProfileSummaryCard(
                profile: storedProfile,
                imageData: nil
            )
        } else {
            // Phase-specific default content for Interview tab
            phaseSpecificInterviewContent
        }
    }

    @ViewBuilder
    private func validationContent(_ validation: OnboardingValidationPrompt) -> some View {
        if validation.dataType == OnboardingDataType.knowledgeCard.rawValue {
            KnowledgeCardValidationHost(
                prompt: validation,
                artifactsJSON: coordinator.ui.artifactRecords,
                coordinator: coordinator
            )
        } else if validation.dataType == OnboardingDataType.skeletonTimeline.rawValue {
            // Timeline editor mode is now handled by the Timeline tab directly
            // This branch should not be reached for editor mode (isTimelineEditorActive handles it)
            // Validation mode is handled by modal sheet in OnboardingInterviewView
            EmptyView()
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
                onCancel: { }
            )
        }
    }

    @ViewBuilder
    private var phaseSpecificInterviewContent: some View {
        switch coordinator.ui.phase {
        case .phase2DeepDive:
            // Show DocumentCollectionView when active, otherwise show KC generation view
            if coordinator.ui.isDocumentCollectionActive {
                DocumentCollectionView(
                    coordinator: coordinator,
                    onAssessCompleteness: {
                        Task {
                            // Trigger card merge directly and notify LLM of results
                            await coordinator.finishUploadsAndMergeCards()
                        }
                    },
                    onCancelExtractionsAndFinish: {
                        Task {
                            // Cancel active extraction agents
                            await coordinator.cancelExtractionAgentsAndFinishUploads()
                        }
                    },
                    onDropFiles: { urls, extractionMethod in
                        Task { await coordinator.uploadFilesDirectly(urls, extractionMethod: extractionMethod) }
                    },
                    onSelectFiles: { openDirectUploadPanel() },
                    onSelectGitRepo: { repoURL in
                        Task { await coordinator.startGitRepoAnalysis(repoURL) }
                    },
                    onFetchURL: { urlString in
                        await coordinator.fetchURLForArtifact(urlString)
                    }
                )
            } else {
                VStack(spacing: 12) {
                    PersistentUploadDropZone(
                        onDropFiles: { urls, extractionMethod in
                            Task {
                                await coordinator.uploadFilesDirectly(urls, extractionMethod: extractionMethod)
                                // Re-activate document collection UI to allow re-merge
                                await coordinator.activateDocumentCollection()
                            }
                        },
                        onSelectFiles: { openDirectUploadPanel() },
                        onSelectGitRepo: { repoURL in
                            Task {
                                await coordinator.startGitRepoAnalysis(repoURL)
                                // Re-activate document collection UI to allow re-merge
                                await coordinator.activateDocumentCollection()
                            }
                        }
                    )
                    KnowledgeCardCollectionView(
                        coordinator: coordinator,
                        onGenerateCards: {
                            Task {
                                await coordinator.eventBus.publish(.generateCardsButtonClicked)
                            }
                        },
                        onAdvanceToNextPhase: {
                            Task {
                                await coordinator.requestPhaseAdvanceFromUI()
                            }
                        }
                    )
                }
            }
        case .phase3WritingCorpus:
            WritingCorpusCollectionView(
                coordinator: coordinator,
                onDropFiles: { urls in
                    Task { await coordinator.uploadWritingSamples(urls) }
                },
                onSelectFiles: { openWritingSamplePanel() },
                onDoneWithSamples: {
                    Task { await coordinator.completeWritingSamplesCollection() }
                },
                onEndInterview: {
                    Task { await coordinator.endInterview() }
                }
            )
        default:
            // Phase 1 or other: show empty state with guidance
            InterviewTabEmptyState(phase: coordinator.ui.phase)
        }
    }

    private func openWritingSamplePanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [
            UTType.pdf,
            UTType(filenameExtension: "docx"),
            UTType.plainText,
            UTType(filenameExtension: "md")
        ].compactMap { $0 }
        panel.begin { result in
            guard result == .OK, !panel.urls.isEmpty else { return }
            Task {
                await coordinator.uploadWritingSamples(panel.urls)
            }
        }
    }

    private func openDirectUploadPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [
            UTType.pdf,
            UTType(filenameExtension: "docx"),
            UTType.plainText,
            UTType.png,
            UTType.jpeg,
            UTType(filenameExtension: "md"),
            UTType.json
        ].compactMap { $0 }
        panel.begin { result in
            guard result == .OK, !panel.urls.isEmpty else { return }
            Task {
                await coordinator.uploadFilesDirectly(panel.urls)
            }
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
        // Always include any pending requests that weren't captured by step-based filtering
        // This ensures generic uploads (like profile photos) always appear
        for request in coordinator.pendingUploadRequests where !filtered.contains(where: { $0.id == request.id }) {
            filtered.append(request)
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
                candidates = ["pdf", "docx", "txt", "json"]
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
        // Only editor mode validations count as occupying tool pane
        // Validation mode prompts are shown as modal sheets
        // Skip skeleton_timeline - it's now handled by the Timeline tab
        if let validation = coordinator.pendingValidationPrompt,
           validation.mode == .editor,
           validation.dataType != OnboardingDataType.skeletonTimeline.rawValue {
            return true
        }
        if coordinator.pendingApplicantProfileRequest != nil { return true }
        if coordinator.pendingSectionToggleRequest != nil { return true }
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

    /// Show profile summary until skeleton timeline is loaded to prevent jarring transition
    private var shouldShowProfileUntilTimelineLoads: Bool {
        // Only applies during resume intake step when building the timeline
        guard coordinator.wizardTracker.currentStep == .resumeIntake else { return false }
        // If timeline has loaded, no need to show placeholder
        guard coordinator.ui.skeletonTimeline == nil else { return false }
        // If we have a stored profile summary, show it
        return coordinator.ui.lastApplicantProfileSummary != nil
    }
}
private struct ExtractionProgressOverlay: View {
    let items: [ExtractionProgressItem]
    let statusText: String?
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
            onReject: { reason in
                Task {
                    await coordinator.submitValidationAndResume(
                        status: "rejected",
                        updatedData: nil,
                        changes: nil,
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

private struct InterviewTabEmptyState: View {
    let phase: InterviewPhase

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundStyle(.secondary)

            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var icon: String {
        switch phase {
        case .phase1CoreFacts:
            return "person.text.rectangle"
        case .phase2DeepDive:
            return "doc.badge.plus"
        case .phase3WritingCorpus:
            return "text.document"
        case .complete:
            return "checkmark.circle"
        }
    }

    private var title: String {
        switch phase {
        case .phase1CoreFacts:
            return "Building Your Profile"
        case .phase2DeepDive:
            return "Deep Dive"
        case .phase3WritingCorpus:
            return "Writing Samples"
        case .complete:
            return "Interview Complete"
        }
    }

    private var message: String {
        switch phase {
        case .phase1CoreFacts:
            return "The AI is gathering information about your background. Interactive cards will appear here as the conversation progresses."
        case .phase2DeepDive:
            return "Upload documents or add artifacts to support your experience entries."
        case .phase3WritingCorpus:
            return "Upload writing samples to help capture your voice and style."
        case .complete:
            return "The interview has been completed. You can browse your collected data in the other tabs."
        }
    }
}
