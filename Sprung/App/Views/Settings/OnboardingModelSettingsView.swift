//
//  OnboardingModelSettingsView.swift
//  Sprung
//
//
import SwiftUI
import SwiftOpenAI

struct OnboardingModelSettingsView: View {
    @AppStorage("onboardingAnthropicModelId") private var onboardingAnthropicModelId: String = "claude-sonnet-4-20250514"
    @AppStorage("seedGenerationModelId") private var seedGenerationModelId: String = "anthropic/claude-sonnet-4"
    @AppStorage("seedGenerationBackend") private var seedGenerationBackend: String = "anthropic"
    @AppStorage("onboardingPDFExtractionModelId") private var pdfExtractionModelId: String = "gemini-2.5-flash"
    @AppStorage("onboardingGitIngestModelId") private var gitIngestModelId: String = "anthropic/claude-haiku-4.5"
    @AppStorage("onboardingDocSummaryModelId") private var docSummaryModelId: String = "gemini-2.5-flash-lite"
    @AppStorage("onboardingCardMergeModelId") private var cardMergeModelId: String = "openai/gpt-5"
    @AppStorage("skillBankModelId") private var skillBankModelId: String = "gemini-2.5-flash"
    @AppStorage("kcExtractionModelId") private var kcExtractionModelId: String = "gemini-2.5-pro"
    @AppStorage("guidanceExtractionModelId") private var guidanceExtractionModelId: String = "gemini-2.5-flash"
    @AppStorage("skillsProcessingModelId") private var skillsProcessingModelId: String = "gemini-2.5-flash"
    @AppStorage("skillsProcessingParallelAgents") private var skillsProcessingParallelAgents: Int = 12
    @AppStorage("voicePrimerExtractionModelId") private var voicePrimerModelId: String = "openai/gpt-4o-mini"
    @AppStorage("onboardingKCAgentModelId") private var kcAgentModelId: String = "anthropic/claude-haiku-4.5"
    @AppStorage("onboardingInterviewAllowWebSearchDefault") private var onboardingWebSearchAllowed: Bool = true
    @AppStorage("backgroundProcessingModelId") private var backgroundProcessingModelId: String = "google/gemini-2.0-flash-001"
    @AppStorage("knowledgeCardTokenLimit") private var knowledgeCardTokenLimit: Int = 8000
    @AppStorage("onboardingMaxConcurrentExtractions") private var maxConcurrentExtractions: Int = 5
    @AppStorage("maxConcurrentPDFExtractions") private var maxConcurrentPDFExtractions: Int = 30
    @AppStorage("pdfJudgeUseFourUp") private var pdfJudgeUseFourUp: Bool = false
    @AppStorage("pdfJudgeDPI") private var pdfJudgeDPI: Int = 150
    @AppStorage("onboardingEphemeralTurns") private var ephemeralTurns: Int = 15

    @Environment(EnabledLLMStore.self) private var enabledLLMStore
    @Environment(LLMFacade.self) private var llmFacade

    @State private var geminiModels: [GoogleAIService.GeminiModel] = []
    @State private var isLoadingGeminiModels = false
    @State private var geminiModelError: String?
    @State private var anthropicModels: [AnthropicModel] = []
    @State private var isLoadingAnthropicModels = false
    @State private var anthropicModelError: String?

    private let googleAIService = GoogleAIService()
    private let pdfExtractionFallbackModelId = DefaultModels.gemini

    var body: some View {
        Form {
            Section {
                anthropicModelPickerContent
            } header: {
                SettingsSectionHeader(title: "Interview Model", systemImage: "bubble.left.and.bubble.right")
            }

            Section {
                seedGenerationSettings
            } header: {
                SettingsSectionHeader(title: "Experience Defaults Generation", systemImage: "wand.and.stars")
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
        }
        .formStyle(.grouped)
        .task {
            if hasAnthropicKey && anthropicModels.isEmpty {
                await loadAnthropicModels()
            }
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
}

// MARK: - Model Pickers
private extension OnboardingModelSettingsView {
    @ViewBuilder
    var seedGenerationSettings: some View {
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
                if !hasAnthropicKey {
                    Label("Add Anthropic API key to use direct Anthropic backend.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.callout)
                } else if filteredAnthropicModels.isEmpty {
                    HStack {
                        Text("Loading models...")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        ProgressView()
                            .controlSize(.small)
                    }
                } else {
                    Picker("Model", selection: $seedGenerationModelId) {
                        ForEach(filteredAnthropicModels) { model in
                            Text(model.displayName).tag(model.id)
                        }
                    }
                    .pickerStyle(.menu)
                }
            } else {
                Picker("Model", selection: $seedGenerationModelId) {
                    ForEach(allOpenRouterModels, id: \.modelId) { model in
                        Text(model.displayName.isEmpty ? model.modelId : model.displayName)
                            .tag(model.modelId)
                    }
                }
                .pickerStyle(.menu)
            }

            Text("Generates professional descriptions for work history, education, and projects after onboarding.")
                .font(.footnote)
                .foregroundStyle(.secondary)
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
                    ForEach(allOpenRouterModels, id: \.modelId) { model in
                        Text(model.displayName.isEmpty ? model.modelId : model.displayName)
                            .tag(model.modelId)
                    }
                }
                .pickerStyle(.menu)
                Text("Card deduplication and experience defaults generation.")
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

                Picker("Inference Guidance Generation Model", selection: $guidanceExtractionModelId) {
                    ForEach(geminiModels.filter { $0.outputTokenLimit >= 4000 }) { model in
                        Text(model.displayName)
                            .tag(model.id)
                    }
                }
                .pickerStyle(.menu)
                Text("Generates identity vocabulary, title sets, and voice profiles. Flash recommended.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Divider()
                    .padding(.vertical, 4)

                Picker("Skills Processing Model", selection: $skillsProcessingModelId) {
                    ForEach(geminiModels.filter { $0.outputTokenLimit >= 64000 }) { model in
                        Text(model.displayName)
                            .tag(model.id)
                    }
                }
                .pickerStyle(.menu)
                Text("Deduplicates skills and generates ATS synonym variants. Flash recommended.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

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
            Stepper(value: $ephemeralTurns, in: 0...30) {
                HStack {
                    Text("Context Pruning Turns")
                    Spacer()
                    Text(ephemeralTurns == 0 ? "Disabled" : "\(ephemeralTurns)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            Text(ephemeralTurns == 0
                ? "File contents retained for entire agent session (uses full context window)."
                : "File contents pruned after \(ephemeralTurns) turns. Set to 0 to disable and use full context.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Model Loading
private extension OnboardingModelSettingsView {
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
