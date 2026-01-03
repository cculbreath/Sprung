//
//  OnboardingModelSettingsView.swift
//  Sprung
//
//
import SwiftUI
import SwiftOpenAI

struct OnboardingModelSettingsView: View {
    @AppStorage("onboardingInterviewDefaultModelId") private var onboardingModelId: String = "gpt-5"
    @AppStorage("onboardingAnthropicModelId") private var onboardingAnthropicModelId: String = "claude-sonnet-4-20250514"
    @AppStorage("onboardingProvider") private var onboardingProvider: String = "openai"
    @AppStorage("onboardingPDFExtractionModelId") private var pdfExtractionModelId: String = "gemini-2.5-flash"
    @AppStorage("onboardingGitIngestModelId") private var gitIngestModelId: String = "anthropic/claude-haiku-4.5"
    @AppStorage("onboardingDocSummaryModelId") private var docSummaryModelId: String = "gemini-2.5-flash-lite"
    @AppStorage("onboardingCardMergeModelId") private var cardMergeModelId: String = "openai/gpt-5"
    @AppStorage("narrativeDedupeModelId") private var narrativeDedupeModelId: String = "openai/gpt-4.1"
    @AppStorage("skillBankModelId") private var skillBankModelId: String = "gemini-2.5-flash"
    @AppStorage("kcExtractionModelId") private var kcExtractionModelId: String = "gemini-2.5-pro"
    @AppStorage("guidanceExtractionModelId") private var guidanceExtractionModelId: String = "gemini-2.5-flash"
    @AppStorage("voicePrimerExtractionModelId") private var voicePrimerModelId: String = "openai/gpt-4o-mini"
    @AppStorage("onboardingKCAgentModelId") private var kcAgentModelId: String = "anthropic/claude-haiku-4.5"
    @AppStorage("onboardingInterviewAllowWebSearchDefault") private var onboardingWebSearchAllowed: Bool = true
    @AppStorage("onboardingInterviewReasoningEffort") private var onboardingReasoningEffort: String = "none"
    @AppStorage("onboardingInterviewHardTaskReasoningEffort") private var onboardingHardTaskReasoningEffort: String = "medium"
    @AppStorage("onboardingInterviewFlexProcessing") private var onboardingFlexProcessing: Bool = true
    @AppStorage("onboardingInterviewPromptCacheRetention") private var onboardingPromptCacheRetention: Bool = true
    @AppStorage("backgroundProcessingModelId") private var backgroundProcessingModelId: String = "google/gemini-2.0-flash-001"
    @AppStorage("knowledgeCardTokenLimit") private var knowledgeCardTokenLimit: Int = 8000
    @AppStorage("onboardingMaxConcurrentExtractions") private var maxConcurrentExtractions: Int = 5
    @AppStorage("maxConcurrentPDFExtractions") private var maxConcurrentPDFExtractions: Int = 30
    @AppStorage("pdfJudgeUseFourUp") private var pdfJudgeUseFourUp: Bool = false
    @AppStorage("pdfJudgeDPI") private var pdfJudgeDPI: Int = 150
    @AppStorage("onboardingEphemeralTurns") private var ephemeralTurns: Int = 3

    @Environment(EnabledLLMStore.self) private var enabledLLMStore
    @Environment(LLMFacade.self) private var llmFacade

    @State private var geminiModels: [GoogleAIService.GeminiModel] = []
    @State private var isLoadingGeminiModels = false
    @State private var geminiModelError: String?
    @State private var interviewModels: [ModelObject] = []
    @State private var isLoadingInterviewModels = false
    @State private var interviewModelError: String?
    @State private var anthropicModels: [AnthropicModel] = []
    @State private var isLoadingAnthropicModels = false
    @State private var anthropicModelError: String?

    private let googleAIService = GoogleAIService()
    private let pdfExtractionFallbackModelId = DefaultModels.gemini

    /// Models that support extended prompt cache retention (24h)
    private let promptCacheRetentionCompatibleModels: Set<String> = [
        "gpt-5.2",
        "gpt-5.1-codex-max", "gpt-5.1", "gpt-5.1-codex", "gpt-5.1-codex-mini", "gpt-5.1-chat-latest",
        "gpt-5", "gpt-5-codex",
        "gpt-4.1"
    ]

