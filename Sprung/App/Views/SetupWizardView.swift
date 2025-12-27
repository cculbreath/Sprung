//
//  SetupWizardView.swift
//  Sprung
//
//  First-run wizard to collect API keys, enable OpenRouter models,
//  and choose default models for onboarding, PDF extraction, and Git ingest.
//
import SwiftUI
import Observation
import SwiftOpenAI

struct SetupWizardView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(EnabledLLMStore.self) private var enabledLLMStore
    @Environment(OpenRouterService.self) private var openRouterService

    @AppStorage("hasCompletedSetupWizard") private var hasCompletedSetupWizard = false
    @AppStorage("onboardingInterviewDefaultModelId") private var onboardingModelId: String = "gpt-5"
    @AppStorage("onboardingPDFExtractionModelId") private var pdfExtractionModelId: String = "google/gemini-2.0-flash-001"
    @AppStorage("onboardingGitIngestModelId") private var gitIngestModelId: String = Self.gitIngestDefaultModelId
    @AppStorage("discoveryCoachingModelId") private var coachingModelId: String = ""

    @State private var openRouterApiKey: String = APIKeyManager.get(.openRouter) ?? ""
    @State private var openAiApiKey: String = APIKeyManager.get(.openAI) ?? ""
    @State private var geminiApiKey: String = APIKeyManager.get(.gemini) ?? ""
    @State private var currentStep: Int = 0
    @State private var showModelPicker = false
    @State private var showExitAlert = false

    // Model selection from OpenRouter API
    @State private var selectedModelIds: Set<String> = []
    @State private var isLoadingModels = false
    @State private var modelLoadError: String?

    // Gemini models (lazy-loaded)
    @State private var geminiModels: [GoogleAIService.GeminiModel] = []
    @State private var isLoadingGeminiModels = false
    @State private var geminiModelError: String?
    private let googleAIService = GoogleAIService()

    // Interview models from OpenAI (lazy-loaded)
    @State private var interviewModels: [ModelObject] = []
    @State private var isLoadingInterviewModels = false
    @State private var interviewModelError: String?

    // Provider prefixes for grouping
    private static let targetProviders = ["google", "openai", "anthropic", "x-ai", "deepseek"]

    var onFinish: (() -> Void)?

    private static let gitIngestDefaultModelId = "anthropic/claude-haiku-4.5"

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                Divider()
                content
                Divider()
                footer
            }
            .frame(minWidth: 780, minHeight: 560)
            .navigationTitle("Welcome to Sprung")
            .sheet(isPresented: $showModelPicker) {
                OpenRouterModelSelectionSheet()
                    .environment(enabledLLMStore)
                    .environment(openRouterService)
            }
            .alert("Skip setup?", isPresented: $showExitAlert) {
                Button("Skip", role: .destructive) {
                    completeAndDismiss(markCompleted: true)
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("You can rerun the wizard from Settings at any time.")
            }
            .task {
                await preloadGeminiModelsIfPossible()
            }
        }
    }
}

