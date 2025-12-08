//
//  SetupWizardView.swift
//  Sprung
//
//  First-run wizard to collect API keys, enable OpenRouter models,
//  and choose default models for onboarding, PDF extraction, and Git ingest.
//
import SwiftUI
import Observation

struct SetupWizardView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(EnabledLLMStore.self) private var enabledLLMStore
    @Environment(OpenRouterService.self) private var openRouterService

    @AppStorage("hasCompletedSetupWizard") private var hasCompletedSetupWizard = false
    @AppStorage("onboardingInterviewDefaultModelId") private var onboardingModelId: String = "gpt-5"
    @AppStorage("onboardingPDFExtractionModelId") private var pdfExtractionModelId: String = "google/gemini-2.0-flash-001"
    @AppStorage("onboardingGitIngestModelId") private var gitIngestModelId: String = Self.gitIngestDefaultModelId

    @State private var openRouterApiKey: String = APIKeyManager.get(.openRouter) ?? ""
    @State private var openAiApiKey: String = APIKeyManager.get(.openAI) ?? ""
    @State private var geminiApiKey: String = APIKeyManager.get(.gemini) ?? ""
    @State private var currentStep: Int = 0
    @State private var showModelPicker = false
    @State private var showExitAlert = false

    // Gemini models (lazy-loaded)
    @State private var geminiModels: [GoogleAIService.GeminiModel] = []
    @State private var isLoadingGeminiModels = false
    @State private var geminiModelError: String?
    private let googleAIService = GoogleAIService()

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
            .navigationBarTitleDisplayMode(.inline)
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
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Label("\(openRouterService.availableModels.count) available", systemImage: "tray.full")
                            .foregroundStyle(.secondary)
                        Label("\(enabledLLMStore.enabledModelIds.count) selected", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 12) {
                        Button("Fetch models") {
                            Task { await openRouterService.fetchModels() }
                        }
                        .disabled(openRouterApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Button("Choose models…") {
                            showModelPicker = true
                        }
                        .disabled(enabledLLMStore.enabledModels.isEmpty && openRouterService.availableModels.isEmpty)
                    }
                    if enabledLLMStore.enabledModels.isEmpty {
                        Label("Select at least one OpenRouter model to continue.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer()
        }
        .padding(24)
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
            SecureField(placeholder, text: value)
                .textFieldStyle(.roundedBorder)
            Text(help)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    var onboardingModelPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Onboarding Interview Model", selection: $onboardingModelId) {
                ForEach(onboardingInterviewModelOptions, id: \.id) { option in
                    Text(option.name).tag(option.id)
                }
            }
            .pickerStyle(.menu)
            Text("Used for the three-phase onboarding interview (OpenAI Responses API).")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
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
            if enabledLLMStore.enabledModels.isEmpty {
                return
            }
            withAnimation { currentStep += 1 }
        case .defaults:
            finalizeDefaults()
            completeAndDismiss(markCompleted: true)
        }
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

    var onboardingInterviewModelOptions: [(id: String, name: String)] {
        [
            // GPT-5.1 family (preferred - supports "none" reasoning)
            ("gpt-5.1", "GPT-5.1"),
            ("gpt-5.1-codex", "GPT-5.1 Codex"),
            ("gpt-5.1-codex-mini", "GPT-5.1 Codex Mini"),
            ("gpt-5.1-codex-max", "GPT-5.1 Codex Max"),
            // GPT-5 family (requires "minimal" reasoning minimum)
            ("gpt-5", "GPT-5"),
            ("gpt-5-mini", "GPT-5 Mini"),
            ("gpt-5-nano", "GPT-5 Nano"),
            ("gpt-5-pro", "GPT-5 Pro"),
            ("gpt-5-codex", "GPT-5 Codex")
        ]
    }
}