    /// Models that support flex processing (50% cost savings, variable latency)
    private let flexProcessingCompatibleModels: Set<String> = [
        "gpt-5.2", "gpt-5.1", "gpt-5", "gpt-5-mini", "gpt-5-nano",
        "o3", "o4-mini"
    ]

    private let reasoningOptions: [(value: String, label: String, detail: String)] = [
        ("none", "None", "GPT-5.1 only; fastest responses, no reasoning tokens"),
        ("minimal", "Minimal", "GPT-5 only; lightweight reasoning"),
        ("low", "Low", "Light reasoning for moderately complex tasks"),
        ("medium", "Medium", "Balanced speed and reasoning depth"),
        ("high", "High", "Maximum reasoning; best for complex tasks")
    ]

    var body: some View {
        Form {
            Section {
                providerPicker
            } header: {
                SettingsSectionHeader(title: "Provider", systemImage: "server.rack")
            }

            Section {
                onboardingInterviewModelPicker
            } header: {
                SettingsSectionHeader(title: "Interview Model", systemImage: "bubble.left.and.bubble.right")
            }

            Section {
                pdfExtractionModelPicker
                docSummaryModelPicker
            } header: {
                SettingsSectionHeader(title: "Document Processing", systemImage: "doc.viewfinder")
            }

            Section {
                skillExtractionModelPickers
            } header: {
                SettingsSectionHeader(title: "Skill Extraction", systemImage: "list.bullet.rectangle")
            }

            Section {
                voiceAndMetadataModelPickers
                gitIngestModelPicker
                backgroundProcessingModelPicker
            } header: {
                SettingsSectionHeader(title: "Additional Models", systemImage: "cpu")
            }

            Section {
                knowledgeCardTokenLimitPicker
                maxConcurrentExtractionsPicker
                ephemeralTurnsPicker
                Toggle("Allow web search during interviews", isOn: $onboardingWebSearchAllowed)
            } header: {
                SettingsSectionHeader(title: "Processing Limits", systemImage: "slider.horizontal.3")
            }

            // OpenAI-specific settings (hidden when Anthropic selected)
            if !isAnthropicProvider {
                Section {
                    onboardingReasoningPicker
                    onboardingFlexProcessingToggle
                    onboardingPromptCacheRetentionToggle
                } header: {
                    SettingsSectionHeader(title: "OpenAI Options", systemImage: "gearshape.2")
                }
            }
        }
        .formStyle(.grouped)
        .task {
            sanitizePDFExtractionModelIfNeeded()
            sanitizeGitIngestModelIfNeeded()
            sanitizeBackgroundProcessingModelIfNeeded()
        }
        .onChange(of: enabledLLMStore.enabledModels.map(\.modelId)) { _, _ in
            sanitizePDFExtractionModelIfNeeded()
            sanitizeGitIngestModelIfNeeded()
            sanitizeBackgroundProcessingModelIfNeeded()
        }
    }

    // MARK: - Computed Properties

    private var isAnthropicProvider: Bool {
        onboardingProvider == "anthropic"
    }

    private var filteredInterviewModels: [ModelObject] {
        interviewModels
            .filter { model in
                let id = model.id.lowercased()
                return id.hasPrefix("gpt-5") || id.hasPrefix("gpt-6") || id.hasPrefix("gpt-7")
            }
            .sorted { $0.id < $1.id }
    }

    private var filteredAnthropicModels: [AnthropicModel] {
        anthropicModels
            .filter { model in
                let id = model.id.lowercased()
                return id.hasPrefix("claude-") && !id.contains("instant")
            }
            .sorted { $0.displayName < $1.displayName }
    }

    private var hasGeminiKey: Bool {
        APIKeyManager.get(.gemini) != nil
    }

    private var hasOpenAIKey: Bool {
        APIKeyManager.get(.openAI) != nil
    }

    private var hasAnthropicKey: Bool {
        APIKeyManager.get(.anthropic) != nil
    }

    private var allOpenRouterModels: [EnabledLLM] {
        enabledLLMStore.enabledModels
            .sorted { lhs, rhs in
                if lhs.modelId == DefaultModels.openRouterFast { return true }
                if rhs.modelId == DefaultModels.openRouterFast { return false }
                return (lhs.displayName.isEmpty ? lhs.modelId : lhs.displayName)
                    < (rhs.displayName.isEmpty ? rhs.modelId : rhs.displayName)
            }
    }

