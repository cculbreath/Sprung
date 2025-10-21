import AppKit
import SwiftUI
import UniformTypeIdentifiers
import SwiftyJSON

struct OnboardingInterviewView: View {
    @Environment(OnboardingInterviewService.self) private var interviewService
    @Environment(EnabledLLMStore.self) private var enabledLLMStore
    @Environment(AppEnvironment.self) private var appEnvironment

    @State private var selectedModelId: String = ""
    @State private var userInput: String = ""
    @State private var shouldAutoScroll = true
    @State private var webSearchAllowed: Bool = true
    @State private var writingAnalysisAllowed: Bool = false
    @State private var showImportError = false
    @State private var importErrorText: String?

    @AppStorage("onboardingInterviewDefaultModelId") private var defaultModelId = "openai/gpt-5"
    @AppStorage("onboardingInterviewAllowWebSearchDefault") private var defaultWebSearchAllowed = true
    @AppStorage("onboardingInterviewAllowWritingAnalysisDefault") private var defaultWritingAnalysisAllowed = false

    private let fallbackModelId = "openai/gpt-5"

    var body: some View {
        @Bindable var service = interviewService

        VStack(spacing: 0) {
            wizardHeader(service: service)
            Divider()
            mainContent(service: service)
            Divider()
            bottomBar(service: service)
        }
        .frame(minWidth: 1040, minHeight: 700)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            initializeSelectionsIfNeeded(service: service)
        }
        .onChange(of: defaultModelId) { _, _ in
            syncModelSelection(applyingDefaults: true)
            updateServiceDefaults()
        }
        .onChange(of: defaultWebSearchAllowed) { _, newValue in
            if !service.isActive {
                webSearchAllowed = newValue
                updateServiceDefaults()
            }
        }
        .onChange(of: defaultWritingAnalysisAllowed) { _, newValue in
            if !service.isActive {
                writingAnalysisAllowed = newValue
            }
        }
        .onChange(of: service.allowWebSearch) { _, newValue in
            if service.isActive {
                webSearchAllowed = newValue
            }
        }
        .onChange(of: service.allowWritingAnalysis) { _, newValue in
            if service.isActive {
                writingAnalysisAllowed = newValue
            }
        }
        .sheet(isPresented: Binding(
            get: { service.pendingExtraction != nil },
            set: { newValue in
                if !newValue {
                    interviewService.cancelPendingExtraction()
                }
            }
        )) {
            if let pending = service.pendingExtraction {
                ExtractionReviewSheet(
                    extraction: pending,
                    onConfirm: { updated, notes in
                        Task { await interviewService.confirmPendingExtraction(updatedExtraction: updated, notes: notes) }
                    },
                    onCancel: {
                        interviewService.cancelPendingExtraction()
                    }
                )
            }
        }
        .alert("Import Failed", isPresented: $showImportError, presenting: importErrorText) { _ in
            Button("OK") { importErrorText = nil }
        } message: { message in
            Text(message)
        }
    }
}

// MARK: - Header & Layout

private extension OnboardingInterviewView {
    func wizardHeader(service: OnboardingInterviewService) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Onboarding Interview")
                        .font(.largeTitle)
                        .bold()
                    Text(headerSubtitle(for: service.wizardStep))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if service.isProcessing {
                    ProgressView()
                        .controlSize(.small)
                        .progressViewStyle(.circular)
                        .padding(.trailing, 4)
                }

                Button("Options…") {
                    NSApp.sendAction(#selector(AppDelegate.showSettingsWindow), to: nil, from: nil)
                }
                .buttonStyle(.bordered)
            }

