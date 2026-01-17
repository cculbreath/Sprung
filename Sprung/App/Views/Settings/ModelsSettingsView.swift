//
//  ModelsSettingsView.swift
//  Sprung
//
//  Consolidated view for all LLM model selections.
//  Force-refreshes model lists on every open.
//

import SwiftUI
import SwiftOpenAI

struct ModelsSettingsView: View {
    // MARK: - Onboarding Models
    @AppStorage("onboardingAnthropicModelId") private var onboardingAnthropicModelId: String = ""

    // MARK: - Seed Generation (per-backend persistence)
    @AppStorage("seedGenerationBackend") private var seedGenerationBackend: String = "anthropic"
    @AppStorage("seedGenerationAnthropicModelId") private var seedGenerationAnthropicModelId: String = ""
    @AppStorage("seedGenerationOpenRouterModelId") private var seedGenerationOpenRouterModelId: String = ""

    // MARK: - Document Processing
    @AppStorage("onboardingPDFExtractionModelId") private var pdfExtractionModelId: String = ""
    @AppStorage("onboardingDocSummaryModelId") private var docSummaryModelId: String = ""
    @AppStorage("onboardingCardMergeModelId") private var cardMergeModelId: String = ""

    // MARK: - Skill Processing
    @AppStorage("skillBankModelId") private var skillBankModelId: String = ""
    @AppStorage("kcExtractionModelId") private var kcExtractionModelId: String = ""
    @AppStorage("guidanceExtractionModelId") private var guidanceExtractionModelId: String = ""
    @AppStorage("skillsProcessingModelId") private var skillsProcessingModelId: String = ""
    @AppStorage("skillsProcessingParallelAgents") private var skillsProcessingParallelAgents: Int = 12

    // MARK: - Additional Models
    @AppStorage("voicePrimerExtractionModelId") private var voicePrimerModelId: String = ""
    @AppStorage("onboardingKCAgentModelId") private var kcAgentModelId: String = ""
    @AppStorage("onboardingGitIngestModelId") private var gitIngestModelId: String = ""
    @AppStorage("backgroundProcessingModelId") private var backgroundProcessingModelId: String = ""

    // MARK: - Discovery Models
    @AppStorage("discoveryCoachingModelId") private var coachingModelId: String = ""

    // MARK: - Environment
    @Environment(EnabledLLMStore.self) private var enabledLLMStore
    @Environment(LLMFacade.self) private var llmFacade
    @Environment(DiscoveryCoordinator.self) private var discoveryCoordinator

    // MARK: - Model List State
    @State private var anthropicModels: [AnthropicModel] = []
    @State private var isLoadingAnthropicModels = false
    @State private var anthropicModelError: String?

    @State private var geminiModels: [GoogleAIService.GeminiModel] = []
    @State private var isLoadingGeminiModels = false
    @State private var geminiModelError: String?

    @State private var openAIModels: [ModelObject] = []
    @State private var isLoadingOpenAIModels = false
    @State private var openAIModelError: String?

    // Discovery state synced with coordinator
    @State private var discoveryLLMModelId: String = ""
    @State private var discoveryReasoningEffort: String = "low"

    private let googleAIService = GoogleAIService()

    private let reasoningOptions = [
        (value: "low", label: "Low"),
        (value: "medium", label: "Medium"),
        (value: "high", label: "High")
    ]

