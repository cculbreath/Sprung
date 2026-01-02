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
                case .phase1VoiceContext:
                    // Phase 1: If we're in writing samples collection, route to writing samples
                    // Otherwise use direct upload (e.g., for profile photo before writing samples)
                    if shouldShowWritingSampleUI {
                        Task { await coordinator.uploadWritingSamples(urls) }
                    } else {
                        Task { await coordinator.uploadFilesDirectly(urls) }
                    }
                case .phase3EvidenceCollection:
                    // Phase 3: upload files and re-activate document collection UI if it was closed
                    let wasDocCollectionActive = coordinator.ui.isDocumentCollectionActive
                    Task {
                        await coordinator.uploadFilesDirectly(urls)
                        // Only re-activate if document collection was previously closed (after Done with Uploads)
                        if !wasDocCollectionActive {
                            await coordinator.activateDocumentCollection()
                        }
                    }
                case .phase2CareerStory:
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
                    // Phase 4 or complete - use direct upload without document collection
                    Task { await coordinator.uploadFilesDirectly(urls) }
                }
            }
        }
    }

    // MARK: - Interview Tab Content

    @ViewBuilder
    private var interviewTabContent: some View {
        VStack(spacing: 0) {
            // Main content
            interviewTabMainContent

            // Persistent "Skip to Next Phase" button at bottom
            if coordinator.ui.phase != .complete {
                Divider()
                    .padding(.top, 12)
                SkipToNextPhaseCard(
                    currentPhase: coordinator.ui.phase,
                    onSkip: {
                        Task {
                            await coordinator.advanceToNextPhaseFromUI()
                        }
                    }
                )
                .padding(.top, 8)
            }
        }
    }

    @ViewBuilder
    private var interviewTabMainContent: some View {
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
        } else if let profileSummary = coordinator.pendingApplicantProfileSummary, !shouldShowWritingSampleUI {
            // Show profile summary UNLESS we should be showing writing sample UI
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
                artifacts: coordinator.sessionArtifacts,
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
        case .phase2CareerStory:
            // Show DocumentCollectionView when active, KnowledgeCardCollectionView during card workflow,
            // otherwise show empty state (timeline is in Timeline tab)
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
                    onDropFiles: { urls in
                        Task { await coordinator.uploadFilesDirectly(urls) }
                    },
                    onSelectFiles: { openDirectUploadPanel() },
                    onSelectGitRepo: { repoURL in
                        Task { await coordinator.startGitRepoAnalysis(repoURL) }
                    },
                    onFetchURL: { urlString in
                        await coordinator.fetchURLForArtifact(urlString)
                    }
                )
            } else if coordinator.ui.isMergingCards || coordinator.ui.cardAssignmentsReadyForApproval || coordinator.ui.isGeneratingCards {
                // Card workflow in progress - show knowledge card collection view
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
            } else {
                // Default: empty state - timeline is in Timeline tab
                InterviewTabEmptyState(phase: .phase2CareerStory)
            }
        case .phase3EvidenceCollection:
            // Show DocumentCollectionView when active, KnowledgeCardCollectionView during card workflow,
            // otherwise show empty state
            if coordinator.ui.isDocumentCollectionActive {
                DocumentCollectionView(
                    coordinator: coordinator,
                    onAssessCompleteness: {
                        Task {
                            await coordinator.finishUploadsAndMergeCards()
                        }
                    },
                    onCancelExtractionsAndFinish: {
                        Task {
                            await coordinator.cancelExtractionAgentsAndFinishUploads()
                        }
                    },
                    onDropFiles: { urls in
                        Task { await coordinator.uploadFilesDirectly(urls) }
                    },
                    onSelectFiles: { openDirectUploadPanel() },
                    onSelectGitRepo: { repoURL in
                        Task { await coordinator.startGitRepoAnalysis(repoURL) }
                    },
                    onFetchURL: { urlString in
                        await coordinator.fetchURLForArtifact(urlString)
                    }
                )
            } else if coordinator.ui.isMergingCards || coordinator.ui.cardAssignmentsReadyForApproval || coordinator.ui.isGeneratingCards {
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
            } else {
                // Default: empty state - document collection UI hidden after Done with Uploads
                InterviewTabEmptyState(phase: .phase3EvidenceCollection)
            }
        case .phase1VoiceContext:
            // Phase 1: Show writing sample collection with skip option
            // Drop handling is done by the pane-level drop zone
            Phase1WritingSampleView(
                coordinator: coordinator,
                onSelectFiles: { openWritingSamplePanel() },
                onDoneWithSamples: {
                    Task { await coordinator.completeWritingSamplesCollection() }
                },
                onSkipSamples: {
                    Task { await coordinator.skipWritingSamplesCollection() }
                }
            )
        default:
            // Other phases: show empty state with guidance
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
        case .voice:
            // Phase 1: Resume, LinkedIn, profile photo ONLY
            // IMPORTANT: Do NOT include writing samples here - the sidebar has a dedicated Phase1WritingSampleView
            filtered = coordinator.pendingUploadRequests.filter {
                [.resume, .linkedIn].contains($0.kind) ||
                    ($0.kind == .generic && $0.metadata.targetKey == "basics.image")
            }
            // For voice phase, also add any generic requests that aren't writing samples
            // but EXCLUDE writing samples since Phase1WritingSampleView handles those
            for request in coordinator.pendingUploadRequests
            where !filtered.contains(where: { $0.id == request.id })
                && request.kind != .writingSample {
                filtered.append(request)
            }
        case .story:
            // Phase 2: Additional artifacts
            filtered = coordinator.pendingUploadRequests.filter { [.artifact, .generic].contains($0.kind) }
            // Include other non-writing sample requests not captured by filtering
            for request in coordinator.pendingUploadRequests
            where !filtered.contains(where: { $0.id == request.id })
                && request.kind != .writingSample {
                filtered.append(request)
            }
        case .evidence:
            // Phase 3: Writing samples and other evidence
            filtered = coordinator.pendingUploadRequests.filter { $0.kind == .writingSample }
        case .strategy:
            // Phase 4: All remaining uploads
            filtered = coordinator.pendingUploadRequests
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

    /// True when we should show the Phase 1 writing sample collection UI
    private var shouldShowWritingSampleUI: Bool {
        // Only in Phase 1
        guard coordinator.ui.phase == .phase1VoiceContext else { return false }
        // Profile must be complete
        let profileComplete = coordinator.ui.objectiveStatuses[OnboardingObjectiveId.applicantProfileComplete.rawValue] == "completed"
        // Writing samples must NOT be complete
        let writingSamplesComplete = coordinator.ui.objectiveStatuses[OnboardingObjectiveId.writingSamplesCollected.rawValue] == "completed"
        return profileComplete && !writingSamplesComplete
    }

    /// Show profile summary until skeleton timeline is loaded to prevent jarring transition
    /// BUT: Don't show it during writing samples collection - show the upload UI instead
    private var shouldShowProfileUntilTimelineLoads: Bool {
        // Only applies during voice phase when building the timeline
        guard coordinator.wizardTracker.currentStep == .voice else { return false }
        // If timeline has loaded, no need to show placeholder
        guard coordinator.ui.skeletonTimeline == nil else { return false }

        // DON'T show profile summary if we should be showing writing sample UI
        // (profile complete + writing samples not yet complete)
        let profileComplete = coordinator.ui.objectiveStatuses[OnboardingObjectiveId.applicantProfileComplete.rawValue] == "completed"
        let writingSamplesComplete = coordinator.ui.objectiveStatuses[OnboardingObjectiveId.writingSamplesCollected.rawValue] == "completed"
        if profileComplete && !writingSamplesComplete {
            return false  // Let Phase1WritingSampleView show instead
        }

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
    private let artifactDisplayInfos: [ArtifactDisplayInfo]
    init(
        prompt: OnboardingValidationPrompt,
        artifacts: [ArtifactRecord],
        coordinator: OnboardingInterviewCoordinator
    ) {
        self.prompt = prompt
        self.coordinator = coordinator
        _draft = State(initialValue: KnowledgeCardDraft(json: prompt.payload))
        artifactDisplayInfos = artifacts.map { ArtifactDisplayInfo(from: $0) }
    }
    var body: some View {
        KnowledgeCardReviewCard(
            card: $draft,
            artifacts: artifactDisplayInfos,
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
        case .phase1VoiceContext:
            return "person.text.rectangle"
        case .phase2CareerStory:
            return "doc.badge.plus"
        case .phase3EvidenceCollection:
            return "text.document"
        case .phase4StrategicSynthesis:
            return "chart.bar.doc.horizontal"
        case .complete:
            return "checkmark.circle"
        }
    }

    private var title: String {
        switch phase {
        case .phase1VoiceContext:
            return "Building Your Profile"
        case .phase2CareerStory:
            return "Career Story"
        case .phase3EvidenceCollection:
            return "Evidence Collection"
        case .phase4StrategicSynthesis:
            return "Strategic Synthesis"
        case .complete:
            return "Interview Complete"
        }
    }

    private var message: String {
        switch phase {
        case .phase1VoiceContext:
            return "The AI is gathering information about your background. Interactive cards will appear here as the conversation progresses."
        case .phase2CareerStory:
            return "Building your career timeline. Add experience entries and enrich each with context."
        case .phase3EvidenceCollection:
            return "Upload documents, code repositories, and other evidence to support your experience."
        case .phase4StrategicSynthesis:
            return "Synthesizing your experience into strategic recommendations for your job search."
        case .complete:
            return "The interview has been completed. You can browse your collected data in the other tabs."
        }
    }
}

