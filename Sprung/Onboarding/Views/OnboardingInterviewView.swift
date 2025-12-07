import AppKit
import SwiftUI
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
            .padding(.horizontal, 32)
        }
        // Uses system window shadow via BorderlessOverlayWindow.hasShadow = true
        // No SwiftUI shadow overlay needed - system shadow has proper hit testing
        let styledContent = contentStack
            .frame(minWidth: 1040)
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
            .clipShape(cardShape)
            .background(cardShape.fill(.thickMaterial))
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
            .alert("Resume Previous Session?", isPresented: $showResumePrompt) {
                Button("Resume") {
                    resumeInterview()
                }
                Button("Start Over", role: .destructive) {
                    startOverInterview()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("You have an unfinished onboarding session. Would you like to resume where you left off, or start over with a fresh session?")
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

            // Check for existing session
            if interviewCoordinator.hasActiveSession() {
                Logger.info("📝 Found existing session, showing resume prompt", category: .ai)
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
            Logger.info("📝 Starting over - resetting all data", category: .ai)
            #if DEBUG
            await interviewCoordinator.resetAllOnboardingData()
            #else
            interviewCoordinator.deleteCurrentSession()
            #endif
            _ = await interviewCoordinator.startInterview(resumeExisting: false)
        }
    }
}
