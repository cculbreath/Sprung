import AppKit
import SwiftUI
struct OnboardingInterviewView: View {
    @Environment(OnboardingInterviewCoordinator.self) private var interviewCoordinator
    @Environment(EnabledLLMStore.self) private var enabledLLMStore
    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(DebugSettingsStore.self) private var debugSettings
    private let onboardingFallbackModelId = "openai/gpt-5.1"
    @State private var viewModel = OnboardingInterviewViewModel(
        fallbackModelId: "openai/gpt-5.1"
    )
    @State private var showResumeOptions = false
    @State private var pendingStartModelId: String?
    #if DEBUG
    @State private var showEventDump = false
    #endif
    @AppStorage("onboardingInterviewDefaultModelId") private var defaultModelId = "openai/gpt-5.1"
    @AppStorage("onboardingInterviewAllowWebSearchDefault") private var defaultWebSearchAllowed = true
    @AppStorage("onboardingInterviewAllowWritingAnalysisDefault") private var defaultWritingAnalysisAllowed = true
    @Namespace private var wizardTransition
    var body: some View {
        bodyContent
    }
    private var bodyContent: some View {
        @Bindable var coordinator = interviewCoordinator
        @Bindable var uiState = viewModel
        // --- Card visual constants ---
        let corner: CGFloat = 44
        let shadowR: CGFloat = 30
        let shadowY: CGFloat = 22
        let cardShape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        let contentStack = VStack(spacing: 0) {
            // Progress bar anchored close to top
            OnboardingInterviewStepProgressView(coordinator: coordinator)
                .padding(.top, 16)
                .padding(.bottom, 24)
                .padding(.horizontal, 32)
            // Main body centered within available space
            VStack(spacing: 8) {
                mainCard(
                    coordinator: coordinator,
                    state: uiState
                )
                .animation(.spring(response: 0.4, dampingFraction: 0.82), value: coordinator.wizardTracker.currentStep)
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
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal,32)
        }
        let styledContent = contentStack
            .frame(minWidth: 1040)
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
            .mask(cardShape)
            .background(cardShape.fill(.thickMaterial))
            .overlay(
                cardShape
                    .stroke(.clear)
                    .shadow(color: .black.opacity(0.5), radius: shadowR, y: shadowY)
                    .allowsHitTesting(false)
            )
            .padding(.top, shadowR)
            .padding(.leading, shadowR)
            .padding(.trailing, shadowR)
            .padding(.bottom, shadowR + abs(shadowY))
        let withResumeOverlay = styledContent
            .overlay {
                if showResumeOptions {
                    ZStack {
                        Color.black.opacity(0.001)
                            .ignoresSafeArea()
                            .contentShape(Rectangle())
                            .onTapGesture {
                                pendingStartModelId = nil
                                showResumeOptions = false
                            }
                        ResumeInterviewPromptView(
                            onResume: {
                                respondToResumeChoice(resume: true)
                            },
                            onStartOver: {
                                respondToResumeChoice(resume: false)
                            },
                            onCancel: {
                                pendingStartModelId = nil
                                showResumeOptions = false
                            }
                        )
                        .transition(.opacity.combined(with: .scale))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .zIndex(5)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: showResumeOptions)
        // --- Lifecycle bindings and tasks ---
        let withLifecycle = withResumeOverlay
            .task {
                let modelIds = openAIModels.map(\.modelId)
                uiState.configureIfNeeded(
                    coordinator: interviewCoordinator,
                    defaultModelId: defaultModelId,
                    defaultWebSearchAllowed: defaultWebSearchAllowed,
                    defaultWritingAnalysisAllowed: defaultWritingAnalysisAllowed,
                    availableModelIds: modelIds
                )
                applyPreferredModel()
            }
            .onChange(of: defaultModelId) { _, newValue in
                let modelIds = openAIModels.map(\.modelId)
                uiState.handleDefaultModelChange(
                    newValue: newValue,
                    availableModelIds: modelIds
                )
                applyPreferredModel(requestedId: newValue)
            }
            .onChange(of: defaultWebSearchAllowed) { _, newValue in
                if !coordinator.ui.isActive {
                    uiState.webSearchAllowed = newValue
                    applyPreferredModel()
                }
            }
            .onChange(of: defaultWritingAnalysisAllowed) { _, newValue in
                if !coordinator.ui.isActive {
                    uiState.writingAnalysisAllowed = newValue
                }
            }
            .onChange(of: coordinator.ui.preferences.allowWebSearch) { _, newValue in
                if coordinator.ui.isActive {
                    uiState.webSearchAllowed = newValue
                }
            }
            .onChange(of: coordinator.ui.preferences.allowWritingAnalysis) { _, newValue in
                if coordinator.ui.isActive {
                    uiState.writingAnalysisAllowed = newValue
                }
            }
            .onChange(of: enabledLLMStore.enabledModels) { _, _ in
                applyPreferredModel()
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
                        onConfirm: { updated, notes in
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
            .alert("Import Failed", isPresented: $uiState.showImportError, presenting: uiState.importErrorText) { _ in
                Button("OK") { uiState.clearImportError() }
            } message: { message in
                Text(message)
            }
        return withSheets
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
        Button {
            showEventDump.toggle()
        } label: {
            Image(systemName: "ladybug.fill")
                .font(.title2)
                .foregroundStyle(.white)
                .padding(12)
                .background(.purple.gradient, in: Circle())
                .shadow(radius: 4)
        }
        .buttonStyle(.plain)
        .padding(24)
    }
    #endif
}
private struct ResumeInterviewPromptView: View {
    let onResume: () -> Void
    let onStartOver: () -> Void
    let onCancel: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 16) {
                Image("custom.onboardinginterview")
                    .resizable()
                    .renderingMode(.template)
                    .foregroundStyle(.secondary)
                    .scaledToFit()
                    .frame(width: 42, height: 42)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Resume previous interview?")
                        .font(.headline)
                    Text("We found an in-progress onboarding interview. Would you like to continue where you left off or start fresh?")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 14) {
                Button("Start over", role: .destructive) {
                    onStartOver()
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .controlSize(.large)
                Spacer()
                HStack(spacing: 12) {
                    Button("Cancel") {
                        onCancel()
                    }
                    .buttonStyle(.bordered)
                    Button("Resume") {
                        onResume()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 28)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(0.18), radius: 24, y: 12)
        )
                .frame(width: 420)
    }
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
                .frame(width: 900)
                .matchedGeometryEffect(id: "mainCard", in: wizardTransition)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.95).combined(with: .opacity),
                    removal: .scale(scale: 1.05).combined(with: .opacity)
                ))
            }
        }
        .padding(.horizontal, 40)
        .padding(.top, 30)
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
                return openAIModels.isEmpty || appEnvironment.appState.openAiApiKey.isEmpty
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
        switch coordinator.wizardTracker.currentStep {
            case .resumeIntake:
                // Wizard steps are now derived from objectives - no manual reset needed
                reinitializeUIState()
            case .artifactDiscovery:
                // Wizard steps are now derived from objectives - no manual setting needed
                break
            case .writingCorpus:
                // Wizard steps are now derived from objectives - no manual setting needed
                break
            case .wrapUp:
                // Wizard steps are now derived from objectives - no manual setting needed
                break
            case .introduction:
                break
        }
    }
    func handleCancel() {
        Task {
            await interviewCoordinator.endInterview()
        }
        reinitializeUIState()
        if let window = NSApp.windows.first(where: { $0 is BorderlessOverlayWindow }) {
            window.orderOut(nil)
        }
    }
}
// MARK: - Helpers
private extension OnboardingInterviewView {
    func updateServiceDefaults() {
        applyPreferredModel()
    }
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
        let modelId = viewModel.currentModelId
        Task { @MainActor in
            guard interviewCoordinator.ui.isActive == false else { return }
            // Check if there's an existing checkpoint to resume
            if interviewCoordinator.checkpoints.hasCheckpoint() {
                Logger.info("✅ Found existing checkpoint - showing resume dialog", category: .ai)
                // Show resume dialog
                pendingStartModelId = modelId
                showResumeOptions = true
            } else {
                Logger.info("📝 No checkpoint found - starting fresh interview", category: .ai)
                // No checkpoint, start fresh
                await launchInterview(modelId: modelId, resume: false)
            }
        }
    }
    @MainActor
    func launchInterview(modelId: String, resume: Bool) async {
        _ = await interviewCoordinator.startInterview(resumeExisting: resume)
        // Note: modelId and backend are now configured via OpenAIService in AppDependencies
        // Writing analysis consent is part of OnboardingPreferences
        pendingStartModelId = nil
        showResumeOptions = false
    }
    func respondToResumeChoice(resume: Bool) {
        guard let modelId = pendingStartModelId else { return }
        Logger.info("📝 User chose to \(resume ? "resume" : "start fresh") interview", category: .ai)
        pendingStartModelId = nil
        showResumeOptions = false
        Task { @MainActor in
            await launchInterview(modelId: modelId, resume: resume)
        }
    }
    var openAIModels: [EnabledLLM] {
        enabledLLMStore.enabledModels
            .filter { $0.modelId.lowercased().hasPrefix("openai/") }
            .sorted { lhs, rhs in
                (lhs.displayName.isEmpty ? lhs.modelId : lhs.displayName)
                < (rhs.displayName.isEmpty ? rhs.modelId : rhs.displayName)
            }
    }
    func reinitializeUIState() {
        viewModel.configureIfNeeded(
            coordinator: interviewCoordinator,
            defaultModelId: defaultModelId,
            defaultWebSearchAllowed: defaultWebSearchAllowed,
            defaultWritingAnalysisAllowed: defaultWritingAnalysisAllowed,
            availableModelIds: openAIModels.map(\.modelId)
        )
        applyPreferredModel()
    }
    func applyPreferredModel(requestedId: String? = nil) {
        // Note: Model configuration is handled via OpenAIService and ModelProvider
        //
        // let resolvedId = interviewService.setPreferredDefaults(
        //     modelId: targetId,
        //     backend: .openAI,
        //     webSearchAllowed: viewModel.webSearchAllowed
        // )
        //
        // if viewModel.selectedModelId != resolvedId {
        //     viewModel.selectedModelId = resolvedId
        // }
        //
        // if defaultModelId != resolvedId {
        //     defaultModelId = resolvedId
        // }
    }
}