// MARK: - Sections
private extension SetupWizardView {
    var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text("First-Time Setup")
                    .font(.title2.weight(.semibold))
                Text(stepSubtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            ProgressView(value: Double(currentStep), total: Double(Step.allCases.count - 1))
                .frame(width: 200)
        }
        .padding(20)
    }

    @ViewBuilder
    var content: some View {
        switch Step(rawValue: currentStep) ?? .welcome {
        case .welcome:
            welcomeStep
        case .apiKeys:
            apiKeysStep
        case .models:
            modelSelectionStep
        case .defaults:
            defaultsStep
        }
    }

    var footer: some View {
        HStack {
            Button("Back") {
                withAnimation { currentStep = max(0, currentStep - 1) }
            }
            .disabled(currentStep == 0)

            Spacer()

            Button("Skip for now") {
                showExitAlert = true
            }

            Button(currentStep == Step.allCases.count - 1 ? "Finish" : "Next") {
                Task {
                    await handleAdvance()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
    }
}

// MARK: - Steps
private extension SetupWizardView {
    var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("A quick guided setup to get you drafting quickly.")
                .font(.headline)
            VStack(alignment: .leading, spacing: 10) {
                Label("Add API keys for OpenRouter, OpenAI (interview + TTS), and Gemini (PDF extraction).", systemImage: "key.fill")
                Label("Choose OpenRouter models to enable.", systemImage: "switch.2")
                Label("Set defaults for onboarding, PDF extraction, and Git ingest.", systemImage: "slider.horizontal.3")
                Label("Optional: revisit this wizard anytime from Settings.", systemImage: "clock.arrow.circlepath")
            }
            .labelStyle(.titleAndIcon)
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    var apiKeysStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add API Keys")
                .font(.headline)
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    keyField(
                        title: "OpenRouter",
                        placeholder: "sk-or-…",
                        value: $openRouterApiKey,
                        isRequired: true,
                        help: "Required for multi-model resume/cover workflows and Git ingest."
                    )
                    keyField(
                        title: "OpenAI (Interview + TTS)",
                        placeholder: "sk-…",
                        value: $openAiApiKey,
                        isRequired: true,
                        help: "Used for onboarding interview and streaming text-to-speech."
                    )
                    keyField(
                        title: "Google Gemini (PDF extraction)",
                        placeholder: "AIza…",
                        value: $geminiApiKey,
                        isRequired: false,
                        help: "Needed for document ingestion and PDF/Doc text extraction."
                    )
                }
            }
            Text("Keys are stored in macOS Keychain and never written in plaintext.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(24)
    }

    var modelSelectionStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Enable OpenRouter Models")
                .font(.headline)
            Text("Select the models you want to use for resume and cover letter generation. You can change these later in Settings.")
                .font(.callout)
                .foregroundStyle(.secondary)

            if isLoadingModels {
                HStack {
                    ProgressView()
                    Text("Loading models from OpenRouter...")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = modelLoadError {
                VStack(spacing: 12) {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Button("Retry") {
                        Task { await fetchOpenRouterModels() }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if openRouterService.availableModels.isEmpty {
                VStack(spacing: 12) {
                    Text("No models loaded. Add your OpenRouter API key and fetch models.")
                        .foregroundStyle(.secondary)
                    Button("Fetch Models") {
                        Task { await fetchOpenRouterModels() }
                    }
                    .disabled(openRouterApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(Self.targetProviders, id: \.self) { provider in
                            providerSection(provider)
                        }
                    }
                }
                .frame(maxHeight: 340)

                HStack {
                    Text("\(selectedModelIds.count) models selected")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Select All") {
                        for provider in Self.targetProviders {
                            for model in modelsForProvider(provider) {
                                selectedModelIds.insert(model.id)
                            }
                        }
                    }
                    .buttonStyle(.link)
                    Button("Clear All") {
                        selectedModelIds.removeAll()
                    }
                    .buttonStyle(.link)
                }
            }

            if selectedModelIds.isEmpty && !openRouterService.availableModels.isEmpty {
                Label("Select at least one model to continue.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }

            Spacer()
        }
        .padding(24)
        .task {
            if openRouterService.availableModels.isEmpty && !openRouterApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                await fetchOpenRouterModels()
            }
        }
    }

    func modelsForProvider(_ provider: String) -> [OpenRouterModel] {
        openRouterService.availableModels
            .filter { $0.id.hasPrefix("\(provider)/") }
            .sorted { $0.name < $1.name }
    }

    func providerSection(_ provider: String) -> some View {
        let models = modelsForProvider(provider)
        let providerDisplayName = provider.split(separator: "-").map { $0.capitalized }.joined(separator: "-")

        return Group {
            if !models.isEmpty {
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(providerDisplayName)
                                .font(.subheadline.weight(.semibold))
                            Text("(\(models.count) models)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button(action: {
                                let providerIds = Set(models.map(\.id))
                                if providerIds.isSubset(of: selectedModelIds) {
                                    selectedModelIds.subtract(providerIds)
                                } else {
                                    selectedModelIds.formUnion(providerIds)
                                }
                            }) {
                                Text(Set(models.map(\.id)).isSubset(of: selectedModelIds) ? "Deselect All" : "Select All")
                                    .font(.caption)
                            }
                            .buttonStyle(.link)
                        }

                        ForEach(models, id: \.id) { model in
                            HStack {
                                Toggle(isOn: Binding(
                                    get: { selectedModelIds.contains(model.id) },
                                    set: { isSelected in
                                        if isSelected {
                                            selectedModelIds.insert(model.id)
                                        } else {
                                            selectedModelIds.remove(model.id)
                                        }
                                    }
                                )) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(model.name)
                                            .font(.body)
                                        HStack(spacing: 8) {
                                            Text(model.costLevelDescription())
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            if let ctx = model.contextLength {
                                                Text("\(ctx / 1000)K context")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                }
                                .toggleStyle(.checkbox)
                            }
                        }
                    }
                }
            }
        }
    }

    func fetchOpenRouterModels() async {
        isLoadingModels = true
        modelLoadError = nil
        await openRouterService.fetchModels()
        if openRouterService.availableModels.isEmpty {
            modelLoadError = "No models returned. Check your API key."
        }
        isLoadingModels = false
    }

    var defaultsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Set Default Models")
                .font(.headline)
            GroupBox {
                VStack(alignment: .leading, spacing: 16) {
                    onboardingModelPicker
                    Divider()
                    pdfExtractionPicker
                    Divider()
                    gitIngestPicker
                    Divider()
                    coachingModelPicker
                }
            }
            Spacer()
        }
        .padding(24)
    }
}