    var body: some View {
        Form {
            Section {
                interviewModelPicker
            } header: {
                SettingsSectionHeader(title: "Interview", systemImage: "bubble.left.and.bubble.right")
            }

            Section {
                seedGenerationModelPicker
            } header: {
                SettingsSectionHeader(title: "Experience Defaults Generation", systemImage: "wand.and.stars")
            }

            Section {
                documentProcessingPickers
            } header: {
                SettingsSectionHeader(title: "Document Processing", systemImage: "doc.viewfinder")
            }

            Section {
                skillProcessingPickers
            } header: {
                SettingsSectionHeader(title: "Skill Processing", systemImage: "list.bullet.rectangle")
            }

            Section {
                additionalModelPickers
            } header: {
                SettingsSectionHeader(title: "Additional Models", systemImage: "cpu")
            }

            Section {
                discoveryModelPickers
            } header: {
                SettingsSectionHeader(title: "Discovery", systemImage: "magnifyingglass.circle.fill")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            // Force-refresh all model lists when settings opens
            Task {
                await refreshAllModelLists()
            }
            // Load Discovery settings from coordinator
            let s = discoveryCoordinator.settingsStore.current()
            discoveryLLMModelId = s.llmModelId
            discoveryReasoningEffort = s.reasoningEffort
        }
    }

    // MARK: - Computed Properties

    private var hasAnthropicKey: Bool {
        APIKeyManager.get(.anthropic) != nil
    }

    private var hasGeminiKey: Bool {
        APIKeyManager.get(.gemini) != nil
    }

    private var hasOpenAIKey: Bool {
        guard let key = APIKeyManager.get(.openAI) else { return false }
        return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var filteredAnthropicModels: [AnthropicModel] {
        anthropicModels
            .filter { model in
                let id = model.id.lowercased()
                return id.hasPrefix("claude-") && !id.contains("instant")
            }
            .sorted { $0.displayName < $1.displayName }
    }

    private var filteredOpenAIModels: [ModelObject] {
        openAIModels
            .filter { model in
                let id = model.id.lowercased()
                return id.hasPrefix("gpt-4o") || id.hasPrefix("gpt-5") || id.hasPrefix("gpt-6") || id.hasPrefix("gpt-7")
            }
            .sorted { $0.id < $1.id }
    }

    private var allOpenRouterModels: [EnabledLLM] {
        enabledLLMStore.enabledModels
            .sorted { lhs, rhs in
                (lhs.displayName.isEmpty ? lhs.modelId : lhs.displayName)
                    < (rhs.displayName.isEmpty ? rhs.modelId : rhs.displayName)
            }
    }

    private var currentSeedModelBinding: Binding<String> {
        seedGenerationBackend == "anthropic"
            ? $seedGenerationAnthropicModelId
            : $seedGenerationOpenRouterModelId
    }
}

// MARK: - Interview Model Picker
private extension ModelsSettingsView {
    @ViewBuilder
    var interviewModelPicker: some View {
        modelPickerRow(
            title: "Interview Model",
            backend: "Anthropic",
            backendColor: .orange
        ) {
            if !hasAnthropicKey {
                missingKeyWarning("Add Anthropic API key to enable interview model selection.")
            } else if isLoadingAnthropicModels {
                loadingIndicator("Loading Claude models...")
            } else if let error = anthropicModelError {
                errorView(error) { Task { await loadAnthropicModels() } }
            } else if filteredAnthropicModels.isEmpty {
                emptyModelsView("No Claude models available") { Task { await loadAnthropicModels() } }
            } else {
                Picker("Model", selection: $onboardingAnthropicModelId) {
                    ForEach(filteredAnthropicModels) { model in
                        Text(model.displayName).tag(model.id)
                    }
                }
                .pickerStyle(.menu)
                Text("Claude models support extended thinking and tool use natively.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Seed Generation Model Picker
private extension ModelsSettingsView {
    @ViewBuilder
    var seedGenerationModelPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Backend", selection: $seedGenerationBackend) {
                Text("Anthropic (Direct)").tag("anthropic")
                Text("OpenRouter").tag("openrouter")
            }
            .pickerStyle(.segmented)

            Text(seedGenerationBackend == "anthropic"
                ? "Direct Anthropic API with prompt caching for faster, cheaper generation."
                : "OpenRouter for model flexibility. Caching depends on underlying provider.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Divider()
                .padding(.vertical, 4)

            if seedGenerationBackend == "anthropic" {
                modelPickerRow(
                    title: "Model",
                    backend: "Anthropic",
                    backendColor: .orange
                ) {
                    if !hasAnthropicKey {
                        missingKeyWarning("Add Anthropic API key to use direct Anthropic backend.")
                    } else if filteredAnthropicModels.isEmpty {
                        loadingIndicator("Loading models...")
                    } else {
                        Picker("", selection: $seedGenerationAnthropicModelId) {
                            ForEach(filteredAnthropicModels) { model in
                                Text(model.displayName).tag(model.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }
                }
            } else {
                modelPickerRow(
                    title: "Model",
                    backend: "OpenRouter",
                    backendColor: .purple
                ) {
                    Picker("", selection: $seedGenerationOpenRouterModelId) {
                        ForEach(allOpenRouterModels, id: \.modelId) { model in
                            Text(model.displayName.isEmpty ? model.modelId : model.displayName)
                                .tag(model.modelId)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
            }

            Text("Generates professional descriptions for work history, education, and projects after onboarding.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Document Processing Pickers
private extension ModelsSettingsView {
    @ViewBuilder
    var documentProcessingPickers: some View {
        // PDF Extraction
        modelPickerRow(
            title: "PDF Extraction Model",
            backend: "Gemini",
            backendColor: .blue
        ) {
            if !hasGeminiKey {
                missingKeyWarning("Add Google Gemini API key to enable native PDF extraction.")
            } else if isLoadingGeminiModels {
                loadingIndicator("Loading Gemini models...")
            } else if let error = geminiModelError {
                errorView(error) { Task { await loadGeminiModels() } }
            } else if geminiModels.isEmpty {
                emptyModelsView("No Gemini models available") { Task { await loadGeminiModels() } }
            } else {
                Picker("", selection: $pdfExtractionModelId) {
                    ForEach(geminiModels.filter { $0.outputTokenLimit >= 64000 }) { model in
                        Text(model.displayName).tag(model.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                Text("Uses Google's Files API for native PDF processing up to 2GB.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }

        // Doc Summary
        modelPickerRow(
            title: "Doc Summary Model",
            backend: "Gemini",
            backendColor: .blue
        ) {
            if !hasGeminiKey {
                missingKeyWarning("Add Google Gemini API key to enable document summarization.")
            } else if geminiModels.isEmpty {
                emptyModelsView("No Gemini models available") { Task { await loadGeminiModels() } }
            } else {
                Picker("", selection: $docSummaryModelId) {
                    ForEach(geminiModels.filter { $0.outputTokenLimit >= 64000 }) { model in
                        Text(model.displayName).tag(model.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                Text("Generates summaries of uploaded documents. Flash-Lite recommended for cost.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }

        // Card Merge
        modelPickerRow(
            title: "Card Merge Model",
            backend: "OpenRouter",
            backendColor: .purple
        ) {
            if allOpenRouterModels.isEmpty {
                missingKeyWarning("Enable OpenRouter models to configure card merge.")
            } else {
                Picker("", selection: $cardMergeModelId) {
                    ForEach(allOpenRouterModels, id: \.modelId) { model in
                        Text(model.displayName.isEmpty ? model.modelId : model.displayName)
                            .tag(model.modelId)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                Text("Card deduplication and experience defaults generation.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Skill Processing Pickers
private extension ModelsSettingsView {
    @ViewBuilder
    var skillProcessingPickers: some View {
        if !hasGeminiKey {
            missingKeyWarning("Add Google Gemini API key to enable skill/narrative extraction.")
        } else if geminiModels.isEmpty {
            emptyModelsView("No Gemini models available") { Task { await loadGeminiModels() } }
        } else {
            // Skill Bank
            modelPickerRow(title: "Skill Bank Model", backend: "Gemini", backendColor: .blue) {
                Picker("", selection: $skillBankModelId) {
                    ForEach(geminiModels.filter { $0.outputTokenLimit >= 16000 }) { model in
                        Text(model.displayName).tag(model.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                Text("Extracts comprehensive skill inventories. Flash recommended for speed.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            // Narrative Card
            modelPickerRow(title: "Narrative Card Model", backend: "Gemini", backendColor: .blue) {
                Picker("", selection: $kcExtractionModelId) {
                    ForEach(geminiModels.filter { $0.outputTokenLimit >= 32000 }) { model in
                        Text(model.displayName).tag(model.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                Text("Generates narrative knowledge cards. Pro recommended for quality.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            // Inference Guidance
            modelPickerRow(title: "Inference Guidance Model", backend: "Gemini", backendColor: .blue) {
                Picker("", selection: $guidanceExtractionModelId) {
                    ForEach(geminiModels.filter { $0.outputTokenLimit >= 4000 }) { model in
                        Text(model.displayName).tag(model.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                Text("Generates identity vocabulary, title sets, and voice profiles. Flash recommended.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Divider()
                .padding(.vertical, 4)

            // Skills Processing
            modelPickerRow(title: "Skills Processing Model", backend: "Gemini", backendColor: .blue) {
                Picker("", selection: $skillsProcessingModelId) {
                    ForEach(geminiModels.filter { $0.outputTokenLimit >= 64000 }) { model in
                        Text(model.displayName).tag(model.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                Text("Deduplicates skills and generates ATS synonym variants. Flash recommended.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            // Parallel Agents
            Stepper(value: $skillsProcessingParallelAgents, in: 1...24) {
                HStack {
                    Text("Parallel ATS Agents")
                    Spacer()
                    Text("\(skillsProcessingParallelAgents)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            Text("Number of parallel agents for ATS synonym expansion. Higher values process faster.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Additional Model Pickers
private extension ModelsSettingsView {
    @ViewBuilder
    var additionalModelPickers: some View {
        // Voice Primer
        modelPickerRow(title: "Voice Primer Model", backend: "OpenRouter", backendColor: .purple) {
            if allOpenRouterModels.isEmpty {
                missingKeyWarning("Enable OpenRouter models to configure voice extraction.")
            } else {
                Picker("", selection: $voicePrimerModelId) {
                    ForEach(allOpenRouterModels, id: \.modelId) { model in
                        Text(model.displayName.isEmpty ? model.modelId : model.displayName)
                            .tag(model.modelId)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                Text("Extracts voice characteristics from writing samples. Fast model recommended.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }

        // KC Agent
        modelPickerRow(title: "KC Agent Model", backend: "OpenRouter", backendColor: .purple) {
            if allOpenRouterModels.isEmpty {
                missingKeyWarning("Enable OpenRouter models to configure KC agent.")
            } else {
                Picker("", selection: $kcAgentModelId) {
                    ForEach(allOpenRouterModels, id: \.modelId) { model in
                        Text(model.displayName.isEmpty ? model.modelId : model.displayName)
                            .tag(model.modelId)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                Text("Metadata extraction for knowledge cards. Haiku recommended for speed.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }

        // Git Ingest
        modelPickerRow(title: "Git Ingest Model", backend: "OpenRouter", backendColor: .purple) {
            if allOpenRouterModels.isEmpty {
                missingKeyWarning("Enable OpenRouter models to adjust Git ingest model.")
            } else {
                Picker("", selection: $gitIngestModelId) {
                    ForEach(allOpenRouterModels, id: \.modelId) { model in
                        Text(model.displayName.isEmpty ? model.modelId : model.displayName)
                            .tag(model.modelId)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                Text("Analyzes git repositories for coding skills during onboarding.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }

        // Background Processing
        modelPickerRow(title: "Background Processing Model", backend: "OpenRouter", backendColor: .purple) {
            if allOpenRouterModels.isEmpty {
                Text("No models enabled. Enable models in API Keys settings.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Picker("", selection: $backgroundProcessingModelId) {
                    ForEach(allOpenRouterModels) { model in
                        Text(model.displayName.isEmpty ? model.modelId : model.displayName)
                            .tag(model.modelId)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                Text("Used for job requirement extraction. Fast, inexpensive models recommended.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Discovery Model Pickers
private extension ModelsSettingsView {
    @ViewBuilder
    var discoveryModelPickers: some View {
        // AI Model (OpenAI)
        modelPickerRow(title: "AI Model", backend: "OpenAI", backendColor: .green) {
            if !hasOpenAIKey {
                missingKeyWarning("Add OpenAI API key in API Keys settings first.")
            } else if isLoadingOpenAIModels {
                loadingIndicator("Loading models...")
            } else if let error = openAIModelError {
                errorView(error) { Task { await loadOpenAIModels() } }
            } else if filteredOpenAIModels.isEmpty {
                emptyModelsView("No GPT-4o/5/6/7 models available") { Task { await loadOpenAIModels() } }
            } else {
                Picker("", selection: $discoveryLLMModelId) {
                    ForEach(filteredOpenAIModels, id: \.id) { model in
                        Text(model.id).tag(model.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .onChange(of: discoveryLLMModelId) { _, newValue in
                    guard !newValue.isEmpty else { return }
                    var s = discoveryCoordinator.settingsStore.current()
                    guard s.llmModelId != newValue else { return }
                    s.llmModelId = newValue
                    discoveryCoordinator.settingsStore.update(s)
                }

                // Reasoning effort
                Picker("Reasoning Effort", selection: $discoveryReasoningEffort) {
                    ForEach(reasoningOptions, id: \.value) { option in
                        Text(option.label).tag(option.value)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: discoveryReasoningEffort) { _, newValue in
                    var s = discoveryCoordinator.settingsStore.current()
                    guard s.reasoningEffort != newValue else { return }
                    s.reasoningEffort = newValue
                    discoveryCoordinator.settingsStore.update(s)
                }

                Text("Model and reasoning effort for source discovery and daily tasks.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }

        // Coaching Model (OpenRouter)
        modelPickerRow(title: "Coaching Model", backend: "OpenRouter", backendColor: .purple) {
            if allOpenRouterModels.isEmpty {
                Text("No enabled models. Add models in LLM Settings.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Picker("", selection: $coachingModelId) {
                    ForEach(allOpenRouterModels, id: \.modelId) { model in
                        Text(model.displayName).tag(model.modelId)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                Text("Model for daily coaching. Uses OpenRouter.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Helper Views
private extension ModelsSettingsView {
    func modelPickerRow<Content: View>(
        title: String,
        backend: String,
        backendColor: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                Text(backend)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(backendColor.opacity(0.15), in: Capsule())
                    .foregroundStyle(backendColor)
            }
            content()
        }
    }

    func missingKeyWarning(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
            .font(.callout)
    }

    func loadingIndicator(_ message: String) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    func errorView(_ error: String, retry: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Failed to load models", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.callout)
            Text(error)
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Retry", action: retry)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }

    func emptyModelsView(_ message: String, load: @escaping () -> Void) -> some View {
        HStack {
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Load Models", action: load)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }
}

// MARK: - Model Loading
private extension ModelsSettingsView {
    func refreshAllModelLists() async {
        async let anthropic: () = loadAnthropicModels()
        async let gemini: () = loadGeminiModels()
        async let openai: () = loadOpenAIModels()
        _ = await (anthropic, gemini, openai)
    }

    @MainActor
    func loadAnthropicModels() async {
        guard hasAnthropicKey else {
            anthropicModelError = "Anthropic API key not configured"
            return
        }
        isLoadingAnthropicModels = true
        anthropicModelError = nil
        do {
            let response = try await llmFacade.anthropicListModels()
            anthropicModels = response.data
            // Auto-select if current selection is invalid
            if !filteredAnthropicModels.contains(where: { $0.id == onboardingAnthropicModelId }) {
                if let first = filteredAnthropicModels.first {
                    onboardingAnthropicModelId = first.id
                }
            }
            if !filteredAnthropicModels.contains(where: { $0.id == seedGenerationAnthropicModelId }) {
                if let first = filteredAnthropicModels.first {
                    seedGenerationAnthropicModelId = first.id
                }
            }
        } catch {
            anthropicModelError = error.localizedDescription
        }
        isLoadingAnthropicModels = false
    }

    @MainActor
    func loadGeminiModels() async {
        guard hasGeminiKey else {
            geminiModelError = "Gemini API key not configured"
            return
        }
        isLoadingGeminiModels = true
        geminiModelError = nil
        do {
            geminiModels = try await googleAIService.fetchAvailableModels()
        } catch {
            geminiModelError = error.localizedDescription
        }
        isLoadingGeminiModels = false
    }

    @MainActor
    func loadOpenAIModels() async {
        guard hasOpenAIKey else {
            openAIModelError = "OpenAI API key not configured"
            return
        }
        guard let apiKey = APIKeyManager.get(.openAI) else { return }

        isLoadingOpenAIModels = true
        openAIModelError = nil
        do {
            let service = OpenAIServiceFactory.service(apiKey: apiKey)
            let response = try await service.listModels()
            openAIModels = response.data
            // Validate current selection
            if !filteredOpenAIModels.contains(where: { $0.id == discoveryLLMModelId }) {
                if let first = filteredOpenAIModels.first {
                    discoveryLLMModelId = first.id
                    var s = discoveryCoordinator.settingsStore.current()
                    s.llmModelId = first.id
                    discoveryCoordinator.settingsStore.update(s)
                }
            }
        } catch {
            openAIModelError = error.localizedDescription
        }
        isLoadingOpenAIModels = false
    }
}
