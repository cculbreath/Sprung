import AppKit
import SwiftUI
import SwiftyJSON
struct OnboardingInterviewView: View {
    @Environment(OnboardingInterviewCoordinator.self) private var interviewCoordinator
    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(DebugSettingsStore.self) private var debugSettings
    @State private var viewModel = OnboardingInterviewViewModel(
        fallbackModelId: OnboardingModelConfig.currentModelId
    )
    @State private var showResumePrompt = false
    #if DEBUG
    @State private var showEventDump = false
    #endif
    @AppStorage("onboardingInterviewDefaultModelId") private var defaultModelId = "gpt-5"
    @AppStorage("onboardingInterviewAllowWebSearchDefault") private var defaultWebSearchAllowed = true
    @Namespace private var wizardTransition

    // Window and content entrance animation state
    @State private var windowAppeared = false
    @State private var progressAppeared = false
    @State private var cardAppeared = false
    @State private var bottomBarAppeared = false
    var body: some View {
        bodyContent
    }
    private var bodyContent: some View {
        @Bindable var coordinator = interviewCoordinator
        @Bindable var uiState = viewModel
        // --- Card visual constants ---
        let corner: CGFloat = 44
        let cardShape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        let contentStack = VStack(spacing: 0) {
            // Progress bar anchored close to top
            OnboardingInterviewStepProgressView(coordinator: coordinator)
                .padding(.top, 16)
                .padding(.bottom, 24)
                .padding(.horizontal, 32)
                .opacity(progressAppeared ? 1 : 0)
                .offset(y: progressAppeared ? 0 : -10)
            // Main body centered within available space
            VStack(spacing: 8) {
                mainCard(
                    coordinator: coordinator,
                    state: uiState
                )
                .animation(.spring(response: 0.4, dampingFraction: 0.82), value: coordinator.wizardTracker.currentStep)
                .opacity(cardAppeared ? 1 : 0)
                .scaleEffect(cardAppeared ? 1 : 0.95)
                Spacer(minLength: 16) // centers body relative to bottom bar
                OnboardingInterviewBottomBar(
                    showBack: shouldShowBackButton(for: coordinator.wizardTracker.currentStep),
                    continueTitle: continueButtonTitle(for: coordinator.wizardTracker.currentStep),
                    isContinueDisabled: isContinueDisabled(coordinator: coordinator),
                    onShowSettings: openSettings,
                    onBack: { handleBack(coordinator: coordinator) },
                    onCancel: { handleCancel() },
                    onContinue: { handleContinue(coordinator: coordinator) }
                )
                .padding(.horizontal, 16)
                .animation(.easeInOut(duration: 0.25), value: coordinator.wizardTracker.currentStep)
                .opacity(bottomBarAppeared ? 1 : 0)
                .offset(y: bottomBarAppeared ? 0 : 15)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 32)
        }
        // Uses system window shadow via BorderlessOverlayWindow.hasShadow = true
        // No SwiftUI shadow overlay needed - system shadow has proper hit testing
        let styledContent = contentStack
            .frame(minWidth: 1040)
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
            .clipShape(cardShape)
            .background(cardShape.fill(.thickMaterial))
            // Window entrance animation
            .scaleEffect(windowAppeared ? 1 : 0.92)
            .opacity(windowAppeared ? 1 : 0)
            .offset(y: windowAppeared ? 0 : 20)
        // --- Lifecycle bindings and tasks ---
        let withLifecycle = styledContent
            .task {
                uiState.configureIfNeeded(
                    coordinator: interviewCoordinator,
                    defaultModelId: defaultModelId,
                    defaultWebSearchAllowed: defaultWebSearchAllowed
                )
            }
            .onChange(of: defaultModelId) { _, newValue in
                uiState.handleDefaultModelChange(newValue: newValue)
            }
            .onChange(of: defaultWebSearchAllowed) { _, newValue in
                if !coordinator.ui.isActive {
                    uiState.webSearchAllowed = newValue
                }
            }
            .onChange(of: coordinator.ui.preferences.allowWebSearch) { _, newValue in
                if coordinator.ui.isActive {
                    uiState.webSearchAllowed = newValue
                }
            }
            .onChange(of: coordinator.ui.interviewJustCompleted) { _, completed in
                if completed {
                    handleInterviewCompleted()
                }
            }
        let withSheets = withLifecycle
            .sheet(isPresented: Binding(
                get: { coordinator.ui.pendingExtraction != nil },
                set: { newValue in
                    if !newValue {
                        coordinator.setExtractionStatus(nil)
                    }
                }
            )) {
                if let pending = coordinator.ui.pendingExtraction {
                    ExtractionReviewSheet(
                        extraction: pending,
                        onConfirm: { _, _ in
                            // FEATURE REQUEST: Extraction confirmation and editing
                            // Status: Deferred to post-M0 milestone
                            // The UI for reviewing and editing extracted data exists, but the confirmation
                            // flow is not yet implemented. When implemented, this should:
                            // 1. Apply user edits to the extracted data
                            // 2. Update StateCoordinator with revised extraction
                            // 3. Resume tool continuation with updated payload
                            Logger.debug("Extraction confirmation is not implemented in milestone M0.")
                        },
                        onCancel: {
                            coordinator.setExtractionStatus(nil)
                        }
                    )
                }
            }
            .alert("Import Failed", isPresented: $uiState.showImportError, presenting: uiState.importErrorText, actions: { _ in
                Button("OK") { uiState.clearImportError() }
            }, message: { message in
                Text(message)
            })
            .alert("Existing Onboarding Data Found", isPresented: $showResumePrompt) {
                Button("Resume") {
                    resumeInterview()
                }
                Button("Start Over", role: .destructive) {
                    startOverInterview()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("You have existing onboarding data (knowledge cards, cover letter sources, and experience defaults). Would you like to resume where you left off, or start over with a fresh session?\n\nWarning: Starting over will permanently delete all knowledge cards, cover letter sources, experience defaults, and reset your applicant profile (including photo) to defaults.")
            }
            // Validation prompts as modal sheets - blocks interaction until user responds
            .sheet(isPresented: Binding(
                get: { coordinator.pendingValidationPrompt?.mode == .validation },
                set: { _ in }
            )) {
                if let validation = coordinator.pendingValidationPrompt {
                    ValidationPromptSheet(
                        validation: validation,
                        coordinator: coordinator
                    )
                }
            }
        return withSheets
            .onAppear {
                // Window container animates first
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    windowAppeared = true
                }
                // Staggered content animations
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8).delay(0.15)) {
                    progressAppeared = true
                }
                withAnimation(.spring(response: 0.5, dampingFraction: 0.75).delay(0.25)) {
                    cardAppeared = true
                }
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8).delay(0.35)) {
                    bottomBarAppeared = true
                }
            }
            .onDisappear {
                windowAppeared = false
                progressAppeared = false
                cardAppeared = false
                bottomBarAppeared = false
            }
            #if DEBUG
            .overlay(alignment: .bottomTrailing) {
                if debugSettings.showOnboardingDebugButton {
                    debugButton
                }
            }
            .sheet(isPresented: $showEventDump) {
                EventDumpView(coordinator: coordinator)
            }
            #endif
    }
    #if DEBUG
    private var debugButton: some View {
        Button(action: {
            showEventDump.toggle()
        }, label: {
            Image(systemName: "ladybug.fill")
                .font(.title2)
                .foregroundStyle(.white)
                .padding(12)
                .background(.purple.gradient, in: Circle())
                .shadow(radius: 4)
        })
        .buttonStyle(.plain)
        .padding(24)
    }
    #endif
}
// MARK: - Layout
private extension OnboardingInterviewView {
    func mainCard(
        coordinator: OnboardingInterviewCoordinator,
        state: OnboardingInterviewViewModel
    ) -> some View {
        Group {
            if coordinator.wizardTracker.currentStep == .introduction {
                OnboardingInterviewIntroductionCard()
                    .matchedGeometryEffect(id: "mainCard", in: wizardTransition)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.95).combined(with: .opacity),
                        removal: .scale(scale: 1.05).combined(with: .opacity)
                    ))
            } else {
                OnboardingInterviewInteractiveCard(
                    coordinator: coordinator,
                    state: state,
                    modelStatusDescription: modelStatusDescription(coordinator: coordinator),
                    onOpenSettings: openSettings
                )
                .frame(width: 920)
                .matchedGeometryEffect(id: "mainCard", in: wizardTransition)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.95).combined(with: .opacity),
                    removal: .scale(scale: 1.05).combined(with: .opacity)
                ))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }
    func continueButtonTitle(for step: OnboardingWizardStep) -> String {
        switch step {
        case .wrapUp:
            return "Finish"
        case .introduction:
            return "Begin Interview"
        default:
            return "Continue"
        }
    }
    func shouldShowBackButton(for step: OnboardingWizardStep) -> Bool {
        step != .introduction
    }
    func isContinueDisabled(
        coordinator: OnboardingInterviewCoordinator
    ) -> Bool {
        switch coordinator.wizardTracker.currentStep {
        case .introduction:
            return appEnvironment.appState.openAiApiKey.isEmpty
        case .resumeIntake:
            return coordinator.ui.isProcessing ||
            coordinator.pendingChoicePrompt != nil ||
            coordinator.pendingApplicantProfileRequest != nil ||
            coordinator.pendingApplicantProfileIntake != nil
        case .artifactDiscovery:
            return coordinator.ui.isProcessing ||
            coordinator.pendingSectionToggleRequest != nil
        default:
            return coordinator.ui.isProcessing
        }
    }
    func handleContinue(
        coordinator: OnboardingInterviewCoordinator
    ) {
        switch coordinator.wizardTracker.currentStep {
        case .introduction:
            beginInterview()
        case .resumeIntake:
            // Wizard steps are now derived from objectives - no manual setting needed
            break
        case .artifactDiscovery:
            // Wizard steps are now derived from objectives - no manual setting needed
            break
        case .writingCorpus:
            // Wizard steps are now derived from objectives - no manual setting needed
            break
        case .wrapUp:
            handleCancel()
        }
    }
    func handleBack(
        coordinator: OnboardingInterviewCoordinator
    ) {
        // Wizard steps are now derived from objectives - no manual reset needed
    }
    func handleCancel() {
        Task {
            await interviewCoordinator.endInterview()
        }
        if let window = NSApp.windows.first(where: { $0 is BorderlessOverlayWindow }) {
            window.orderOut(nil)
        }
    }

    /// Called when interview transitions to .complete phase - closes window and resets session
    func handleInterviewCompleted() {
        Logger.info("🏁 Interview completed - closing window and resetting session", category: .ai)
        // Reset the flag so subsequent interviews can complete
        interviewCoordinator.ui.interviewJustCompleted = false
        // Delete the session so subsequent Interview button clicks start fresh
        interviewCoordinator.deleteCurrentSession()
        // Close the window
        if let window = NSApp.windows.first(where: { $0 is BorderlessOverlayWindow }) {
            window.orderOut(nil)
        }
    }
}
// MARK: - Helpers
private extension OnboardingInterviewView {
    func openSettings() {
        NSApp.sendAction(#selector(AppDelegate.showSettingsWindow), to: nil, from: nil)
    }
    func modelStatusDescription(coordinator: OnboardingInterviewCoordinator) -> String {
        let rawId = viewModel.currentModelId
        let display = rawId.split(separator: "/").last.map(String.init) ?? rawId
        let webText = coordinator.ui.preferences.allowWebSearch ? "on" : "off"
        return "Using \(display) with web search \(webText)."
    }
    func beginInterview() {
        Task { @MainActor in
            guard interviewCoordinator.ui.isActive == false else { return }

            // Check for existing onboarding data (session, ResRefs, CoverRefs, ExperienceDefaults)
            if interviewCoordinator.hasExistingOnboardingData() {
                Logger.info("📝 Found existing onboarding data, showing resume prompt", category: .ai)
                showResumePrompt = true
                return
            }

            Logger.info("📝 Starting fresh interview", category: .ai)
            _ = await interviewCoordinator.startInterview(resumeExisting: false)
        }
    }

    func resumeInterview() {
        Task { @MainActor in
            Logger.info("📝 Resuming existing interview", category: .ai)
            _ = await interviewCoordinator.startInterview(resumeExisting: true)
        }
    }

    func startOverInterview() {
        Task { @MainActor in
            Logger.info("📝 Starting over - clearing all onboarding data", category: .ai)
            interviewCoordinator.clearAllOnboardingData()
            _ = await interviewCoordinator.startInterview(resumeExisting: false)
        }
    }
}

// MARK: - Validation Prompt Sheet

private struct ValidationPromptSheet: View {
    let validation: OnboardingValidationPrompt
    let coordinator: OnboardingInterviewCoordinator
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(headerTitle)
                    .font(.title2.weight(.semibold))
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 16)

