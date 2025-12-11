// Sprung/App/Views/SettingsView.swift
import SwiftUI
import SwiftData
struct SettingsView: View {
    @AppStorage("fixOverflowMaxIterations") private var fixOverflowMaxIterations: Int = 3
    @AppStorage("reasoningEffort") private var reasoningEffort: String = "medium"
    @AppStorage("enableResumeCustomizationTools") private var enableResumeCustomizationTools: Bool = true
    @AppStorage("onboardingInterviewDefaultModelId") private var onboardingModelId: String = "gpt-5"
    @AppStorage("onboardingPDFExtractionModelId") private var pdfExtractionModelId: String = "google/gemini-2.0-flash-001"
    @AppStorage("onboardingGitIngestModelId") private var gitIngestModelId: String = "anthropic/claude-haiku-4.5"
    @AppStorage("onboardingInterviewAllowWebSearchDefault") private var onboardingWebSearchAllowed: Bool = true
    @AppStorage("onboardingInterviewReasoningEffort") private var onboardingReasoningEffort: String = "none"
    @AppStorage("onboardingInterviewHardTaskReasoningEffort") private var onboardingHardTaskReasoningEffort: String = "medium"
    @AppStorage("onboardingInterviewFlexProcessing") private var onboardingFlexProcessing: Bool = true
    @AppStorage("onboardingInterviewPromptCacheRetention") private var onboardingPromptCacheRetention: Bool = true
    @Environment(OnboardingInterviewCoordinator.self) private var onboardingCoordinator
    @Environment(EnabledLLMStore.self) private var enabledLLMStore
    @Environment(ApplicantProfileStore.self) private var applicantProfileStore
    @Environment(ExperienceDefaultsStore.self) private var experienceDefaultsStore
    @Environment(CareerKeywordStore.self) private var careerKeywordStore
    @Environment(\.modelContext) private var modelContext
    @State private var showFactoryResetConfirmation = false
    @State private var showFinalResetConfirmation = false
    @State private var resetError: String?
    @State private var isResetting = false
    @State private var geminiModels: [GoogleAIService.GeminiModel] = []
    @State private var isLoadingGeminiModels = false
    @State private var geminiModelError: String?
    @State private var showSetupWizard = false
    private let dataResetService = DataResetService()
    private let pdfExtractionFallbackModelId = "gemini-2.0-flash"
    private let googleAIService = GoogleAIService()

    /// Available GPT-5 and GPT-5.1 models for onboarding interviews (uses OpenAI directly, not OpenRouter)
    private let onboardingInterviewModelOptions: [(id: String, name: String)] = [
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

    /// Models that support extended prompt cache retention (24h)
    private let promptCacheRetentionCompatibleModels: Set<String> = [
        "gpt-5.1", "gpt-5.1-codex", "gpt-5.1-codex-mini", "gpt-5.1-chat-latest",
        "gpt-5", "gpt-5-codex", "gpt-4.1"
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
                gitIngestModelPicker

                Toggle("Allow web search during interviews", isOn: $onboardingWebSearchAllowed)

                Divider()
                    .padding(.vertical, 4)

                onboardingReasoningPicker
                onboardingFlexProcessingToggle
                onboardingPromptCacheRetentionToggle
            } header: {
                SettingsSectionHeader(title: "Onboarding Interview", systemImage: "wand.and.stars")
            }

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
                VStack(alignment: .leading, spacing: 12) {
                    Text("Resetting will permanently delete all your data:")
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
        .task {
            sanitizePDFExtractionModelIfNeeded()
            sanitizeGitIngestModelIfNeeded()
        }
        .onChange(of: enabledLLMStore.enabledModels.map(\.modelId)) { _, _ in
            sanitizePDFExtractionModelIfNeeded()
            sanitizeGitIngestModelIfNeeded()
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
            try await dataResetService.performFactoryReset(
                modelContext: modelContext,
                applicantProfileStore: applicantProfileStore,
                experienceDefaultsStore: experienceDefaultsStore,
                enabledLLMStore: enabledLLMStore,
                careerKeywordStore: careerKeywordStore
            )
            resetError = ""
            try await Task.sleep(nanoseconds: 1_000_000_000)
            NSApplication.shared.terminate(nil)
        } catch {
            resetError = error.localizedDescription
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
            Picker("Interview Model", selection: $onboardingModelId) {
                ForEach(onboardingInterviewModelOptions, id: \.id) { model in
                    Text(model.name).tag(model.id)
                }
            }
            .pickerStyle(.menu)
            Text("GPT-5 requires \"Minimal\" reasoning; GPT-5.1 supports \"None\".")
                .font(.footnote)
                .foregroundStyle(.secondary)
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
                    ForEach(geminiModels) { model in
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

    var isGPT5Model: Bool {
        let id = onboardingModelId.lowercased()
        return id.hasPrefix("gpt-5") && !id.hasPrefix("gpt-5.1")
    }

    var isGPT51Model: Bool {
        onboardingModelId.lowercased().hasPrefix("gpt-5.1")
    }

    var availableReasoningOptions: [(value: String, label: String, detail: String)] {
        if isGPT5Model {
            return reasoningOptions.filter { $0.value != "none" }
        } else {
            return reasoningOptions.filter { $0.value != "minimal" }
        }
    }

    var availableHardTaskReasoningOptions: [(value: String, label: String, detail: String)] {
        if isGPT5Model {
            return reasoningOptions.filter { $0.value != "none" }
        } else {
            return reasoningOptions.filter { $0.value != "none" && $0.value != "minimal" }
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
                if isGPT5Model && onboardingReasoningEffort == "none" {
                    onboardingReasoningEffort = "minimal"
                } else if isGPT51Model && onboardingReasoningEffort == "minimal" {
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
                if isGPT5Model && onboardingHardTaskReasoningEffort == "none" {
                    onboardingHardTaskReasoningEffort = "medium"
                } else if isGPT51Model && onboardingHardTaskReasoningEffort == "minimal" {
                    onboardingHardTaskReasoningEffort = "medium"
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
            Text("Variable latency for non-time-critical tasks like document ingestion.")
                .font(.footnote)
                .foregroundStyle(.secondary)
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
                if lhs.modelId == "google/gemini-2.0-flash-001" { return true }
                if rhs.modelId == "google/gemini-2.0-flash-001" { return false }
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
        let fallback = "anthropic/claude-haiku-4.5"
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