            stepProgressView(service: service)
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 12)
    }

    func headerSubtitle(for step: OnboardingWizardStep) -> String {
        switch step {
        case .introduction:
            return "Get ready to capture résumé data, artifacts, and writing samples."
        case .resumeIntake:
            return "Review parsed résumé details before diving into deeper questions."
        case .artifactDiscovery:
            return "Surface impactful work and supporting evidence."
        case .writingCorpus:
            return "Collect writing samples to build a style profile."
        case .wrapUp:
            return "Confirm what we captured and note any follow-up items."
        }
    }

    func stepProgressView(service: OnboardingInterviewService) -> some View {
        HStack(alignment: .center, spacing: 16) {
            ForEach(OnboardingWizardStep.allCases) { step in
                let status = service.wizardStepStatuses[step] ?? .pending
                VStack(spacing: 6) {
                    Image(systemName: progressIcon(for: status))
                        .foregroundStyle(progressColor(for: status))
                        .font(.title3)
                    Text(step.title)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 120)
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
            }
        }
    }

    func progressIcon(for status: OnboardingWizardStepStatus) -> String {
        switch status {
        case .pending: return "circle"
        case .current: return "circle.fill"
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

    func mainContent(service: OnboardingInterviewService) -> some View {
        Group {
            switch service.wizardStep {
            case .introduction:
                introductionContent(service: service)
            default:
                stepLayout(service: service)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    func introductionContent(service: OnboardingInterviewService) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Welcome to the onboarding interview wizard.")
                        .font(.title2)
                        .bold()
                    Text("You'll confirm résumé data, share high-impact work, and optionally upload writing samples so Sprung can build evidence-backed résumés and tailored cover letters.")
                        .font(.body)
                }

                onboardingKeyChecklist

                modelSelectionBlock()

                Toggle("Allow web search during interview (helps find public references)", isOn: Binding(
                    get: { webSearchAllowed },
                    set: { newValue in
                        webSearchAllowed = newValue
                        defaultWebSearchAllowed = newValue
                        if service.isActive {
                            service.setWebSearchConsent(newValue)
                        } else {
                            updateServiceDefaults()
                        }
                    }
                ))
                .toggleStyle(.switch)

                Toggle("Allow writing-style analysis when prompted", isOn: Binding(
                    get: { writingAnalysisAllowed || (!service.isActive && defaultWritingAnalysisAllowed) },
                    set: { newValue in
                        writingAnalysisAllowed = newValue
                        defaultWritingAnalysisAllowed = newValue
                        if service.isActive {
                            service.setWritingAnalysisConsent(newValue)
                        }
                    }
                ))
                .toggleStyle(.switch)

                if appEnvironment.appState.openAiApiKey.isEmpty {
                    Label("Add an OpenAI API key in Settings before beginning.", systemImage: "exclamationmark.shield")
                        .foregroundStyle(.red)
                        .font(.callout)
                }

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    Text("What to expect")
                        .font(.headline)
                    ForEach(OnboardingWizardStep.allCases.filter { $0 != .introduction }) { step in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.seal")
                                    .foregroundStyle(.secondary)
                                Text(step.title)
                                    .font(.subheadline)
                                    .bold()
                            }
                            Text(step.subtitle)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 26)
                        }
                    }
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.vertical, 32)
        }
    }

    @ViewBuilder
    func modelSelectionBlock() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Interview model")
                .font(.headline)

            if openAIModels.isEmpty {
                Label("Enable OpenAI responses models via Options… → API Keys.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)
            } else {
                Picker("Model", selection: Binding(
                    get: { selectedModelId.isEmpty ? currentModelId() : selectedModelId },
                    set: { newValue in
                        selectedModelId = newValue
                        defaultModelId = newValue
                        updateServiceDefaults()
                    }
                )) {
                    ForEach(openAIModels, id: \.modelId) { model in
                        Text(model.displayName.isEmpty ? model.modelId : model.displayName)
                            .tag(model.modelId)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 260, alignment: .leading)

                Text("The onboarding workflow uses the OpenAI Responses API. Choose a responses-capable model to continue.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    var onboardingKeyChecklist: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Upload your latest résumé or LinkedIn profile on the next step.", systemImage: "doc.richtext")
            Label("Share artifacts—papers, repos, decks—to build knowledge cards and a fact ledger.", systemImage: "folder.badge.person.crop")
            Label("Optionally upload writing samples so Sprung can mirror your tone.", systemImage: "character.cursor.ibeam")
        }
        .labelStyle(.titleAndIcon)
        .font(.callout)
        .foregroundStyle(.secondary)
    }

    func stepLayout(service: OnboardingInterviewService) -> some View {
        HStack(spacing: 0) {
            stepDetail(service: service)
                .frame(minWidth: 340, maxWidth: 380)
            Divider()
            chatPanel(service: service)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func stepDetail(service: OnboardingInterviewService) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(detailHeadline(for: service.wizardStep))
                    .font(.title3)
                    .bold()

                Text(detailSubtitle(for: service.wizardStep))
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if let error = service.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }

                if service.wizardStep == .resumeIntake {
                    Toggle("Allow web search this session", isOn: Binding(
                        get: { webSearchAllowed },
                        set: { newValue in
                            webSearchAllowed = newValue
                            defaultWebSearchAllowed = newValue
                            if service.isActive {
                                service.setWebSearchConsent(newValue)
                            } else {
                                updateServiceDefaults()
                            }
                        }
                    ))
                    .toggleStyle(.switch)
                }

                if service.wizardStep == .writingCorpus {
                    Toggle("Enable writing-style analysis", isOn: Binding(
                        get: { writingAnalysisAllowed || (!service.isActive && defaultWritingAnalysisAllowed) },
                        set: { newValue in
                            writingAnalysisAllowed = newValue
                            defaultWritingAnalysisAllowed = newValue
                            if service.isActive {
                                service.setWritingAnalysisConsent(newValue)
                            }
                        }
                    ))
                    .toggleStyle(.switch)
                }

                let stepRequests = uploadRequests(for: service.wizardStep, service: service)
                if !stepRequests.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Pending uploads")
                            .font(.headline)
                        ForEach(stepRequests) { request in
                            UploadRequestCard(
                                request: request,
                                onSelectFile: { openPanel(for: request) },
                                onProvideLink: { url in
                                    Task { await interviewService.fulfillUploadRequest(id: request.id, link: url) }
                                },
                                onDecline: {
                                    Task { await interviewService.declineUploadRequest(id: request.id) }
                                }
                            )
                        }
                    }
                }

                if !service.uploadedItems.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Uploaded items")
                            .font(.headline)
                        ForEach(service.uploadedItems) { item in
                            Label("\(item.kind.rawValue.capitalized): \(item.name)", systemImage: "doc")
                                .font(.caption)
                        }
                    }
                }

                if service.wizardStep == .wrapUp {
                    WrapUpSummaryView(artifacts: service.artifacts, schemaIssues: service.schemaIssues)
                }
            }
            .padding(.vertical, 24)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    func detailHeadline(for step: OnboardingWizardStep) -> String {
        switch step {
        case .introduction:
            return "Overview"
        case .resumeIntake:
            return "Résumé Intake"
        case .artifactDiscovery:
            return "Artifact Discovery"
        case .writingCorpus:
            return "Writing Corpus"
        case .wrapUp:
            return "Review & Export"
        }
    }

    func detailSubtitle(for step: OnboardingWizardStep) -> String {
        switch step {
        case .introduction:
            return "Preview what the interview covers before you begin."
        case .resumeIntake:
            return "Upload your résumé or LinkedIn data and confirm the parsed extraction."
        case .artifactDiscovery:
            return "Share high-impact work artifacts so we can summarize accomplishments and metrics."
        case .writingCorpus:
            return "Provide representative writing samples to build your style profile."
        case .wrapUp:
            return "Review captured data, knowledge cards, and outstanding verification items."
        }
    }

    func bottomBar(service: OnboardingInterviewService) -> some View {
        HStack(spacing: 12) {
            Button("Cancel") {
                interviewService.reset()
            }
            .buttonStyle(.bordered)

            Spacer()

            if shouldShowBackButton(for: service.wizardStep) {
                Button("Go Back") {
                    handleBack(service: service)
                }
            }

            Button(continueButtonTitle(for: service.wizardStep)) {
                handleContinue(service: service)
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
        default:
            return service.isProcessing
        }
    }

    func handleContinue(service: OnboardingInterviewService) {
        switch service.wizardStep {
        case .introduction:
            beginInterview()
        case .resumeIntake:
            if service.isActive {
                service.setPhase(.artifactDiscovery)
            }
        case .artifactDiscovery:
            service.setPhase(.writingCorpus)
        case .writingCorpus:
            service.setPhase(.wrapUp)
        case .wrapUp:
            interviewService.reset()
        }
    }

    func handleBack(service: OnboardingInterviewService) {
        switch service.wizardStep {
        case .resumeIntake:
            interviewService.reset()
            initializeSelectionsIfNeeded(service: service)
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
}

// MARK: - Chat

private extension OnboardingInterviewView {
    func chatPanel(service: OnboardingInterviewService) -> some View {
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
                .background(Color(nsColor: .textBackgroundColor))
                .onChange(of: service.messages.count) { _, _ in
                    if shouldAutoScroll, let lastId = service.messages.last?.id {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
            }

            if !service.nextQuestions.isEmpty {
                Divider()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(service.nextQuestions) { question in
                            Button(action: { send(question.text) }) {
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
                TextField("Type your response…", text: $userInput, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)
                    .disabled(!service.isActive || service.isProcessing)
                    .onSubmit { send(userInput) }

                Button {
                    send(userInput)
                } label: {
                    Label("Send", systemImage: "paperplane.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !service.isActive || service.isProcessing)
            }
            .padding(.all, 16)
        }
        .frame(minWidth: 640, maxWidth: .infinity, maxHeight: .infinity)
    }

    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        userInput = ""
        Task { await interviewService.send(userMessage: trimmed) }
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

    func openPanel(for request: OnboardingUploadRequest) {
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
                Task { await interviewService.fulfillUploadRequest(id: request.id, fileURL: url) }
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
    func initializeSelectionsIfNeeded(service: OnboardingInterviewService) {
        syncModelSelection(applyingDefaults: true)
        if service.isActive {
            webSearchAllowed = service.allowWebSearch
            writingAnalysisAllowed = service.allowWritingAnalysis
        } else {
            webSearchAllowed = defaultWebSearchAllowed
            writingAnalysisAllowed = defaultWritingAnalysisAllowed
        }
        updateServiceDefaults()
    }

    func syncModelSelection(applyingDefaults: Bool = false) {
        if !selectedModelId.isEmpty && !applyingDefaults {
            return
        }

        let ids = openAIModels.map(\.modelId)
        if ids.contains(defaultModelId) {
            selectedModelId = defaultModelId
        } else if ids.contains(fallbackModelId) {
            selectedModelId = fallbackModelId
        } else if let first = ids.first {
            selectedModelId = first
        } else {
            selectedModelId = fallbackModelId
        }
    }

    func currentModelId() -> String {
        if !selectedModelId.isEmpty {
            return selectedModelId
        }
        return fallbackModelId
    }

    func updateServiceDefaults() {
        interviewService.setPreferredDefaults(
            modelId: currentModelId(),
            backend: .openAI,
            webSearchAllowed: webSearchAllowed
        )
    }

    func beginInterview() {
        let modelId = currentModelId()
        Task {
            await interviewService.startInterview(modelId: modelId, backend: .openAI)
            if writingAnalysisAllowed {
                interviewService.setWritingAnalysisConsent(true)
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
                Text(message.text)
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
