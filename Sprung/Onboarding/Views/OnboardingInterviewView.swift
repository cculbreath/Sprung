import AppKit
import SwiftUI
import UniformTypeIdentifiers
import SwiftyJSON

struct OnboardingInterviewView: View {
    @Environment(OnboardingInterviewService.self) private var interviewService
    @Environment(EnabledLLMStore.self) private var enabledLLMStore
    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(ApplicantProfileStore.self) private var applicantProfileStore
    @Environment(ExperienceDefaultsStore.self) private var experienceDefaultsStore

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

        return ZStack {
            OnboardingInterviewBackgroundView()

            VStack(spacing: 20) {
                Spacer(minLength: 28)

                stepProgressView(service: service)
                    .padding(.horizontal, 32)

                mainCard(service: service, actions: actions)

                bottomBar(service: service, actions: actions)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 0)
            }
        }
        .frame(minWidth: 1040, minHeight: 700)
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
    func mainCard(service: OnboardingInterviewService, actions: OnboardingInterviewActionHandler) -> some View {
        Group {
            if service.wizardStep == .introduction {
                introductionCard
            } else {
                interactiveCard(service: service, actions: actions)
            }
        }
        .frame(maxWidth: 880, maxHeight: 620, alignment: .center)
        .padding(.horizontal, 32)
        .padding(.vertical, 24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 44, style: .continuous))
        .shadow(color: Color.black.opacity(0.12), radius: 30, y: 22)
        .padding(.horizontal, 40)
    }

    var introductionCard: some View {
        VStack(spacing: 28) {
            Image("custom.onboardinginterview")
                .resizable()
                .renderingMode(.template)
                .foregroundColor(.accentColor)
                .scaledToFit()
                .frame(width: 160, height: 160)

            VStack(spacing: 8) {
                Text("Welcome to Sprung Onboarding")
                    .font(.system(size: 34, weight: .bold, design: .default))
                    .multilineTextAlignment(.center)
                Text("We’ll confirm your contact details, enable the right résumé sections, and collect highlights so Sprung can advocate for you.")
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            onboardingHighlights()
                .frame(maxWidth: 520)
        }
        .frame(maxWidth: .infinity)
    }

    func onboardingHighlights() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Part 1 Goals")
                .font(.headline)
                .foregroundStyle(.primary)
            VStack(alignment: .leading, spacing: 12) {
                highlightRow(systemImage: "person.text.rectangle", text: "Confirm contact info from a résumé, LinkedIn, macOS Contacts, or manual entry.")
                highlightRow(systemImage: "list.number", text: "Choose the JSON Resume sections that describe your experience.")
                highlightRow(systemImage: "tray.full", text: "Review every section entry before it’s saved to your profile.")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func highlightRow(systemImage: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
            Text(text)
                .font(.body)
        }
    }

    func interactiveCard(service: OnboardingInterviewService, actions: OnboardingInterviewActionHandler) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            stepLayout(service: service, actions: actions)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    func stepProgressView(service: OnboardingInterviewService) -> some View {
        HStack(alignment: .center, spacing: 32) {
            ForEach(OnboardingWizardStep.allCases) { step in
                let status = service.wizardStepStatuses[step] ?? .pending
                HStack(spacing: 8) {
                    Image(systemName: progressIcon(for: status))
                        .foregroundStyle(progressColor(for: status))
                        .font(.title3)
                    Text(step.title)
                        .font(status == .current ? .headline : .subheadline)
                        .foregroundStyle(status == .pending ? Color.secondary : Color.primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    func progressIcon(for status: OnboardingWizardStepStatus) -> String {
        switch status {
        case .pending: return "circle"
        case .current: return "circle.inset.filled"
        case .completed: return "checkmark.circle.fill"
        }
    }

    func progressColor(for status: OnboardingWizardStepStatus) -> Color {
        switch status {
        case .pending: return Color.secondary
        case .current: return Color.accentColor
        case .completed: return Color.green
        }
    }

    func stepLayout(service: OnboardingInterviewService, actions: OnboardingInterviewActionHandler) -> some View {
        HStack(spacing: 0) {
            toolInteractionPane(service: service, actions: actions)
                .frame(minWidth: 340, maxWidth: 420)
                .frame(maxHeight: .infinity, alignment: .topLeading)
            Divider()
            chatPanel(service: service, state: viewModel, actions: actions)
        }
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        )
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func toolInteractionPane(service: OnboardingInterviewService, actions: OnboardingInterviewActionHandler) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let badge = statusBadgeText(service: service) {
                badge
            }

            let requests = uploadRequests(for: service.wizardStep, service: service)
            if let contactsRequest = service.pendingContactsRequest {
                ContactsPermissionCard(
                    request: contactsRequest,
                    onAllow: {
                        Task { await actions.fetchApplicantProfileFromContacts() }
                    },
                    onDecline: {
                        Task { await actions.declineContactsFetch(reason: "User declined contacts access") }
                    }
                )
            } else if let prompt = service.pendingChoicePrompt {
                InterviewChoicePromptCard(
                    prompt: prompt,
                    onSubmit: { selection in
                        Task { await actions.resolveChoice(selectionIds: selection) }
                    },
                    onCancel: {
                        Task { await actions.cancelChoicePrompt(reason: "User dismissed choice prompt") }
                    }
                )
            } else if let profileRequest = service.pendingApplicantProfileRequest {
                ApplicantProfileReviewCard(
                    request: profileRequest,
                    fallbackDraft: ApplicantProfileDraft(profile: applicantProfileStore.currentProfile()),
                    onConfirm: { draft in
                        Task { await actions.approveApplicantProfile(draft: draft) }
                    },
                    onCancel: {
                        Task { await actions.declineApplicantProfile(reason: "User cancelled applicant profile validation") }
                    }
                )
            } else if let sectionToggle = service.pendingSectionToggleRequest {
                ResumeSectionsToggleCard(
                    request: sectionToggle,
                    existingDraft: experienceDefaultsStore.loadDraft(),
                    onConfirm: { enabled in
                        Task { await actions.completeSectionToggleSelection(enabled: enabled) }
                    },
                    onCancel: {
                        Task { await actions.cancelSectionToggleSelection(reason: "User cancelled section toggle") }
                    }
                )
            } else if let entryRequest = service.pendingSectionEntryRequests.first {
                ResumeSectionEntriesCard(
                    request: entryRequest,
                    existingDraft: experienceDefaultsStore.loadDraft(),
                    onConfirm: { approved in
                        Task { await actions.completeSectionEntryRequest(id: entryRequest.id, approvedEntries: approved) }
                    },
                    onCancel: {
                        Task { await actions.declineSectionEntryRequest(id: entryRequest.id, reason: "User cancelled section validation") }
                    }
                )
            } else if !requests.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(requests) { request in
                            UploadRequestCard(
                                request: request,
                                onSelectFile: { openPanel(for: request, actions: actions) },
                                onProvideLink: { url in
                                    Task { await actions.completeUploadRequest(id: request.id, link: url) }
                                },
                                onDecline: {
                                    Task { await actions.declineUploadRequest(id: request.id) }
                                }
                            )
                        }
                    }
                }
            } else {
                Spacer()
            }
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    func statusBadgeText(service: OnboardingInterviewService) -> Text? {
        switch service.wizardStep {
        case .resumeIntake:
            let text = badgeText(service: service, introCompleted: service.completedWizardSteps.contains(.resumeIntake))
            return text.isEmpty ? nil : Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .artifactDiscovery:
            let text = badgeText(service: service, introCompleted: true)
            return text.isEmpty ? nil : Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .writingCorpus, .wrapUp, .introduction:
            return nil
        }
    }

    private func badgeText(service: OnboardingInterviewService, introCompleted: Bool) -> String {
        if !service.pendingUploadRequests.isEmpty {
            return "Upload the requested files"
        }
        if service.pendingContactsRequest != nil {
            return "Allow access to macOS Contacts"
        }
        if let choicePrompt = service.pendingChoicePrompt {
            return "Action required: " + (choicePrompt.prompt.isEmpty ? "please choose an option" : choicePrompt.prompt)
        }
        if service.pendingApplicantProfileRequest != nil {
            return "Action required: review applicant profile"
        }
        if service.pendingSectionToggleRequest != nil {
            return "Confirm applicable résumé sections"
        }
        if service.pendingSectionEntryRequests.first != nil {
            return "Review section entries"
        }
        if service.pendingUploadRequests.isEmpty && introCompleted == false {
            return ""
        }
        return ""
    }

    func detailHeadline(for step: OnboardingWizardStep) -> String {
        switch step {
        case .introduction:
            return "Overview"
        case .resumeIntake:
            return "Applicant Profile"
        case .artifactDiscovery:
            return "Artifact Discovery"
        case .writingCorpus:
            return "Writing Corpus"
        case .wrapUp:
            return "Review & Finish"
        }
    }

    func detailSubtitle(for step: OnboardingWizardStep) -> String {
        switch step {
        case .introduction:
            return "Preview what the interview covers before you begin."
        case .resumeIntake:
            return "Confirm your contact details before we explore the rest of your experience."
        case .artifactDiscovery:
            return "Validate résumé sections and review each entry that will appear in your profile."
        case .writingCorpus:
            return "Provide writing samples so Sprung can mirror your tone."
        case .wrapUp:
            return "Review what we captured and note any follow-up items."
        }
    }

    func bottomBar(service: OnboardingInterviewService, actions: OnboardingInterviewActionHandler) -> some View {
        HStack(spacing: 12) {
            Button("Options…") {
                NSApp.sendAction(#selector(AppDelegate.showSettingsWindow), to: nil, from: nil)
            }
            .buttonStyle(.bordered)

            Spacer()

            if shouldShowBackButton(for: service.wizardStep) {
                Button("Go Back") {
                    handleBack(service: service, actions: actions)
                }
            }

            Button("Cancel") {
                handleCancel(actions: actions)
            }
            .buttonStyle(.bordered)

            Button(continueButtonTitle(for: service.wizardStep)) {
                handleContinue(service: service, actions: actions)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isContinueDisabled(service: service))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
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

    func handleContinue(service: OnboardingInterviewService, actions: OnboardingInterviewActionHandler) {
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

    func handleBack(service: OnboardingInterviewService, actions: OnboardingInterviewActionHandler) {
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

// MARK: - Chat

private extension OnboardingInterviewView {
    func chatPanel(service: OnboardingInterviewService, state: OnboardingInterviewViewModel, actions: OnboardingInterviewActionHandler) -> some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(service.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                    .padding(20)
                }
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: Color.black.opacity(0.18), radius: 20, y: 16)
                .onChange(of: service.messages.count) { _, _ in
                    if state.shouldAutoScroll, let lastId = service.messages.last?.id {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
                .onAppear {
                    if state.shouldAutoScroll, let lastId = service.messages.last?.id {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
            }

            if service.isProcessing &&
                service.pendingChoicePrompt == nil &&
                service.pendingApplicantProfileRequest == nil &&
                service.pendingSectionToggleRequest == nil &&
                service.pendingSectionEntryRequests.isEmpty &&
                service.pendingContactsRequest == nil {
                HStack(spacing: 12) {
                    LLMActivityView()
                        .frame(width: 36, height: 36)
                    Text("Assistant is thinking…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .transition(.opacity)
            }

            if !service.nextQuestions.isEmpty {
                Divider()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(service.nextQuestions) { question in
                            Button(action: { send(question.text, state: state, actions: actions) }) {
                                Text(question.text)
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 12)
                                    .background(Color.accentColor.opacity(0.15))
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }

            Divider()

            HStack(alignment: .center, spacing: 12) {
                TextField(
                    "Type your response…",
                    text: Binding(
                        get: { state.userInput },
                        set: { state.userInput = $0 }
                    ),
                    axis: .vertical
                )
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...5)
                .disabled(!service.isActive || service.isProcessing)
                .onSubmit { send(state.userInput, state: state, actions: actions) }

                Button {
                    send(state.userInput, state: state, actions: actions)
                } label: {
                    Label("Send", systemImage: "paperplane.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(state.userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !service.isActive || service.isProcessing)
            }
            .padding(.all, 16)

            HStack(spacing: 6) {
                Text(modelStatusDescription(service: service))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Change in Settings…") {
                    openSettings()
                }
                .buttonStyle(.link)
                .font(.caption)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 8)
        }
        .frame(minWidth: 640, maxWidth: .infinity, maxHeight: .infinity)
    }

    func send(_ text: String, state: OnboardingInterviewViewModel, actions: OnboardingInterviewActionHandler) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        state.userInput = ""
        Task { await actions.sendMessage(trimmed) }
    }
}

// MARK: - Requests & Uploads

private extension OnboardingInterviewView {
    func uploadRequests(for step: OnboardingWizardStep, service: OnboardingInterviewService) -> [OnboardingUploadRequest] {
        switch step {
        case .resumeIntake:
            return service.pendingUploadRequests.filter { [.resume, .linkedIn].contains($0.kind) }
        case .artifactDiscovery:
            return service.pendingUploadRequests.filter { [.artifact, .generic].contains($0.kind) }
        case .writingCorpus:
            return service.pendingUploadRequests.filter { $0.kind == .writingSample }
        case .wrapUp:
            return service.pendingUploadRequests
        case .introduction:
            return []
        }
    }

    func openPanel(for request: OnboardingUploadRequest, actions: OnboardingInterviewActionHandler) {
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
                urls = panel.urls.prefix(1).map { $0 }
            }
            for url in urls {
                Task { await actions.completeUploadRequest(id: request.id, fileURL: url) }
            }
        }
    }

    func allowedContentTypes(for request: OnboardingUploadRequest) -> [UTType]? {
        var candidates = request.metadata.accepts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        if candidates.isEmpty {
            switch request.kind {
            case .resume:
                candidates = ["pdf", "docx", "txt", "json"]
            case .artifact, .generic:
                candidates = ["pdf", "pptx", "docx", "txt", "json"]
            case .writingSample:
                candidates = ["pdf", "docx", "txt", "md"]
            case .linkedIn:
                return nil
            }
        }

        let mapped = candidates.compactMap { UTType(filenameExtension: $0) }
        return mapped.isEmpty ? nil : mapped
    }
}

// MARK: - Actions & Defaults

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

// MARK: - Supporting Views

private struct UploadRequestCard: View {
    let request: OnboardingUploadRequest
    let onSelectFile: () -> Void
    let onProvideLink: (URL) -> Void
    let onDecline: () -> Void

    @State private var linkText: String = ""
    @State private var linkError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(request.metadata.title)
                .font(.headline)

            Text(request.metadata.instructions)
                .font(.callout)

            if !request.metadata.accepts.isEmpty {
                Text("Accepted types: \(request.metadata.accepts.joined(separator: ", ").uppercased())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if request.kind == .linkedIn {
                Text("Paste a LinkedIn profile URL.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if request.metadata.allowMultiple {
                Text("Multiple files allowed.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if request.kind == .linkedIn {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("https://www.linkedin.com/in/…", text: $linkText)
                        .textFieldStyle(.roundedBorder)
                    if let error = linkError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    HStack {
                        Button("Submit Link") {
                            submitLink()
                        }
                        Button("Skip") {
                            onDecline()
                        }
                        .buttonStyle(.borderless)
                    }
                }
            } else {
                HStack(spacing: 12) {
                    Button("Choose File…") {
                        onSelectFile()
                    }
                    Button("Skip") {
                        onDecline()
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func submitLink() {
        let trimmed = linkText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), !trimmed.isEmpty else {
            linkError = "Please provide a valid LinkedIn URL."
            return
        }
        linkError = nil
        onProvideLink(url)
        linkText = ""
    }
}

private struct WrapUpSummaryView: View {
    let artifacts: OnboardingArtifacts
    let schemaIssues: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !schemaIssues.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Schema Alerts")
                        .font(.headline)
                        .foregroundStyle(.orange)
                    ForEach(schemaIssues, id: \.self) { issue in
                        Label(issue, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .font(.footnote)
                    }
                }
            }

            if let profile = artifacts.applicantProfile {
                ArtifactSection(title: "Applicant Profile", content: formattedJSON(profile))
            }

            if let defaults = artifacts.defaultValues {
                ArtifactSection(title: "Default Values", content: formattedJSON(defaults))
            }

            if !artifacts.knowledgeCards.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Knowledge Cards")
                        .font(.headline)
                    ForEach(Array(artifacts.knowledgeCards.enumerated()), id: \.offset) { index, card in
                        KnowledgeCardView(index: index + 1, card: card)
                            .padding(8)
                            .background(Color(nsColor: .textBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }

            if !artifacts.factLedger.isEmpty {
                FactLedgerListView(entries: artifacts.factLedger)
            }

            if let skillMap = artifacts.skillMap {
                ArtifactSection(title: "Skill Evidence Map", content: formattedJSON(skillMap))
            }

            if let styleProfile = artifacts.styleProfile {
                StyleProfileView(profile: styleProfile)
            }

            if !artifacts.writingSamples.isEmpty {
                WritingSamplesListView(samples: artifacts.writingSamples)
            }

            if let context = artifacts.profileContext, !context.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Profile Context")
                        .font(.headline)
                    Text(context)
                        .font(.callout)
                }
            }

            if !artifacts.needsVerification.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Needs Verification")
                        .font(.headline)
                    ForEach(artifacts.needsVerification, id: \.self) { item in
                        Label(item, systemImage: "questionmark.diamond")
                            .foregroundStyle(.orange)
                            .font(.caption)
                    }
                }
            }
        }
    }

    private func formattedJSON(_ json: JSON) -> String {
        json.rawString(options: .prettyPrinted) ?? json.rawString() ?? ""
    }
}

// MARK: - Legacy Supporting Views

private struct MessageBubble: View {
    let message: OnboardingMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer() }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(displayText)
                    .padding(12)
                    .background(backgroundColor)
                    .foregroundStyle(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 520, alignment: message.role == .user ? .trailing : .leading)

            if message.role != .user { Spacer() }
        }
        .transition(.opacity)
    }

    private var backgroundColor: Color {
        switch message.role {
        case .user:
            return Color.accentColor.opacity(0.2)
        case .assistant:
            return Color(nsColor: .controlBackgroundColor)
        case .system:
            return Color.gray.opacity(0.15)
        }
    }

    private var displayText: String {
        switch message.role {
        case .assistant:
            return parseAssistantReply(from: message.text)
        case .user, .system:
            return message.text
        }
    }

    private func parseAssistantReply(from text: String) -> String {
        if let data = text.data(using: .utf8),
           let json = try? JSON(data: data),
           let reply = json["assistant_reply"].string {
            return reply
        }
        if let range = text.range(of: "\"assistant_reply\":") {
            let substring = text[range.upperBound...]
            if let closingQuote = substring.firstIndex(of: "\"") {
                let trimmed = substring[closingQuote...].dropFirst()
                if let end = trimmed.firstIndex(of: "\"") {
                    return String(trimmed[..<end])
                }
            }
        }
        return text
    }
}

private struct ArtifactSection: View {
    let title: String
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            ScrollView {
                Text(content.isEmpty ? "—" : content)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 180)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

private struct KnowledgeCardView: View {
    let index: Int
    let card: JSON

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("#\(index) \(card["title"].stringValue)")
                .font(.headline)
            if let summary = card["summary"].string {
                Text(summary)
                    .font(.body)
            }
            if let source = card["source"].string, !source.isEmpty {
                Label(source, systemImage: "link")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            let metrics = card["metrics"].arrayValue.compactMap { $0.string }
            if !metrics.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Metrics")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    ForEach(metrics, id: \.self) { metric in
                        Text("• \(metric)")
                            .font(.caption)
                    }
                }
            }
            let skills = card["skills"].arrayValue.compactMap { $0.string }
            if !skills.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Skills")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(skills.joined(separator: ", "))
                        .font(.caption)
                }
            }
        }
    }
}

