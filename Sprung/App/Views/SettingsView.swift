// Sprung/App/Views/SettingsView.swift
import SwiftUI
import SwiftData
import SwiftOpenAI
struct SettingsView: View {
    @AppStorage("fixOverflowMaxIterations") private var fixOverflowMaxIterations: Int = 3
    @AppStorage("reasoningEffort") private var reasoningEffort: String = "medium"
    @AppStorage("enableResumeCustomizationTools") private var enableResumeCustomizationTools: Bool = true
    @AppStorage("onboardingInterviewDefaultModelId") private var onboardingModelId: String = "gpt-5"
    @AppStorage("onboardingAnthropicModelId") private var onboardingAnthropicModelId: String = "claude-sonnet-4-20250514"
    @AppStorage("onboardingProvider") private var onboardingProvider: String = "openai"
    @AppStorage("onboardingPDFExtractionModelId") private var pdfExtractionModelId: String = "gemini-2.5-flash"
    @AppStorage("onboardingGitIngestModelId") private var gitIngestModelId: String = "anthropic/claude-haiku-4.5"
    @AppStorage("onboardingDocSummaryModelId") private var docSummaryModelId: String = "gemini-2.5-flash-lite"
    @AppStorage("onboardingCardMergeModelId") private var cardMergeModelId: String = "openai/gpt-5"
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
    @Environment(DiscoveryCoordinator.self) private var searchOpsCoordinator
    @Environment(\.modelContext) private var modelContext
    @State private var showFactoryResetConfirmation = false
    @State private var showFinalResetConfirmation = false
    @State private var showClearArtifactsConfirmation = false
    @State private var showClearKnowledgeCardsConfirmation = false
    @State private var showClearWritingSamplesConfirmation = false
    @State private var clearResultMessage: String?
    @State private var resetError: String?
    @State private var isResetting = false
    @State private var geminiModels: [GoogleAIService.GeminiModel] = []
    @State private var isLoadingGeminiModels = false
    @State private var geminiModelError: String?
    @State private var showSetupWizard = false
    @State private var interviewModels: [ModelObject] = []
    @State private var isLoadingInterviewModels = false
    @State private var interviewModelError: String?
    @State private var anthropicModels: [AnthropicModel] = []
    @State private var isLoadingAnthropicModels = false
    @State private var anthropicModelError: String?
    @Environment(LLMFacade.self) private var llmFacade
    private let dataResetService = DataResetService()
    private let pdfExtractionFallbackModelId = DefaultModels.gemini
    private let googleAIService = GoogleAIService()