            Divider()

            // Content
            validationContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        }
        .frame(minWidth: 700, idealWidth: 800, maxWidth: 900, minHeight: 500, idealHeight: 600, maxHeight: 800)
        .interactiveDismissDisabled(true) // Prevent dismiss by clicking outside
    }

    private var headerTitle: String {
        switch validation.dataType {
        case "skeleton_timeline":
            return "Review Timeline"
        case "knowledge_card":
            return "Review Knowledge Card"
        case "applicant_profile":
            return "Review Profile"
        default:
            return "Review Required"
        }
    }

    @ViewBuilder
    private var validationContent: some View {
        if validation.dataType == "skeleton_timeline" {
            TimelineCardEditorView(
                timeline: validation.payload,
                coordinator: coordinator,
                mode: .validation,
                onValidationSubmit: { status in
                    Task {
                        await coordinator.submitValidationAndResume(
                            status: status,
                            updatedData: nil,
                            changes: nil,
                            notes: nil
                        )
                    }
                },
                onSubmitChangesOnly: {
                    Task {
                        await coordinator.clearValidationPromptAndNotifyLLM(
                            message: "User made changes to the timeline cards and submitted them for review. Please reassess the updated timeline, ask any clarifying questions if needed, or submit for validation again when ready."
                        )
                    }
                }
            )
            .padding(16)
        } else if validation.dataType == "knowledge_card" {
            KnowledgeCardValidationSheetContent(
                prompt: validation,
                artifactsJSON: coordinator.ui.artifactRecords,
                coordinator: coordinator
            )
            .padding(16)
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
                    Task {
                        await coordinator.submitValidationAndResume(
                            status: "rejected",
                            updatedData: nil,
                            changes: nil,
                            notes: "User cancelled"
                        )
                    }
                }
            )
            .padding(16)
        }
    }
}

private struct KnowledgeCardValidationSheetContent: View {
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