private struct FactLedgerListView: View {
    let entries: [JSON]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Fact Ledger")
                .font(.headline)
            ForEach(entries.indices, id: \.self) { index in
                let entry = entries[index]
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry["statement"].stringValue)
                        .font(.subheadline)
                    if let evidence = entry["evidence"].string {
                        Text(evidence)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }
}

private struct StyleProfileView: View {
    let profile: JSON

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Style Profile")
                .font(.headline)
            Text(formattedJSON(profile))
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func formattedJSON(_ json: JSON) -> String {
        json.rawString(options: .prettyPrinted) ?? json.rawString() ?? ""
    }
}

private struct WritingSamplesListView: View {
    let samples: [JSON]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Writing Samples")
                .font(.headline)
            ForEach(Array(samples.enumerated()), id: \.offset) { index, sample in
                VStack(alignment: .leading, spacing: 4) {
                    Text(sample["title"].string ?? sample["name"].string ?? "Sample #\(index + 1)")
                        .font(.subheadline)
                        .bold()
                    if let summary = sample["summary"].string {
                        Text(summary)
                            .font(.caption)
                    }
                    let tone = sample["tone"].string ?? "—"
                    let words = sample["word_count"].int ?? 0
                    let avg = sample["avg_sentence_len"].double ?? 0
                    let active = sample["active_voice_ratio"].double ?? 0
                    let quant = sample["quant_density_per_100w"].double ?? 0

                    Text("Tone: \(tone) • \(words) words • Avg sentence: \(String(format: "%.1f", avg)) words")
                        .font(.caption)
                    Text("Active voice: \(String(format: "%.0f%%", active * 100)) • Quant density: \(String(format: "%.2f", quant)) per 100 words")
                        .font(.caption)

                    let notable = sample["notable_phrases"].arrayValue.compactMap { $0.string }
                    if !notable.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Notable phrases")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            ForEach(notable.prefix(3), id: \.self) { phrase in
                                Text("• \(phrase)")
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }
}

private struct ExtractionReviewSheet: View {
    let extraction: OnboardingPendingExtraction
    let onConfirm: (JSON, String?) -> Void
    let onCancel: () -> Void