    /// Is Anthropic selected as the onboarding provider?
    private var isAnthropicProvider: Bool {
        onboardingProvider == "anthropic"
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

    /// Filtered Anthropic models: claude-* (excluding deprecated/legacy)
    private var filteredAnthropicModels: [AnthropicModel] {
        anthropicModels
            .filter { model in
                let id = model.id.lowercased()
                // Include Claude models, exclude deprecated naming patterns
                return id.hasPrefix("claude-") && !id.contains("instant")
            }
            .sorted { $0.displayName < $1.displayName }
    }

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

    // Reasoning options differ by model family:
    // - GPT-5: minimal, low, medium, high (NO "none")
    // - GPT-5.1: none, low, medium, high (NO "minimal")
    private let reasoningOptions: [(value: String, label: String, detail: String)] = [
        ("none", "None", "GPT-5.1 only; fastest responses, no reasoning tokens"),
        ("minimal", "Minimal", "GPT-5 only; lightweight reasoning"),
        ("low", "Low", "Light reasoning for moderately complex tasks"),
        ("medium", "Medium", "Balanced speed and reasoning depth"),
        ("high", "High", "Maximum reasoning; best for complex tasks")
    ]

    var body: some View {
        Form {
            // MARK: - API Keys
            Section {
                APIKeysSettingsView()
                Button("Run Setup Wizard…") {
                    showSetupWizard = true
                }
                .buttonStyle(.bordered)
            } header: {
                SettingsSectionHeader(title: "API Keys", systemImage: "key.fill")
            }

            // MARK: - Resume & Cover Letter AI
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Reasoning Effort", selection: $reasoningEffort) {
                        ForEach(reasoningOptions, id: \.value) { option in
                            Text(option.label).tag(option.value)
                        }
                    }
                    .pickerStyle(.menu)
                    Text("Controls AI reasoning depth for resume customization and cover letter writing.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 12) {
                    Stepper(value: $fixOverflowMaxIterations, in: 1 ... 10) {
                        HStack {
                            Text("Fix Overflow Attempts")
                            Spacer()
                            Text("\(fixOverflowMaxIterations)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    Text("How many times AI will attempt to correct overflowing resume sections.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Enable AI Tools", isOn: $enableResumeCustomizationTools)
                    Text("Allow AI to query you about skills during resume customization. Requires model with tool support.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                SettingsSectionHeader(title: "Resume & Cover Letter", systemImage: "doc.text.fill")
            }

            // MARK: - Onboarding Interview
            Section {
                onboardingInterviewModelPicker
                pdfExtractionModelPicker
                docSummaryModelPicker
                skillExtractionModelPickers
                voiceAndMetadataModelPickers
                gitIngestModelPicker
                backgroundProcessingModelPicker
                knowledgeCardTokenLimitPicker
                maxConcurrentExtractionsPicker
                ephemeralTurnsPicker

                Toggle("Allow web search during interviews", isOn: $onboardingWebSearchAllowed)

                // OpenAI-specific settings (hidden when Anthropic selected)
                if !isAnthropicProvider {
                    Divider()
                        .padding(.vertical, 4)

                    onboardingReasoningPicker
                    onboardingFlexProcessingToggle
                    onboardingPromptCacheRetentionToggle
                }
            } header: {
                SettingsSectionHeader(title: "Onboarding Interview", systemImage: "wand.and.stars")
            }

            // MARK: - Search Operations
            DiscoverySettingsSection(coordinator: searchOpsCoordinator)

            // MARK: - Voice & Audio
            Section {
                TextToSpeechSettingsView()
            } header: {
                SettingsSectionHeader(title: "Voice & Audio", systemImage: "speaker.wave.2.fill")
            }

            // MARK: - Debugging
            Section {
                DebugSettingsView()
            } header: {
                SettingsSectionHeader(title: "Debugging", systemImage: "ladybug.fill")
            }

            // MARK: - Danger Zone
            Section {
                // Granular data clearing options
                VStack(alignment: .leading, spacing: 12) {
                    Text("Clear specific data types without a full reset:")
                        .font(.callout)

                    HStack(spacing: 12) {
                        Button(role: .destructive) {
                            showClearArtifactsConfirmation = true
                        } label: {
                            Label("Clear Artifacts", systemImage: "doc.badge.ellipsis")
                        }
                        .buttonStyle(.bordered)
                        .disabled(isResetting)

                        Button(role: .destructive) {
                            showClearKnowledgeCardsConfirmation = true
                        } label: {
                            Label("Clear Knowledge Cards", systemImage: "rectangle.stack.badge.minus")
                        }
                        .buttonStyle(.bordered)
                        .disabled(isResetting)

                        Button(role: .destructive) {
                            showClearWritingSamplesConfirmation = true
                        } label: {
                            Label("Clear Writing Samples", systemImage: "text.badge.minus")
                        }
                        .buttonStyle(.bordered)
                        .disabled(isResetting)
                    }

                    if let message = clearResultMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()
                    .padding(.vertical, 8)

                // Full factory reset
                VStack(alignment: .leading, spacing: 12) {
                    Text("Factory reset will permanently delete all your data:")
                        .font(.callout)
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Resumes, cover letters, and templates", systemImage: "doc.fill")
                        Label("Job application records", systemImage: "briefcase.fill")
                        Label("Interview data and artifacts", systemImage: "wand.and.stars.inverse")
                        Label("User profile information", systemImage: "person.fill")
                        Label("All settings and preferences", systemImage: "gear")
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)

                    Button(role: .destructive) {
                        showFactoryResetConfirmation = true
                    } label: {
                        Label("Factory Reset", systemImage: "exclamationmark.triangle.fill")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isResetting)
                }
            } header: {
                SettingsSectionHeader(title: "Danger Zone", systemImage: "exclamationmark.octagon.fill")
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 520, idealWidth: 680, maxWidth: 780,
               minHeight: 480, idealHeight: 700, maxHeight: .infinity)
        .alert("Factory Reset", isPresented: $showFactoryResetConfirmation) {
            Button("Cancel", role: .cancel) {
                showFactoryResetConfirmation = false
            }
            Button("Continue", role: .destructive) {
                showFinalResetConfirmation = true
            }
        } message: {
            Text("This will permanently delete all resumes, cover letters, job applications, user profile data, and settings. This action cannot be undone.")
        }
        .alert("Confirm Factory Reset", isPresented: $showFinalResetConfirmation) {
            Button("Cancel", role: .cancel) {
                showFinalResetConfirmation = false
            }
            Button("Reset Everything", role: .destructive) {
                Task {
                    await performReset()
                }
            }
        } message: {
            Text("This is your final chance to cancel. Once confirmed, all data will be deleted and the app will restart.")
        }
        .alert("Clear Artifact Records", isPresented: $showClearArtifactsConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                clearArtifactRecords()
            }
        } message: {
            Text("This will delete all uploaded documents and their extracted content. This cannot be undone.")
        }
        .alert("Clear Knowledge Cards", isPresented: $showClearKnowledgeCardsConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                clearKnowledgeCards()
            }
        } message: {
            Text("This will delete all knowledge cards generated during onboarding. This cannot be undone.")
        }
        .alert("Clear Writing Samples", isPresented: $showClearWritingSamplesConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                clearWritingSamples()
            }
        } message: {
            Text("This will delete all writing samples used for cover letter generation. This cannot be undone.")
        }
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
        .sheet(isPresented: $showSetupWizard) {
            SetupWizardView {
                showSetupWizard = false
            }
        }
    }

    private func performReset() async {
        isResetting = true
        defer { isResetting = false }
        do {
            try await dataResetService.performFactoryReset()
            resetError = ""
            try await Task.sleep(nanoseconds: 500_000_000)
            NSApplication.shared.terminate(nil)
        } catch {
            resetError = error.localizedDescription
        }
    }

    private func clearArtifactRecords() {
        do {
            let count = try dataResetService.clearArtifactRecords(context: modelContext)
            clearResultMessage = "Cleared \(count) artifact record\(count == 1 ? "" : "s")"
        } catch {
            clearResultMessage = "Error: \(error.localizedDescription)"
        }
    }

    private func clearKnowledgeCards() {
        do {
            let count = try dataResetService.clearKnowledgeCards()
            clearResultMessage = "Cleared \(count) knowledge card file\(count == 1 ? "" : "s")"
        } catch {
            clearResultMessage = "Error: \(error.localizedDescription)"
        }
    }

    private func clearWritingSamples() {
        do {
            let count = try dataResetService.clearWritingSamples(context: modelContext)
            clearResultMessage = "Cleared \(count) writing sample\(count == 1 ? "" : "s")"
        } catch {
            clearResultMessage = "Error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Section Header
private struct SettingsSectionHeader: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
            .fontWeight(.semibold)
            .foregroundStyle(.primary)
    }
}

// MARK: - Onboarding Interview Settings
private extension SettingsView {
    var onboardingInterviewModelPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isAnthropicProvider {
                // Anthropic model picker
                if !hasAnthropicKey {
                    Label("Add Anthropic API key above to enable interview model selection.", systemImage: "exclamationmark.triangle.fill")
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
            } else {
                // OpenAI model picker
                if !hasOpenAIKey {
                    Label("Add OpenAI API key above to enable interview model selection.", systemImage: "exclamationmark.triangle.fill")
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
        }
        .task {
            if isAnthropicProvider && hasAnthropicKey && anthropicModels.isEmpty {
                await loadAnthropicModels()
            } else if !isAnthropicProvider && hasOpenAIKey && interviewModels.isEmpty {
                await loadInterviewModels()
            }
        }
        .onChange(of: onboardingProvider) { _, newProvider in
            // Load appropriate models when provider changes
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

    var pdfExtractionModelPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !hasGeminiKey {
                Label("Add Google Gemini API key above to enable native PDF extraction.", systemImage: "exclamationmark.triangle.fill")
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

    private var hasGeminiKey: Bool {
        APIKeyManager.get(.gemini) != nil
    }

    private var hasOpenAIKey: Bool {
        APIKeyManager.get(.openAI) != nil
    }

    private var hasAnthropicKey: Bool {
        APIKeyManager.get(.anthropic) != nil
    }

    @MainActor
    private func loadInterviewModels() async {
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

    @MainActor
    private func loadAnthropicModels() async {
        guard hasAnthropicKey else {
            anthropicModelError = "Anthropic API key not configured"
            return
        }
        isLoadingAnthropicModels = true
        anthropicModelError = nil
        do {
            let response = try await llmFacade.anthropicListModels()
            anthropicModels = response.data
            // Validate current selection is still available
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
    private func loadGeminiModels() async {
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

    var gitIngestModelPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            if allOpenRouterModels.isEmpty {
                Label("Enable OpenRouter models in Options before adjusting Git ingest model.", systemImage: "exclamationmark.triangle.fill")
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

    var docSummaryModelPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !hasGeminiKey {
                Label("Add Google Gemini API key above to enable document summarization.", systemImage: "exclamationmark.triangle.fill")
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
                Text("Merges card inventories across documents. Models with structured output support shown. GPT-5+ recommended for 128K output tokens.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    var skillExtractionModelPickers: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !hasGeminiKey {
                Label("Add Google Gemini API key above to enable skill/narrative extraction.", systemImage: "exclamationmark.triangle.fill")
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
                Text("Extracts comprehensive skill inventories from documents. Flash recommended for speed.")
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
                Label("Enable OpenRouter models in Options to configure voice/metadata extraction.", systemImage: "exclamationmark.triangle.fill")
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

    var backgroundProcessingModelPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            if allOpenRouterModels.isEmpty {
                Text("No models enabled. Enable models in AI Settings above.")
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
                Text("Used for job requirement extraction. Fast, inexpensive models recommended (e.g., Gemini Flash).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

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
            Text("When total knowledge card tokens exceed this limit, only job-relevant cards are included in prompts.")
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
            Text("Maximum parallel document extractions during onboarding. Higher values process faster but may hit API rate limits.")
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
            Text("Pages processed in parallel when LLM vision is used for complex PDFs. Default 30, max 50. Higher values use more API quota.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Divider()
                .padding(.vertical, 4)

            // PDF Judge Settings
            Toggle("Use 4-Up Composites for Judge", isOn: $pdfJudgeUseFourUp)
            Text("When enabled, combines 4 pages into each composite image. When disabled, sends individual page images.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Picker("Judge Image Resolution", selection: $pdfJudgeDPI) {
                Text("100 DPI (Fast)").tag(100)
                Text("150 DPI (Balanced)").tag(150)
                Text("200 DPI (Quality)").tag(200)
                Text("300 DPI (Max)").tag(300)
            }
            .pickerStyle(.menu)
            Text("Resolution for sample page images sent to the extraction quality judge. Higher values improve accuracy but increase API costs.")
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
            Text("File contents from browsing tools are pruned from context after this many conversation turns to manage token usage.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
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

    /// True for base GPT-5 models (gpt-5, gpt-5-mini, etc.) that require "minimal" reasoning minimum
    var isGPT5BaseModel: Bool {
        let id = onboardingModelId.lowercased()
        // GPT-5 base models: gpt-5, gpt-5-mini, gpt-5-nano, gpt-5-pro, gpt-5-codex
        // NOT gpt-5.1+, gpt-5.2+, etc.
        guard id.hasPrefix("gpt-5") else { return false }
        // Check if it has a dot version (gpt-5.1, gpt-5.2, etc.)
        let afterPrefix = id.dropFirst(5) // Remove "gpt-5"
        if afterPrefix.isEmpty { return true } // Just "gpt-5"
        if afterPrefix.first == "." { return false } // gpt-5.x
        if afterPrefix.first == "-" { return true } // gpt-5-something
        return false
    }

    /// True for GPT-5.1+ models that support "none" reasoning
    var supportsNoneReasoning: Bool {
        let id = onboardingModelId.lowercased()
        // GPT-5.1+, GPT-6+, GPT-7+ all support "none" reasoning
        if id.hasPrefix("gpt-6") || id.hasPrefix("gpt-7") { return true }
        if id.hasPrefix("gpt-5.") { return true } // gpt-5.1, gpt-5.2, etc.
        return false
    }

    var availableReasoningOptions: [(value: String, label: String, detail: String)] {
        if isGPT5BaseModel {
            return reasoningOptions.filter { $0.value != "none" }
        } else {
            return reasoningOptions.filter { $0.value != "minimal" }
        }
    }

    var availableHardTaskReasoningOptions: [(value: String, label: String, detail: String)] {
        if isGPT5BaseModel {
            return reasoningOptions.filter { $0.value != "none" }
        } else {
            // GPT-5.1+ supports "none" as lowest reasoning level
            return reasoningOptions.filter { $0.value != "minimal" }
        }
    }

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

    var isFlexProcessingCompatible: Bool {
        flexProcessingCompatibleModels.contains(onboardingModelId)
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

    var isPromptCacheRetentionCompatible: Bool {
        promptCacheRetentionCompatibleModels.contains(onboardingModelId)
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

    var allOpenRouterModels: [EnabledLLM] {
        enabledLLMStore.enabledModels
            .sorted { lhs, rhs in
                if lhs.modelId == DefaultModels.openRouterFast { return true }
                if rhs.modelId == DefaultModels.openRouterFast { return false }
                return (lhs.displayName.isEmpty ? lhs.modelId : lhs.displayName)
                    < (rhs.displayName.isEmpty ? rhs.modelId : rhs.displayName)
            }
    }

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
}