    private var isGPT5BaseModel: Bool {
        let id = onboardingModelId.lowercased()
        guard id.hasPrefix("gpt-5") else { return false }
        let afterPrefix = id.dropFirst(5)
        if afterPrefix.isEmpty { return true }
        if afterPrefix.first == "." { return false }
        if afterPrefix.first == "-" { return true }
        return false
    }

    private var supportsNoneReasoning: Bool {
        let id = onboardingModelId.lowercased()
        if id.hasPrefix("gpt-6") || id.hasPrefix("gpt-7") { return true }
        if id.hasPrefix("gpt-5.") { return true }
        return false
    }

    private var availableReasoningOptions: [(value: String, label: String, detail: String)] {
        if isGPT5BaseModel {
            return reasoningOptions.filter { $0.value != "none" }
        } else {
            return reasoningOptions.filter { $0.value != "minimal" }
        }
    }

    private var availableHardTaskReasoningOptions: [(value: String, label: String, detail: String)] {
        if isGPT5BaseModel {
            return reasoningOptions.filter { $0.value != "none" }
        } else {
            return reasoningOptions.filter { $0.value != "minimal" }
        }
    }

    private var isFlexProcessingCompatible: Bool {
        flexProcessingCompatibleModels.contains(onboardingModelId)
    }

    private var isPromptCacheRetentionCompatible: Bool {
        promptCacheRetentionCompatibleModels.contains(onboardingModelId)
    }
}