// MARK: - Skip to Next Phase Card

private struct SkipToNextPhaseCard: View {
    let currentPhase: InterviewPhase
    let onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "forward.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Ready to move on?")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Text(nextPhaseDescription)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onSkip) {
                HStack {
                    Text("Skip to \(nextPhaseName)")
                    Image(systemName: "chevron.right")
                        .font(.caption)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var nextPhaseName: String {
        switch currentPhase {
        case .phase1VoiceContext:
            return "Career Story"
        case .phase2CareerStory:
            return "Evidence Collection"
        case .phase3EvidenceCollection:
            return "Strategic Synthesis"
        case .phase4StrategicSynthesis:
            return "Complete Interview"
        case .complete:
            return "Complete"
        }
    }

    private var nextPhaseDescription: String {
        switch currentPhase {
        case .phase1VoiceContext:
            return "Next: Map out your career timeline from your resume or through conversation."
        case .phase2CareerStory:
            return "Next: Upload documents, code repos, and other evidence to support your experience."
        case .phase3EvidenceCollection:
            return "Next: Synthesize your strengths, identify pitfalls, and finalize your candidate dossier."
        case .phase4StrategicSynthesis:
            return "Finish the interview and start building resumes and applications."
        case .complete:
            return "Interview complete."
        }
    }
}
