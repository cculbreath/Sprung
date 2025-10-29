import AppKit
import SwiftUI

struct OnboardingInterviewView: View {
    @Environment(OnboardingInterviewService.self) private var interviewService
    @Environment(OnboardingInterviewCoordinator.self) private var interviewCoordinator
    @Environment(OnboardingToolRouter.self) private var toolRouter
    @Environment(EnabledLLMStore.self) private var enabledLLMStore
    @Environment(AppEnvironment.self) private var appEnvironment

    @State private var viewModel = OnboardingInterviewViewModel(
        fallbackModelId: "openai/gpt-5"
    )

    @State private var showResumeOptions = false
    @State private var pendingStartModelId: String?
    @State private var loggedToolStatuses: [String: String] = [:]

    @AppStorage("onboardingInterviewDefaultModelId") private var defaultModelId = "openai/gpt-5"
    @AppStorage("onboardingInterviewAllowWebSearchDefault") private var defaultWebSearchAllowed = true
    @AppStorage("onboardingInterviewAllowWritingAnalysisDefault") private var defaultWritingAnalysisAllowed = true

    @Namespace private var wizardTransition

    var body: some View {
        @Bindable var service = interviewService
        @Bindable var coordinator = interviewCoordinator
        @Bindable var router = toolRouter
        @Bindable var uiState = viewModel
        let actions = OnboardingInterviewActionHandler(service: service, coordinator: coordinator)

        // --- Card visual constants ---
        let corner: CGFloat = 44
        let shadowR: CGFloat = 30
        let shadowY: CGFloat = 22
        let cardShape = RoundedRectangle(cornerRadius: corner, style: .continuous)

        VStack(spacing: 0) {
            // Progress bar anchored close to top
            OnboardingInterviewStepProgressView(coordinator: coordinator)
                .padding(.top, 16)
                .padding(.bottom, 24)
                .padding(.horizontal, 32)

            // Main body centered within available space
            VStack(spacing: 8) {
                mainCard(
                    service: service,
                    coordinator: coordinator,
                    router: router,
                    state: uiState,
                    actions: actions
                )
                .animation(.spring(response: 0.4, dampingFraction: 0.82), value: coordinator.wizardStep)

                Spacer(minLength: 16) // centers body relative to bottom bar

                OnboardingInterviewBottomBar(
                    showBack: shouldShowBackButton(for: coordinator.wizardStep),
                    continueTitle: continueButtonTitle(for: coordinator.wizardStep),
                    isContinueDisabled: isContinueDisabled(service: service, coordinator: coordinator),
                    onShowSettings: openSettings,
                    onBack: { handleBack(service: service, coordinator: coordinator, actions: actions) },
                    onCancel: { handleCancel(actions: actions) },
                    onContinue: { handleContinue(service: service, coordinator: coordinator, actions: actions) }
                )
                .padding(.horizontal, 16)
                .animation(.easeInOut(duration: 0.25), value: coordinator.wizardStep)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal,32)
        }
        .frame(minWidth: 1040)
        .padding(.horizontal, 32)
        .padding(.vertical, 24)
        .mask(cardShape) // clip content to rounded shape
        .background(
            cardShape.fill(.thickMaterial)
        )
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
                            respondToResumeChoice(resume: true, actions: actions)
                        },
                        onStartOver: {
                            respondToResumeChoice(resume: false, actions: actions)
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
        .task {
            uiState.configureIfNeeded(
                service: service,
                defaultModelId: defaultModelId,
                defaultWebSearchAllowed: defaultWebSearchAllowed,
                defaultWritingAnalysisAllowed: defaultWritingAnalysisAllowed,
                availableModelIds: openAIModels.map(\.modelId)
            )
            updateServiceDefaults()
        }
        .onChange(of: defaultModelId) { _, newValue in
            uiState.handleDefaultModelChange(
                newValue: newValue,
                availableModelIds: openAIModels.map(\.modelId)
            )
            updateServiceDefaults()
        }
        .onChange(of: defaultWebSearchAllowed) { _, newValue in
            if !service.isActive {
                uiState.webSearchAllowed = newValue
                updateServiceDefaults()
            }
        }
        .onChange(of: defaultWritingAnalysisAllowed) { _, newValue in
            if !service.isActive {
                uiState.writingAnalysisAllowed = newValue
            }
        }
        .onChange(of: service.allowWebSearch) { _, newValue in
            if service.isActive {
                uiState.webSearchAllowed = newValue
            }
        }
        .onChange(of: service.allowWritingAnalysis) { _, newValue in
            if service.isActive {
                uiState.writingAnalysisAllowed = newValue
            }
        }
        .sheet(isPresented: Binding(
            get: { service.pendingExtraction != nil },
            set: { newValue in
                if !newValue {
                    actions.cancelPendingExtraction()
                }
            }
        )) {
            if let pending = service.pendingExtraction {
                ExtractionReviewSheet(
                    extraction: pending,
                    onConfirm: { updated, notes in
                        Task { await actions.confirmPendingExtraction(updated, notes: notes) }
                    },
                    onCancel: {
                        actions.cancelPendingExtraction()
                    }
                )
            }
        }
        .alert("Import Failed", isPresented: $uiState.showImportError, presenting: uiState.importErrorText) { _ in
            Button("OK") { uiState.clearImportError() }
        } message: { message in
            Text(message)
        }
        .onAppear {
            let initialStatuses = router.statusSnapshot.rawValueMap
            loggedToolStatuses = initialStatuses
            Logger.info("📊 Tool status update", category: .ai, metadata: initialStatuses)
        }
        .onChange(of: router.statusSnapshot.rawValueMap) { _, newValue in
            guard newValue != loggedToolStatuses else { return }
            Logger.info("📊 Tool status update", category: .ai, metadata: newValue)
            loggedToolStatuses = newValue
        }
    }
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
        service: OnboardingInterviewService,
        coordinator: OnboardingInterviewCoordinator,
        router: OnboardingToolRouter,
        state: OnboardingInterviewViewModel,
        actions: OnboardingInterviewActionHandler
    ) -> some View {
        Group {
            if coordinator.wizardStep == .introduction {
                OnboardingInterviewIntroductionCard()
                    .matchedGeometryEffect(id: "mainCard", in: wizardTransition)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.95).combined(with: .opacity),
                        removal: .scale(scale: 1.05).combined(with: .opacity)
                    ))
            } else {
                OnboardingInterviewInteractiveCard(
                    service: service,
                    coordinator: coordinator,
                    router: router,
                    state: state,
                    actions: actions,
                    modelStatusDescription: modelStatusDescription(service: service),
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
        service: OnboardingInterviewService,
        coordinator: OnboardingInterviewCoordinator
    ) -> Bool {
        switch coordinator.wizardStep {
            case .introduction:
                return openAIModels.isEmpty || appEnvironment.appState.openAiApiKey.isEmpty
            case .resumeIntake:
                return service.isProcessing ||
                coordinator.pendingChoicePrompt != nil ||
                coordinator.pendingApplicantProfileRequest != nil ||
                coordinator.pendingApplicantProfileIntake != nil
            case .artifactDiscovery:
                return service.isProcessing ||
                coordinator.pendingSectionToggleRequest != nil
            default:
                return service.isProcessing
        }
    }

    func handleContinue(
        service: OnboardingInterviewService,
        coordinator: OnboardingInterviewCoordinator,
        actions: OnboardingInterviewActionHandler
    ) {
        switch coordinator.wizardStep {
            case .introduction:
                beginInterview(service: service, actions: actions)
            case .resumeIntake:
                if service.isActive,
                   coordinator.pendingChoicePrompt == nil,
                   coordinator.pendingApplicantProfileRequest == nil,
                   coordinator.pendingApplicantProfileIntake == nil {
                    coordinator.setWizardStep(.artifactDiscovery)
                }
            case .artifactDiscovery:
                coordinator.setWizardStep(.writingCorpus)
            case .writingCorpus:
                coordinator.setWizardStep(.wrapUp)
            case .wrapUp:
                handleCancel(actions: actions)
        }
    }

    func handleBack(
        service: OnboardingInterviewService,
        coordinator: OnboardingInterviewCoordinator,
        actions: OnboardingInterviewActionHandler
    ) {
        switch coordinator.wizardStep {
            case .resumeIntake:
                actions.resetInterview()
                reinitializeUIState(service: service)
            case .artifactDiscovery:
                coordinator.setWizardStep(.resumeIntake)
            case .writingCorpus:
                coordinator.setWizardStep(.artifactDiscovery)
            case .wrapUp:
                coordinator.setWizardStep(.writingCorpus)
            case .introduction:
                break
        }
    }

    func handleCancel(actions: OnboardingInterviewActionHandler) {
        actions.resetInterview()
        reinitializeUIState(service: interviewService)
        if let window = NSApp.windows.first(where: { $0 is BorderlessOverlayWindow }) {
            window.orderOut(nil)
        }
    }
}

