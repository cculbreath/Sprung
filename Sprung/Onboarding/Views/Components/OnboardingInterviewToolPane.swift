import SwiftyJSON
import SwiftUI
struct OnboardingInterviewToolPane: View {
    @Environment(ApplicantProfileStore.self) private var applicantProfileStore
    @Environment(ExperienceDefaultsStore.self) private var experienceDefaultsStore
    @Environment(CoverRefStore.self) private var coverRefStore
    @Bindable var coordinator: OnboardingInterviewCoordinator
    @Binding var isOccupied: Bool
    @State private var selectedTab: ToolPaneTabsView<AnyView>.Tab = .interview
    @State private var isPaneDropTargetHighlighted = false
    @State private var showSkipToCompleteWarning = false
    @State private var missingGoalItems: [String] = []

    var body: some View {
        let paneOccupied = isPaneOccupied(coordinator: coordinator)
        // Only show spinner for document extraction, not LLM activity
        // LLM text streaming is indicated by the chatbox glow instead
        let showSpinner = coordinator.ui.pendingExtraction != nil

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
        // Warning alert when skipping to complete with unpersisted goals
        .alert("Complete Interview with Missing Data?", isPresented: $showSkipToCompleteWarning) {
            Button("Complete Anyway", role: .destructive) {
                Task {
                    await coordinator.advanceToNextPhaseFromUI()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The following interview goals have no persisted data:\n\n• \(missingGoalItems.joined(separator: "\n• "))\n\nThis data helps generate better resumes and cover letters. Consider continuing the interview to collect more information.")
        }
    }

    // MARK: - Pane Drop Handling

    private func handlePaneDrop(providers: [NSItemProvider]) {
        DropZoneHandler.handleDrop(providers: providers) { urls in
            guard !urls.isEmpty else { return }

            // Route based on context
            let pendingUploads = ToolPaneUploadHandler.uploadRequests(
                for: coordinator.wizardTracker.currentStep,
                pending: coordinator.pendingUploadRequests
            )
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
                        // In phase 4, check for unpersisted goals before completing
                        if coordinator.ui.phase == .phase4StrategicSynthesis {
                            let missing = checkForMissingGoals()
                            if !missing.isEmpty {
                                missingGoalItems = missing
                                showSkipToCompleteWarning = true
                                return
                            }
                        }
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
        let uploads = ToolPaneUploadHandler.uploadRequests(
            for: coordinator.wizardTracker.currentStep,
            pending: coordinator.pendingUploadRequests
        )
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
                onSubmitOther: { otherText in
                    Task {
                        await coordinator.submitChoiceSelectionWithOther(otherText)
                    }
                },
                onCancel: {
                    Task {
                        await coordinator.cancelChoiceSelection()
                    }
                }
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
                onConfirm: { config in
                    Task {
                        await coordinator.confirmSectionToggle(config: config)
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
                    onSelectFiles: {
                        ToolPaneUploadHandler.openDirectUploadPanel { urls in
                            Task { await coordinator.uploadFilesDirectly(urls) }
                        }
                    },
                    onSelectGitRepo: { repoURL in
                        Task { await coordinator.startGitRepoAnalysis(repoURL) }
                    },
                    onFetchURL: { urlString in
                        await coordinator.fetchURLForArtifact(urlString)
                    }
                )
            } else if coordinator.ui.isMergingCards || coordinator.ui.cardAssignmentsReadyForApproval || coordinator.ui.isGeneratingCards {
                // Card workflow in progress - show knowledge cards and skills for review
                CardReviewWithStickyFooter(
                    coordinator: coordinator,
                    onGenerateCards: {
                        Task {
                            await coordinator.eventBus.publish(.artifact(.generateCardsButtonClicked))
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
                    onSelectFiles: {
                        ToolPaneUploadHandler.openDirectUploadPanel { urls in
                            Task { await coordinator.uploadFilesDirectly(urls) }
                        }
                    },
                    onSelectGitRepo: { repoURL in
                        Task { await coordinator.startGitRepoAnalysis(repoURL) }
                    },
                    onFetchURL: { urlString in
                        await coordinator.fetchURLForArtifact(urlString)
                    }
                )
            } else if coordinator.ui.isMergingCards || coordinator.ui.cardAssignmentsReadyForApproval || coordinator.ui.isGeneratingCards {
                // Card workflow in progress - show knowledge cards and skills for review
                CardReviewWithStickyFooter(
                    coordinator: coordinator,
                    onGenerateCards: {
                        Task {
                            await coordinator.eventBus.publish(.artifact(.generateCardsButtonClicked))
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
                onSelectFiles: {
                    ToolPaneUploadHandler.openWritingSamplePanel { urls in
                        Task { await coordinator.uploadWritingSamples(urls) }
                    }
                },
                onDoneWithSamples: {
                    Task { await coordinator.completeWritingSamplesCollection() }
                },
                onSkipSamples: {
                    Task { await coordinator.skipWritingSamplesCollection() }
                }
            )
        case .phase4StrategicSynthesis:
            // Phase 4 now focuses on dossier completion
            // SGM (Seed Generation Module) will be presented after Phase 4 completes
            InterviewTabEmptyState(phase: coordinator.ui.phase)
        default:
            // Other phases: show empty state with guidance
            InterviewTabEmptyState(phase: coordinator.ui.phase)
        }
    }

    @ViewBuilder
    private func uploadRequestsView(_ requests: [OnboardingUploadRequest]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(requests) { request in
                    UploadRequestCard(
                        request: request,
                        onSelectFile: {
                            ToolPaneUploadHandler.openPanel(for: request) { urls in
                                Task {
                                    await coordinator.completeUploadAndResume(id: request.id, fileURLs: urls)
                                }
                            }
                        },
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
    private func isPaneOccupied(coordinator: OnboardingInterviewCoordinator) -> Bool {
        hasInteractiveCard(coordinator: coordinator) ||
            hasSummaryCard(coordinator: coordinator)
    }
    private func hasInteractiveCard(coordinator: OnboardingInterviewCoordinator) -> Bool {
        if coordinator.ui.pendingExtraction != nil { return true }
        if !ToolPaneUploadHandler.uploadRequests(
            for: coordinator.wizardTracker.currentStep,
            pending: coordinator.pendingUploadRequests
        ).isEmpty { return true }
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

    // MARK: - Skip-to-Complete Safety Check

    /// Checks for unpersisted interview goals and returns a list of missing items
    private func checkForMissingGoals() -> [String] {
        var missing: [String] = []

        // Check Knowledge Cards
        let kcCount = coordinator.knowledgeCardStore.knowledgeCards.count
        if kcCount == 0 {
            missing.append("Knowledge Cards (0 persisted)")
        }

        // Check Skills
        let skillCount = coordinator.skillStore.skills.count
        if skillCount == 0 {
            missing.append("Skills Bank (0 persisted)")
        }

        // Check Writing Samples (CoverRefs)
        let writingSampleCount = coverRefStore.storedCoverRefs.count
        if writingSampleCount == 0 {
            missing.append("Writing Samples (0 persisted)")
        }

        // Check Experience Defaults - verify meaningful content exists
        let expDraft = experienceDefaultsStore.loadDraft()
        let hasExperienceContent = !expDraft.work.isEmpty ||
            !expDraft.education.isEmpty ||
            !expDraft.projects.isEmpty ||
            !expDraft.volunteer.isEmpty
        if !hasExperienceContent {
            missing.append("Experience Defaults (no work/education/projects)")
        }

        return missing
    }
}