// MARK: - Subviews
private extension SetupWizardView {
    func keyField(
        title: String,
        placeholder: String,
        value: Binding<String>,
        isRequired: Bool,
        help: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.medium))
                if isRequired {
                    Text("Required")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            TextField(placeholder, text: value)
                .textFieldStyle(.roundedBorder)
            Text(help)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    var onboardingModelPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            if openAiApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Label("Add OpenAI API key to enable interview model selection.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)
            } else if isLoadingInterviewModels {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading interview models...")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else if let error = interviewModelError {
                VStack(alignment: .leading, spacing: 4) {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.callout)
                    Button("Retry") {
                        Task { await loadInterviewModels() }
                    }
                }
            } else if filteredInterviewModels.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("No interview models found.")
                        .foregroundStyle(.secondary)
                    Button("Load Models") {
                        Task { await loadInterviewModels() }
                    }
                }
            } else {
                Picker("Onboarding Interview Model", selection: $onboardingModelId) {
                    ForEach(filteredInterviewModels, id: \.id) { model in
                        Text(model.id).tag(model.id)
                    }
                }
                .pickerStyle(.menu)
            }
            Text("Used for the three-phase onboarding interview (OpenAI Responses API).")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .task {
            let hasKey = !openAiApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if hasKey && interviewModels.isEmpty {
                await loadInterviewModels()
            }
        }
    }

    /// Filtered interview models: gpt-5*, gpt-6*, gpt-7* (dynamically fetched from OpenAI)
    private var filteredInterviewModels: [ModelObject] {
        interviewModels
            .filter { model in
                let id = model.id.lowercased()
                return id.hasPrefix("gpt-5") || id.hasPrefix("gpt-6") || id.hasPrefix("gpt-7")
            }
            .sorted { $0.id < $1.id }
    }

    func loadInterviewModels() async {
        let apiKey = openAiApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else { return }
        isLoadingInterviewModels = true
        interviewModelError = nil
        do {
            let service = OpenAIServiceFactory.service(apiKey: apiKey)
            let response = try await service.listModels()
            interviewModels = response.data
            // Validate current selection is still available
            if !filteredInterviewModels.contains(where: { $0.id == onboardingModelId }) {
                if let first = filteredInterviewModels.first {
                    onboardingModelId = first.id
                }
            }
        } catch {
            interviewModelError = error.localizedDescription
        }
        isLoadingInterviewModels = false
    }

    var pdfExtractionPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            if geminiModels.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("PDF Extraction Model", text: $pdfExtractionModelId)
                        .textFieldStyle(.roundedBorder)
                    HStack(spacing: 8) {
                        Button("Load Gemini models") {
                            Task { await preloadGeminiModelsIfPossible(force: true) }
                        }
                        .disabled(isLoadingGeminiModels || geminiApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if isLoadingGeminiModels {
                            ProgressView().scaleEffect(0.7)
                        }
                    }
                    if let geminiModelError {
                        Text(geminiModelError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    } else {
                        Text("Using Gemini for PDF/Doc text extraction. Enter a model ID or load available models.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Picker("PDF Extraction Model", selection: $pdfExtractionModelId) {
                    ForEach(geminiModels, id: \.id) { model in
                        Text(model.displayName).tag(model.id)
                    }
                }
                .pickerStyle(.menu)
                Text("Select a Gemini model for document ingestion.").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    var gitIngestPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            if enabledLLMStore.enabledModels.isEmpty {
                Text("Enable OpenRouter models to choose a Git ingest model.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Git Ingest Model", selection: $gitIngestModelId) {
                    ForEach(enabledLLMStore.enabledModels.sorted(by: { $0.displayName < $1.displayName }), id: \.modelId) { model in
                        Text(model.displayName.isEmpty ? model.modelId : model.displayName)
                            .tag(model.modelId)
                    }
                }
                .pickerStyle(.menu)
            }
            Text("Used when scanning repositories during onboarding. Default: \(Self.gitIngestDefaultModelId)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    var coachingModelPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            if enabledLLMStore.enabledModels.isEmpty {
                Text("Enable OpenRouter models to choose a coaching model.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Daily Coaching Model", selection: $coachingModelId) {
                    ForEach(enabledLLMStore.enabledModels.sorted(by: { $0.displayName < $1.displayName }), id: \.modelId) { model in
                        Text(model.displayName.isEmpty ? model.modelId : model.displayName)
                            .tag(model.modelId)
                    }
                }
                .pickerStyle(.menu)
                .onAppear {
                    // Auto-select first model if none selected
                    if coachingModelId.isEmpty,
                       let first = enabledLLMStore.enabledModels.sorted(by: { $0.displayName < $1.displayName }).first {
                        coachingModelId = first.modelId
                    }
                }
            }
            Text("Used for daily job search coaching in Discovery. Uses OpenRouter.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Actions
private extension SetupWizardView {
    enum Step: Int, CaseIterable {
        case welcome = 0
        case apiKeys
        case models
        case defaults
    }

    var stepSubtitle: String {
        switch Step(rawValue: currentStep) ?? .welcome {
        case .welcome: return "Overview"
        case .apiKeys: return "Add API keys"
        case .models: return "Enable OpenRouter models"
        case .defaults: return "Pick defaults"
        }
    }

    func handleAdvance() async {
        guard let step = Step(rawValue: currentStep) else { return }
        switch step {
        case .welcome:
            withAnimation { currentStep += 1 }
        case .apiKeys:
            saveKeys()
            withAnimation { currentStep += 1 }
        case .models:
            if selectedModelIds.isEmpty {
                return
            }
            saveSelectedModels()
            withAnimation { currentStep += 1 }
        case .defaults:
            finalizeDefaults()
            completeAndDismiss(markCompleted: true)
        }
    }

    func saveSelectedModels() {
        // Enable all selected models in EnabledLLMStore
        for modelId in selectedModelIds {
            if let model = openRouterService.availableModels.first(where: { $0.id == modelId }) {
                enabledLLMStore.updateModelCapabilities(from: model)
            } else {
                // Model not in fetched list, create with minimal info
                let enabledModel = enabledLLMStore.getOrCreateModel(
                    id: modelId,
                    displayName: modelId,
                    provider: modelId.split(separator: "/").first.map(String.init) ?? ""
                )
                enabledModel.isEnabled = true
            }
        }
        enabledLLMStore.refreshEnabledModels()
        Logger.info("✅ Enabled \(selectedModelIds.count) OpenRouter models from setup wizard")
    }

    func saveKeys() {
        let router = openRouterApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let openai = openAiApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let gemini = geminiApiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        if router.isEmpty {
            APIKeyManager.delete(.openRouter)
        } else {
            _ = APIKeyManager.set(.openRouter, value: router)
        }
        if openai.isEmpty {
            APIKeyManager.delete(.openAI)
        } else {
            _ = APIKeyManager.set(.openAI, value: openai)
        }
        if gemini.isEmpty {
            APIKeyManager.delete(.gemini)
        } else {
            _ = APIKeyManager.set(.gemini, value: gemini)
        }
        NotificationCenter.default.post(name: .apiKeysChanged, object: nil)
        appState.reconfigureOpenRouterService()

        // Directly configure OpenRouterService with the key we have,
        // rather than relying on Keychain read-back which can race
        if !router.isEmpty {
            openRouterService.configure(apiKey: router)
        }
    }

    func finalizeDefaults() {
        // Ensure git ingest selection is valid against enabled models
        let ids = enabledLLMStore.enabledModels.map(\.modelId)
        let (sanitizedGit, adjustedGit) = ModelPreferenceValidator.sanitize(
            requested: gitIngestModelId,
            available: ids,
            fallback: Self.gitIngestDefaultModelId
        )
        if adjustedGit {
            gitIngestModelId = sanitizedGit
        }
        // Ensure PDF extraction model still points to something usable
        if !geminiModels.isEmpty {
            let ids = geminiModels.map(\.id)
            let (sanitizedPDF, adjustedPDF) = ModelPreferenceValidator.sanitize(
                requested: pdfExtractionModelId,
                available: ids,
                fallback: "google/gemini-2.0-flash-001"
            )
            if adjustedPDF {
                pdfExtractionModelId = sanitizedPDF
            }
        }
    }

    func completeAndDismiss(markCompleted: Bool) {
        if markCompleted {
            hasCompletedSetupWizard = true
        }
        dismiss()
        onFinish?()
    }

    func preloadGeminiModelsIfPossible(force: Bool = false) async {
        guard !isLoadingGeminiModels else { return }
        let hasKey = !(geminiApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        guard force || hasKey else { return }
        isLoadingGeminiModels = true
        geminiModelError = nil
        do {
            let models = try await googleAIService.fetchAvailableModels()
            await MainActor.run {
                geminiModels = models
                if let first = models.first, !models.contains(where: { $0.id == pdfExtractionModelId }) {
                    pdfExtractionModelId = first.id
                }
            }
        } catch {
            await MainActor.run {
                geminiModelError = error.localizedDescription
            }
        }
        await MainActor.run {
            isLoadingGeminiModels = false
        }
    }

}
