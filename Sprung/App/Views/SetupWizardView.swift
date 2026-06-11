//
//  SetupWizardView.swift
//  Sprung
//
//  First-run wizard to collect API keys, enable OpenRouter models,
//  and choose default models for onboarding, document analysis, and Git ingest.
//
import SwiftUI
import Observation
import SwiftOpenAI

struct SetupWizardView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(EnabledLLMStore.self) private var enabledLLMStore
    @Environment(OpenRouterService.self) private var openRouterService
    @Environment(LLMFacade.self) private var llmFacade

    @AppStorage("hasCompletedSetupWizard") private var hasCompletedSetupWizard = false
    @AppStorage("onboardingAnthropicModelId") private var interviewModelId: String = ""
    @AppStorage("onboardingDocAnalysisModelId") private var docAnalysisModelId: String = ""
    @AppStorage("onboardingGitIngestModelId") private var gitIngestModelId: String = ""
    @AppStorage("discoveryCoachingModelId") private var coachingModelId: String = ""

    @State private var openRouterApiKey: String = APIKeyManager.get(.openRouter) ?? ""
    @State private var openAiApiKey: String = APIKeyManager.get(.openAI) ?? ""
    @State private var anthropicApiKey: String = APIKeyManager.get(.anthropic) ?? ""
    @State private var currentStep: Int = 0
    @State private var showModelPicker = false
    @State private var showExitAlert = false

    // Model selection from OpenRouter API
    @State private var selectedModelIds: Set<String> = []
    @State private var isLoadingModels = false
    @State private var modelLoadError: String?

    // Anthropic models for document analysis (lazy-loaded)
    @State private var anthropicModels: [AnthropicModel] = []
    @State private var isLoadingAnthropicModels = false
    @State private var anthropicModelError: String?

    // Provider prefixes for grouping
    private static let targetProviders = ["google", "openai", "anthropic", "x-ai", "deepseek"]

    var onFinish: (() -> Void)?

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
                await preloadAnthropicModelsIfPossible()
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
                Label("Add API keys for OpenRouter, OpenAI (interview + TTS), and Anthropic (document analysis).", systemImage: "key.fill")
                Label("Choose OpenRouter models to enable.", systemImage: "switch.2")
                Label("Set defaults for onboarding, document analysis, and Git ingest.", systemImage: "slider.horizontal.3")
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
                        title: "Anthropic (document analysis)",
                        placeholder: "sk-ant-…",
                        value: $anthropicApiKey,
                        isRequired: false,
                        help: "Needed for document ingestion: summaries, narrative cards, skill bank, and enrichment."
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
                    docAnalysisPicker
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
            if filteredAnthropicModels.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Button("Load Anthropic models") {
                            Task { await preloadAnthropicModelsIfPossible(force: true) }
                        }
                        .disabled(isLoadingAnthropicModels || anthropicApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if isLoadingAnthropicModels {
                            ProgressView().scaleEffect(0.7)
                        }
                    }
                    if let anthropicModelError {
                        Text(anthropicModelError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    } else if anthropicApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Add an Anthropic API key to choose an interview model.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Picker("Onboarding Interview Model", selection: $interviewModelId) {
                    Text("Select a model…").tag("")
                    ForEach(filteredAnthropicModels, id: \.id) { model in
                        Text(model.displayName).tag(model.id)
                    }
                }
                .pickerStyle(.menu)
            }
            Text("Used for the onboarding interview (Anthropic Messages API). An Opus-tier model is recommended.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    var docAnalysisPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            if filteredAnthropicModels.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Button("Load Anthropic models") {
                            Task { await preloadAnthropicModelsIfPossible(force: true) }
                        }
                        .disabled(isLoadingAnthropicModels || anthropicApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if isLoadingAnthropicModels {
                            ProgressView().scaleEffect(0.7)
                        }
                    }
                    if let anthropicModelError {
                        Text(anthropicModelError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    } else if anthropicApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Add an Anthropic API key to choose a document analysis model.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Picker("Document Analysis Model", selection: $docAnalysisModelId) {
                    Text("Select a model…").tag("")
                    ForEach(filteredAnthropicModels, id: \.id) { model in
                        Text(model.displayName).tag(model.id)
                    }
                }
                .pickerStyle(.menu)
            }
            Text("Powers all document ingestion passes: summary, narrative cards, skill bank, and enrichment. An Opus-tier model is recommended.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .task {
            if anthropicModels.isEmpty {
                await preloadAnthropicModelsIfPossible()
            }
        }
    }

    /// Filtered Anthropic models for document analysis.
    private var filteredAnthropicModels: [AnthropicModel] {
        anthropicModels
            .filter { model in
                let id = model.id.lowercased()
                return id.hasPrefix("claude-") && !id.contains("instant")
            }
            .sorted { $0.displayName < $1.displayName }
    }

    var gitIngestPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            if filteredAnthropicModels.isEmpty {
                Text("Add an Anthropic API key and load models to choose a Git ingest model.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Git Ingest Model", selection: $gitIngestModelId) {
                    Text("Select a model…").tag("")
                    ForEach(filteredAnthropicModels, id: \.id) { model in
                        Text(model.displayName).tag(model.id)
                    }
                }
                .pickerStyle(.menu)
            }
            Text("Used when scanning repositories during onboarding. An Opus-tier model is recommended.")
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
        let anthropic = anthropicApiKey.trimmingCharacters(in: .whitespacesAndNewlines)

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
        if anthropic.isEmpty {
            APIKeyManager.delete(.anthropic)
        } else {
            _ = APIKeyManager.set(.anthropic, value: anthropic)
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
        // No-op: Model validation removed - if user selection is invalid,
        // operations will throw ModelConfigurationError at runtime
    }

    func completeAndDismiss(markCompleted: Bool) {
        if markCompleted {
            hasCompletedSetupWizard = true
        }
        dismiss()
        onFinish?()
    }

    @MainActor
    func preloadAnthropicModelsIfPossible(force: Bool = false) async {
        guard !isLoadingAnthropicModels else { return }
        let hasKey = !(anthropicApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        guard force || hasKey else { return }
        isLoadingAnthropicModels = true
        anthropicModelError = nil
        do {
            let response = try await llmFacade.anthropicListModels()
            anthropicModels = response.data
            if !filteredAnthropicModels.contains(where: { $0.id == docAnalysisModelId }) {
                docAnalysisModelId = ""
            }
            if !filteredAnthropicModels.contains(where: { $0.id == interviewModelId }) {
                interviewModelId = ""
            }
            if !filteredAnthropicModels.contains(where: { $0.id == gitIngestModelId }) {
                gitIngestModelId = ""
            }
        } catch {
            anthropicModelError = error.localizedDescription
        }
        isLoadingAnthropicModels = false
    }

}