// MARK: - Model Pickers
private extension OnboardingModelSettingsView {
    var providerPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Interview Provider", selection: Binding(
                get: { OnboardingProvider(rawValue: onboardingProvider) ?? .openai },
                set: { onboardingProvider = $0.rawValue }
            )) {
                ForEach(OnboardingProvider.allCases, id: \.self) { provider in
                    Text(provider.displayName).tag(provider)
                }
            }
            .pickerStyle(.segmented)
            Text("Choose which AI provider powers the onboarding interview.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    var onboardingInterviewModelPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isAnthropicProvider {
                anthropicModelPickerContent
            } else {
                openAIModelPickerContent
            }
        }
        .task {
            if isAnthropicProvider && hasAnthropicKey && anthropicModels.isEmpty {
                await loadAnthropicModels()
            } else if !isAnthropicProvider && hasOpenAIKey && interviewModels.isEmpty {
                await loadInterviewModels()
            }
        }
        .onChange(of: onboardingProvider) { _, newProvider in
            if newProvider == "anthropic" && hasAnthropicKey && anthropicModels.isEmpty {
                Task { await loadAnthropicModels() }
            } else if newProvider == "openai" && hasOpenAIKey && interviewModels.isEmpty {
                Task { await loadInterviewModels() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .apiKeysChanged)) { _ in
            if isAnthropicProvider && hasAnthropicKey && anthropicModels.isEmpty {
                Task { await loadAnthropicModels() }
            } else if !isAnthropicProvider && hasOpenAIKey && interviewModels.isEmpty {
                Task { await loadInterviewModels() }
            }
        }
    }

    @ViewBuilder
    var anthropicModelPickerContent: some View {
        if !hasAnthropicKey {
            Label("Add Anthropic API key to enable interview model selection.", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.callout)
        } else if isLoadingAnthropicModels {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading Claude models...")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } else if let error = anthropicModelError {
            VStack(alignment: .leading, spacing: 4) {
                Label("Failed to load models", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Retry") {
                    Task { await loadAnthropicModels() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        } else if filteredAnthropicModels.isEmpty {
            HStack {
                Text("No Claude models available")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Load Models") {
                    Task { await loadAnthropicModels() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        } else {
            Picker("Interview Model", selection: $onboardingAnthropicModelId) {
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

    @ViewBuilder
    var openAIModelPickerContent: some View {
        if !hasOpenAIKey {
            Label("Add OpenAI API key to enable interview model selection.", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.callout)
        } else if isLoadingInterviewModels {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading interview models...")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } else if let error = interviewModelError {
            VStack(alignment: .leading, spacing: 4) {
                Label("Failed to load models", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Retry") {
                    Task { await loadInterviewModels() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        } else if filteredInterviewModels.isEmpty {
            HStack {
                Text("No GPT-5/6/7 models available")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Load Models") {
                    Task { await loadInterviewModels() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        } else {
            Picker("Interview Model", selection: $onboardingModelId) {
                ForEach(filteredInterviewModels, id: \.id) { model in
                    Text(model.id).tag(model.id)
                }
            }
            .pickerStyle(.menu)
            Text("GPT-5 requires \"Minimal\" reasoning; GPT-5.1+ supports \"None\".")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    var pdfExtractionModelPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !hasGeminiKey {
                Label("Add Google Gemini API key to enable native PDF extraction.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)
            } else if isLoadingGeminiModels {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading Gemini models...")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else if let error = geminiModelError {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Failed to load models", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.callout)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Retry") {
                        Task { await loadGeminiModels() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } else if geminiModels.isEmpty {
                HStack {
                    Text("No Gemini models available")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("Load Models") {
                        Task { await loadGeminiModels() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } else {
                Picker("PDF Extraction Model", selection: $pdfExtractionModelId) {
                    ForEach(geminiModels.filter { $0.outputTokenLimit >= 64000 }) { model in
                        Text(model.displayName)
                            .tag(model.id)
                    }
                }
                .pickerStyle(.menu)
                Text("Uses Google's Files API for native PDF processing up to 2GB.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            if hasGeminiKey && geminiModels.isEmpty {
                await loadGeminiModels()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .apiKeysChanged)) { _ in
            if hasGeminiKey && geminiModels.isEmpty {
                Task { await loadGeminiModels() }
            }
        }
    }

    var docSummaryModelPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !hasGeminiKey {
                Label("Add Google Gemini API key to enable document summarization.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)
            } else if geminiModels.isEmpty {
                HStack {
                    Text("No Gemini models available")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("Load Models") {
                        Task { await loadGeminiModels() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } else {
                Picker("Doc Summary Model", selection: $docSummaryModelId) {
                    ForEach(geminiModels.filter { $0.outputTokenLimit >= 64000 }) { model in
                        Text(model.displayName)
                            .tag(model.id)
                    }
                }
                .pickerStyle(.menu)
                Text("Generates summaries of uploaded documents. Flash-Lite recommended for cost.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Picker("Card Merge Model", selection: $cardMergeModelId) {
                    ForEach(allOpenRouterModels.filter { $0.supportsStructuredOutput }, id: \.modelId) { model in
                        Text(model.displayName)
                            .tag(model.modelId)
                    }
                }
                .pickerStyle(.menu)
                Text("Merges card inventories across documents. GPT-5+ recommended for 128K output tokens.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Picker("Narrative Dedupe Model", selection: $narrativeDedupeModelId) {
                    ForEach(allOpenRouterModels.filter { $0.supportsStructuredOutput }, id: \.modelId) { model in
                        Text(model.displayName)
                            .tag(model.modelId)
                    }
                }
                .pickerStyle(.menu)
                Text("LLM-powered deduplication of narrative cards. Requires structured output.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    var skillExtractionModelPickers: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !hasGeminiKey {
                Label("Add Google Gemini API key to enable skill/narrative extraction.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)
            } else if geminiModels.isEmpty {
                HStack {
                    Text("No Gemini models available")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("Load Models") {
                        Task { await loadGeminiModels() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } else {
                Picker("Skill Bank Model", selection: $skillBankModelId) {
                    ForEach(geminiModels.filter { $0.outputTokenLimit >= 16000 }) { model in
                        Text(model.displayName)
                            .tag(model.id)
                    }
                }
                .pickerStyle(.menu)
                Text("Extracts comprehensive skill inventories. Flash recommended for speed.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Picker("Narrative Card Model", selection: $kcExtractionModelId) {
                    ForEach(geminiModels.filter { $0.outputTokenLimit >= 32000 }) { model in
                        Text(model.displayName)
                            .tag(model.id)
                    }
                }
                .pickerStyle(.menu)
                Text("Generates narrative knowledge cards. Pro recommended for quality.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Picker("Guidance Extraction Model", selection: $guidanceExtractionModelId) {
                    ForEach(geminiModels.filter { $0.outputTokenLimit >= 4000 }) { model in
                        Text(model.displayName)
                            .tag(model.id)
                    }
                }
                .pickerStyle(.menu)
                Text("Extracts identity vocabulary and title sets. Flash recommended.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    var voiceAndMetadataModelPickers: some View {
        VStack(alignment: .leading, spacing: 8) {
            if allOpenRouterModels.isEmpty {
                Label("Enable OpenRouter models to configure voice/metadata extraction.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)
            } else {
                Picker("Voice Primer Model", selection: $voicePrimerModelId) {
                    ForEach(allOpenRouterModels, id: \.modelId) { model in
                        Text(model.displayName.isEmpty ? model.modelId : model.displayName)
                            .tag(model.modelId)
                    }
                }
                .pickerStyle(.menu)
                Text("Extracts voice characteristics from writing samples. Fast model recommended.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Picker("KC Agent Model", selection: $kcAgentModelId) {
                    ForEach(allOpenRouterModels, id: \.modelId) { model in
                        Text(model.displayName.isEmpty ? model.modelId : model.displayName)
                            .tag(model.modelId)
                    }
                }
                .pickerStyle(.menu)
                Text("Metadata extraction for knowledge cards. Haiku recommended for speed.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    var gitIngestModelPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            if allOpenRouterModels.isEmpty {
                Label("Enable OpenRouter models to adjust Git ingest model.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)
            } else {
                Picker("Git Ingest Model", selection: Binding(
                    get: { gitIngestModelId },
                    set: { newValue in
                        gitIngestModelId = newValue
                        _ = sanitizeGitIngestModelIfNeeded()
                    }
                )) {
                    ForEach(allOpenRouterModels, id: \.modelId) { model in
                        Text(model.displayName.isEmpty ? model.modelId : model.displayName)
                            .tag(model.modelId)
                    }
                }
                .pickerStyle(.menu)
                Text("Analyzes git repositories for coding skills during onboarding.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    var backgroundProcessingModelPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            if allOpenRouterModels.isEmpty {
                Text("No models enabled. Enable models in API Keys settings.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Background Processing Model", selection: $backgroundProcessingModelId) {
                    ForEach(allOpenRouterModels) { model in
                        Text(model.displayName.isEmpty ? model.modelId : model.displayName)
                            .tag(model.modelId)
                    }
                }
                .pickerStyle(.menu)
                .onAppear {
                    sanitizeBackgroundProcessingModelIfNeeded()
                }
                Text("Used for job requirement extraction. Fast, inexpensive models recommended.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Processing Limit Pickers
private extension OnboardingModelSettingsView {
    var knowledgeCardTokenLimitPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Stepper(value: $knowledgeCardTokenLimit, in: 2000...20000, step: 1000) {
                HStack {
                    Text("Knowledge Card Token Limit")
                    Spacer()
                    Text("\(knowledgeCardTokenLimit)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            Text("When total knowledge card tokens exceed this limit, only job-relevant cards are included.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    var maxConcurrentExtractionsPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Stepper(value: $maxConcurrentExtractions, in: 1...10) {
                HStack {
                    Text("Max Concurrent Extractions")
                    Spacer()
                    Text("\(maxConcurrentExtractions)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            Text("Maximum parallel document extractions. Higher values may hit API rate limits.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Stepper(value: $maxConcurrentPDFExtractions, in: 1...50) {
                HStack {
                    Text("PDF Vision Extraction Concurrency")
                    Spacer()
                    Text("\(maxConcurrentPDFExtractions)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            Text("Pages processed in parallel for complex PDFs. Default 30, max 50.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Divider()
                .padding(.vertical, 4)

            Toggle("Use 4-Up Composites for Judge", isOn: $pdfJudgeUseFourUp)
            Text("When enabled, combines 4 pages into each composite image for quality judging.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Picker("Judge Image Resolution", selection: $pdfJudgeDPI) {
                Text("100 DPI (Fast)").tag(100)
                Text("150 DPI (Balanced)").tag(150)
                Text("200 DPI (Quality)").tag(200)
                Text("300 DPI (Max)").tag(300)
            }
            .pickerStyle(.menu)
            Text("Resolution for sample images sent to extraction quality judge.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    var ephemeralTurnsPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Stepper(value: $ephemeralTurns, in: 1...10) {
                HStack {
                    Text("Ephemeral Content Turns")
                    Spacer()
                    Text("\(ephemeralTurns)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            Text("File contents from browsing tools are pruned after this many conversation turns.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - OpenAI Options
private extension OnboardingModelSettingsView {
    var onboardingReasoningPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Default Reasoning", selection: $onboardingReasoningEffort) {
                ForEach(availableReasoningOptions, id: \.value) { option in
                    Text(option.label).tag(option.value)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: onboardingModelId) { _, _ in
                if isGPT5BaseModel && onboardingReasoningEffort == "none" {
                    onboardingReasoningEffort = "minimal"
                } else if supportsNoneReasoning && onboardingReasoningEffort == "minimal" {
                    onboardingReasoningEffort = "none"
                }
            }
            Text("Controls reasoning depth for standard interview tasks.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Picker("Hard Task Reasoning", selection: $onboardingHardTaskReasoningEffort) {
                ForEach(availableHardTaskReasoningOptions, id: \.value) { option in
                    Text(option.label).tag(option.value)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: onboardingModelId) { _, _ in
                if isGPT5BaseModel && onboardingHardTaskReasoningEffort == "none" {
                    onboardingHardTaskReasoningEffort = "minimal"
                } else if supportsNoneReasoning && onboardingHardTaskReasoningEffort == "minimal" {
                    onboardingHardTaskReasoningEffort = "none"
                }
            }
            Text("Used for knowledge card generation and profile validation.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    var onboardingFlexProcessingToggle: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Flex Processing (50% cost savings)", isOn: $onboardingFlexProcessing)
            if onboardingFlexProcessing && !isFlexProcessingCompatible {
                Label("Not supported by \(onboardingModelId)", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.footnote)
            } else {
                Text("Variable latency for non-time-critical tasks like document ingestion.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    var onboardingPromptCacheRetentionToggle: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Extended Prompt Cache (24h)", isOn: $onboardingPromptCacheRetention)
            if onboardingPromptCacheRetention && !isPromptCacheRetentionCompatible {
                Label("Not supported by \(onboardingModelId)", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.footnote)
            } else {
                Text("Extends cache lifetime for longer interview sessions.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Model Loading
private extension OnboardingModelSettingsView {
    @MainActor
    func loadInterviewModels() async {
        guard let apiKey = APIKeyManager.get(.openAI), !apiKey.isEmpty else {
            interviewModelError = "OpenAI API key not configured"
            return
        }
        isLoadingInterviewModels = true
        interviewModelError = nil
        do {
            let service = OpenAIServiceFactory.service(apiKey: apiKey)
            let response = try await service.listModels()
            interviewModels = response.data
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
            if !filteredAnthropicModels.contains(where: { $0.id == onboardingAnthropicModelId }) {
                if let first = filteredAnthropicModels.first {
                    onboardingAnthropicModelId = first.id
                }
            }
        } catch {
            anthropicModelError = error.localizedDescription
        }
        isLoadingAnthropicModels = false
    }

    @MainActor
    func loadGeminiModels() async {
        isLoadingGeminiModels = true
        geminiModelError = nil
        do {
            geminiModels = try await googleAIService.fetchAvailableModels()
            if !geminiModels.contains(where: { $0.id == pdfExtractionModelId }) {
                if let first = geminiModels.first {
                    pdfExtractionModelId = first.id
                }
            }
        } catch {
            geminiModelError = error.localizedDescription
        }
        isLoadingGeminiModels = false
    }
}

// MARK: - Model Sanitization
private extension OnboardingModelSettingsView {
    @discardableResult
    func sanitizePDFExtractionModelIfNeeded() -> String {
        let ids = geminiModels.map(\.id)
        guard !ids.isEmpty else { return pdfExtractionModelId }
        let (sanitized, adjusted) = ModelPreferenceValidator.sanitize(
            requested: pdfExtractionModelId,
            available: ids,
            fallback: pdfExtractionFallbackModelId
        )
        if adjusted {
            pdfExtractionModelId = sanitized
        }
        return sanitized
    }

    @discardableResult
    func sanitizeGitIngestModelIfNeeded() -> String {
        let ids = allOpenRouterModels.map(\.modelId)
        let fallback = DefaultModels.openRouter
        let (sanitized, adjusted) = ModelPreferenceValidator.sanitize(
            requested: gitIngestModelId,
            available: ids,
            fallback: fallback
        )
        if adjusted {
            gitIngestModelId = sanitized
        }
        return sanitized
    }

    @discardableResult
    func sanitizeBackgroundProcessingModelIfNeeded() -> String {
        let ids = allOpenRouterModels.map(\.modelId)
        guard !ids.isEmpty else { return backgroundProcessingModelId }
        let fallback = DefaultModels.openRouterFast
        let (sanitized, adjusted) = ModelPreferenceValidator.sanitize(
            requested: backgroundProcessingModelId,
            available: ids,
            fallback: fallback
        )
        if adjusted {
            backgroundProcessingModelId = sanitized
        }
        return sanitized
    }
}
