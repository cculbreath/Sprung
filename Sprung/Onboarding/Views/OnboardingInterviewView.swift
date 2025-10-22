import AppKit
import SwiftUI

struct OnboardingInterviewView: View {
    @Environment(OnboardingInterviewService.self) private var interviewService
    @Environment(EnabledLLMStore.self) private var enabledLLMStore
    @Environment(AppEnvironment.self) private var appEnvironment

    @State private var viewModel = OnboardingInterviewViewModel(
        fallbackModelId: "openai/gpt-5"
    )

    @AppStorage("onboardingInterviewDefaultModelId") private var defaultModelId = "openai/gpt-5"
    @AppStorage("onboardingInterviewAllowWebSearchDefault") private var defaultWebSearchAllowed = true
    @AppStorage("onboardingInterviewAllowWritingAnalysisDefault") private var defaultWritingAnalysisAllowed = true

    var body: some View {
        @Bindable var service = interviewService
        @Bindable var uiState = viewModel
        let actions = OnboardingInterviewActionHandler(service: service)

        return
            Group{
                VStack(spacing: 20) {
                    Spacer(minLength: 28)

                    OnboardingInterviewStepProgressView(service: service)
                        .padding(.horizontal, 32)

                    mainCard(service: service, state: uiState, actions: actions)

                    OnboardingInterviewBottomBar(
                        showBack: shouldShowBackButton(for: service.wizardStep),
                        continueTitle: continueButtonTitle(for: service.wizardStep),
                        isContinueDisabled: isContinueDisabled(service: service),
                        onShowSettings: openSettings,
                        onBack: { handleBack(service: service, actions: actions) },
                        onCancel: { handleCancel(actions: actions) },
                        onContinue: { handleContinue(service: service, actions: actions) }
                    )
                    .padding(.horizontal, 32)
                    .padding(.bottom)
                }
            }

            .frame(minWidth: 1040)
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
            .background(
                .thickMaterial,
                in: RoundedRectangle(cornerRadius: 44, style: .continuous)
            )
            .compositingGroup()
            .shadow(color: Color.black.opacity(0.5), radius: 30, y: 22)
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
    }
}

// MARK: - Layout

private extension OnboardingInterviewView {
    func mainCard(
        service: OnboardingInterviewService,
        state: OnboardingInterviewViewModel,
        actions: OnboardingInterviewActionHandler
    ) -> some View {
        Group {
            if service.wizardStep == .introduction {
                OnboardingInterviewIntroductionCard()
            } else {
                OnboardingInterviewInteractiveCard(
                    service: service,
                    state: state,
                    actions: actions,
                    modelStatusDescription: modelStatusDescription(service: service),
                    onOpenSettings: openSettings
                )
            }
        }

        .padding(.horizontal, 40)
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

    func isContinueDisabled(service: OnboardingInterviewService) -> Bool {
        switch service.wizardStep {
        case .introduction:
            return openAIModels.isEmpty || appEnvironment.appState.openAiApiKey.isEmpty
        case .resumeIntake:
            return service.isProcessing ||
                service.pendingChoicePrompt != nil ||
                service.pendingApplicantProfileRequest != nil ||
                service.pendingContactsRequest != nil
        case .artifactDiscovery:
            return service.isProcessing ||
                service.pendingSectionToggleRequest != nil ||
                !service.pendingSectionEntryRequests.isEmpty
        default:
            return service.isProcessing
        }
    }

    func handleContinue(
        service: OnboardingInterviewService,
        actions: OnboardingInterviewActionHandler
    ) {
        switch service.wizardStep {
        case .introduction:
            beginInterview(actions: actions)
        case .resumeIntake:
            if service.isActive,
               service.pendingChoicePrompt == nil,
               service.pendingApplicantProfileRequest == nil,
               service.pendingContactsRequest == nil {
                service.setPhase(.artifactDiscovery)
            }
        case .artifactDiscovery:
            service.setPhase(.writingCorpus)
        case .writingCorpus:
            service.setPhase(.wrapUp)
        case .wrapUp:
            handleCancel(actions: actions)
        }
    }

    func handleBack(
        service: OnboardingInterviewService,
        actions: OnboardingInterviewActionHandler
    ) {
        switch service.wizardStep {
        case .resumeIntake:
            actions.resetInterview()
            reinitializeUIState(service: service)
        case .artifactDiscovery:
            service.setPhase(.resumeIntake)
        case .writingCorpus:
            service.setPhase(.artifactDiscovery)
        case .wrapUp:
            service.setPhase(.writingCorpus)
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

    func beginInterview(actions: OnboardingInterviewActionHandler) {
        let modelId = viewModel.currentModelId
        Task {
            await actions.startInterview(modelId: modelId, backend: .openAI)
            if viewModel.writingAnalysisAllowed {
                actions.setWritingAnalysisConsent(true)
            }
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