    @State private var jsonText: String
    @State private var notes: String = ""
    @State private var errorMessage: String?

    init(
        extraction: OnboardingPendingExtraction,
        onConfirm: @escaping (JSON, String?) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.extraction = extraction
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        self._jsonText = State(initialValue: extraction.rawExtraction.rawString(options: .prettyPrinted) ?? extraction.rawExtraction.description)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Review Résumé Extraction")
                .font(.title2)
                .bold()

            if !extraction.uncertainties.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Uncertain Fields")
                        .font(.headline)
                        .foregroundStyle(.orange)
                    ForEach(extraction.uncertainties, id: \.self) { item in
                        Label(item, systemImage: "questionmark.circle")
                            .foregroundStyle(.orange)
                    }
                }
            }

            Text("Raw Extraction (editable JSON)")
                .font(.headline)

            TextEditor(text: $jsonText)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 240)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.2))
                )

            TextField("Notes for the assistant (optional)", text: $notes)
                .textFieldStyle(.roundedBorder)

            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }

            HStack {
                Spacer()
                Button("Cancel") { onCancel() }
                Button("Confirm") {
                    guard let data = jsonText.data(using: .utf8),
                          let json = try? JSON(data: data) else {
                        errorMessage = "JSON is invalid. Please correct it before confirming."
                        return
                    }
                    onConfirm(json, notes.isEmpty ? nil : notes)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(minWidth: 560, minHeight: 480)
    }
}


private struct LLMActivityView: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let value = sin(time * 1.6)
            ZStack {
                Circle()
                    .stroke(Color.accentColor.opacity(0.25), lineWidth: 8)
                AngularGradient(gradient: Gradient(colors: [.accentColor, .purple, .pink, .accentColor]), center: .center, angle: .degrees(value * 180))
                    .mask(
                        Circle()
                            .trim(from: 0.0, to: 0.75)
                            .stroke(style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    )
                    .rotationEffect(.degrees(value * 120))
            }
            .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: value)
        }
    }
}