// MARK: - Helpers

private extension OnboardingInterviewView {
    func updateServiceDefaults() {
        interviewService.setPreferredDefaults(
            modelId: viewModel.currentModelId,
            backend: .openAI,
            webSearchAllowed: viewModel.webSearchAllowed
        )
    }

    func openSettings() {
        NSApp.sendAction(#selector(AppDelegate.showSettingsWindow), to: nil, from: nil)
    }

    func modelStatusDescription(service: OnboardingInterviewService) -> String {
        let rawId = service.preferredModelIdForDisplay ?? viewModel.currentModelId
        let display = rawId.split(separator: "/").last.map(String.init) ?? rawId
        let webText = service.allowWebSearch ? "on" : "off"
        return "Using \(display) with web search \(webText)."
    }

    func beginInterview(
        service: OnboardingInterviewService,
        actions: OnboardingInterviewActionHandler
    ) {
        let modelId = viewModel.currentModelId
        Task { @MainActor in
            guard service.isActive == false else { return }
            let hasCheckpoint = await service.hasRestorableCheckpoint()
            if hasCheckpoint {
                pendingStartModelId = modelId
                showResumeOptions = true
            } else {
                await launchInterview(modelId: modelId, resume: false, actions: actions)
            }
        }
    }

    @MainActor
    func launchInterview(
        modelId: String,
        resume: Bool,
        actions: OnboardingInterviewActionHandler
    ) async {
        await actions.startInterview(modelId: modelId, backend: .openAI, resumeExisting: resume)
        if viewModel.writingAnalysisAllowed {
            actions.setWritingAnalysisConsent(true)
        }
        pendingStartModelId = nil
        showResumeOptions = false
    }

    func respondToResumeChoice(
        resume: Bool,
        actions: OnboardingInterviewActionHandler
    ) {
        guard let modelId = pendingStartModelId else { return }
        pendingStartModelId = nil
        showResumeOptions = false

        Task { @MainActor in
            await launchInterview(modelId: modelId, resume: resume, actions: actions)
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

    func reinitializeUIState(service: OnboardingInterviewService) {
        viewModel.configureIfNeeded(
            service: service,
            defaultModelId: defaultModelId,
            defaultWebSearchAllowed: defaultWebSearchAllowed,
            defaultWritingAnalysisAllowed: defaultWritingAnalysisAllowed,
            availableModelIds: openAIModels.map(\.modelId)
        )
        updateServiceDefaults()
    }
}
