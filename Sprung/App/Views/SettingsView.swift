// Sprung/App/Views/SettingsView.swift
import SwiftUI
import SwiftData
struct SettingsView: View {
    @AppStorage("fixOverflowMaxIterations") private var fixOverflowMaxIterations: Int = 3
    @AppStorage("reasoningEffort") private var reasoningEffort: String = "medium"
    @AppStorage("onboardingInterviewDefaultModelId") private var onboardingModelId: String = "gpt-5"
    @AppStorage("onboardingPDFExtractionModelId") private var pdfExtractionModelId: String = "google/gemini-2.0-flash-001"
    @AppStorage("onboardingGitIngestModelId") private var gitIngestModelId: String = "openai/gpt-4o-mini"
    @AppStorage("onboardingInterviewAllowWebSearchDefault") private var onboardingWebSearchAllowed: Bool = true
    @AppStorage("onboardingInterviewAllowWritingAnalysisDefault") private var onboardingWritingAllowed: Bool = false
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
    private let dataResetService = DataResetService()
    private let pdfExtractionFallbackModelId = "google/gemini-2.0-flash-001"

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
            Section(content: {
                APIKeysSettingsView()
            }, header: {
                SettingsSectionHeader(title: "API Keys", systemImage: "key.2.on.ring")
            })
            Section(content: {
                Picker("Reasoning Effort", selection: $reasoningEffort) {
                    ForEach(reasoningOptions, id: \.value) { option in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.label)
                                .fontWeight(.semibold)
                            Text(option.detail)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        .tag(option.value)
                    }
                }
                .pickerStyle(.radioGroup)
                Stepper(value: $fixOverflowMaxIterations, in: 1 ... 10) {
                    Text("Fix Overflow Attempts: \(fixOverflowMaxIterations)")
                }
                Text("Controls how many times the AI will attempt to correct overflowing resume sections when using 'Fix Overflow'.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }, header: {
                SettingsSectionHeader(title: "AI Reasoning", systemImage: "sparkles")
            })
            Section(content: {
                onboardingInterviewModelPicker
                pdfExtractionModelPicker
                gitIngestModelPicker
                Toggle("Allow web search during interviews by default", isOn: Binding(
                    get: { onboardingWebSearchAllowed },
                    set: { newValue in
                        onboardingWebSearchAllowed = newValue
                        onboardingWebSearchAllowed = newValue
                    }
                ))
                .toggleStyle(.switch)
                Toggle("Allow writing-style analysis by default", isOn: Binding(
                    get: { onboardingWritingAllowed },
                    set: { newValue in
                        onboardingWritingAllowed = newValue
                        onboardingWritingAllowed = newValue
                    }
                ))
                .toggleStyle(.switch)
                Divider()
                    .padding(.vertical, 8)
                onboardingReasoningPicker
                onboardingFlexProcessingToggle
                onboardingPromptCacheRetentionToggle
            }, header: {
                SettingsSectionHeader(title: "Onboarding Interview", systemImage: "wand.and.stars")
            })
            Section(content: {
                TextToSpeechSettingsView()
            }, header: {
                SettingsSectionHeader(title: "Voice & Audio", systemImage: "speaker.wave.2.fill")
            })
            Section(content: {
                DebugSettingsView()
            }, header: {
                SettingsSectionHeader(title: "Debugging", systemImage: "wrench.and.screwdriver")
            })
            Section(content: {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Resetting will permanently delete all your data, including:")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 6) {
                        Label("All resumes and cover letters", systemImage: "doc.fill")
                            .font(.callout)
                        Label("Job application records", systemImage: "briefcase.fill")
                            .font(.callout)
                        Label("Interview data and artifacts", systemImage: "wand.and.stars.inverse")
                            .font(.callout)
                        Label("User profile information", systemImage: "person.fill")
                            .font(.callout)
                        Label("All settings and preferences", systemImage: "gear")
                            .font(.callout)
                    }
                    .foregroundStyle(.orange)
                    Button(action: { showFactoryResetConfirmation = true }) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text("Factory Reset")
                            Spacer()
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .disabled(isResetting)
                }
                .padding(.vertical, 4)
            }, header: {
                SettingsSectionHeader(title: "Danger Zone", systemImage: "exclamationmark.octagon.fill")
            })
        }
        .formStyle(.grouped)
        .frame(minWidth: 520, idealWidth: 680, maxWidth: 780,
               minHeight: 480, idealHeight: 640, maxHeight: .infinity)
        .padding(.vertical, 12)
        .alert("⚠️ Factory Reset", isPresented: $showFactoryResetConfirmation, actions: {
            Button("Cancel", role: .cancel) {
                showFactoryResetConfirmation = false
            }
            Button("Continue to Confirmation", role: .destructive) {
                showFinalResetConfirmation = true
            }
        }, message: {
            Text("This will permanently delete all resumes, cover letters, job applications, user profile data, and settings. This action cannot be undone.\n\nAre you sure?")
        })
        .alert("🔴 Confirm Factory Reset", isPresented: $showFinalResetConfirmation, actions: {
            Button("Cancel", role: .cancel) {
                showFinalResetConfirmation = false
            }
            Button("Yes, Reset Everything", role: .destructive) {
                Task {
                    await performReset()
                }
            }
        }, message: {
            Text("This is your final chance to cancel. Once confirmed, all data will be deleted and the app will restart.")
        })
        .task {
            sanitizePDFExtractionModelIfNeeded()
            sanitizeGitIngestModelIfNeeded()
        }
        .onChange(of: enabledLLMStore.enabledModels.map(\.modelId)) { _, _ in
            sanitizePDFExtractionModelIfNeeded()
            sanitizeGitIngestModelIfNeeded()
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
            // Brief delay before exiting to allow UI to update
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            // Exit the app cleanly - user can relaunch
            NSApplication.shared.terminate(nil)
        } catch {
            resetError = error.localizedDescription
        }
    }
}
private struct SettingsSectionHeader: View {
    let title: String
    let systemImage: String
    var body: some View {
        Label {
            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
        } icon: {
            Image(systemName: systemImage)
                .symbolRenderingMode(.monochrome)
                .imageScale(.medium)
        }
        .foregroundStyle(.primary)
    }
}
private extension SettingsView {
    var onboardingInterviewModelPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Default Interview Model", selection: $onboardingModelId) {
                ForEach(onboardingInterviewModelOptions, id: \.id) { model in
                    Text(model.name).tag(model.id)
                }
            }
            .pickerStyle(.menu)
            Text("GPT-5 and GPT-5.1 models supported. Note: GPT-5 requires \"Minimal\" reasoning (no \"None\"), while GPT-5.1 supports \"None\" (no \"Minimal\").")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
    }
    var pdfExtractionModelPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            if allOpenRouterModels.isEmpty {
                Label("Enable OpenRouter models in Options… before adjusting the PDF extraction model.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)
            } else {
                Picker("PDF Extraction Model", selection: Binding(
                    get: { pdfExtractionModelId },
                    set: { newValue in
                        pdfExtractionModelId = newValue
                        _ = sanitizePDFExtractionModelIfNeeded()
                    }
                )) {
                    ForEach(allOpenRouterModels, id: \.modelId) { model in
                        Text(model.displayName.isEmpty ? model.modelId : model.displayName)
                            .tag(model.modelId)
                    }
                }
                .pickerStyle(.menu)
                Text("Model used to extract structured data from resume PDFs. Gemini 2.0 Flash is recommended for cost-effective multimodal extraction.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
    }

    var gitIngestModelPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            if allOpenRouterModels.isEmpty {
                Label("Enable OpenRouter models in Options… before adjusting the Git ingest model.", systemImage: "exclamationmark.triangle.fill")
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
                Text("Model used to analyze git repositories for coding skills and achievements. Runs asynchronously during Phase 2.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
    }

    /// Returns true if the selected model is GPT-5 (not 5.1)
    var isGPT5Model: Bool {
        let id = onboardingModelId.lowercased()
        return id.hasPrefix("gpt-5") && !id.hasPrefix("gpt-5.1")
    }

    /// Returns true if the selected model is GPT-5.1
    var isGPT51Model: Bool {
        onboardingModelId.lowercased().hasPrefix("gpt-5.1")
    }

    /// Filters reasoning options based on selected model family
    var availableReasoningOptions: [(value: String, label: String, detail: String)] {
        if isGPT5Model {
            // GPT-5: minimal, low, medium, high (NO "none")
            return reasoningOptions.filter { $0.value != "none" }
        } else {
            // GPT-5.1: none, low, medium, high (NO "minimal")
            return reasoningOptions.filter { $0.value != "minimal" }
        }
    }

    /// Filters hard task reasoning options based on selected model family
    var availableHardTaskReasoningOptions: [(value: String, label: String, detail: String)] {
        if isGPT5Model {
            // GPT-5: minimal, low, medium, high
            return reasoningOptions.filter { $0.value != "none" }
        } else {
            // GPT-5.1: low, medium, high (exclude none for hard tasks)
            return reasoningOptions.filter { $0.value != "none" && $0.value != "minimal" }
        }
    }

    var onboardingReasoningPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Default Reasoning Effort", selection: $onboardingReasoningEffort) {
                ForEach(availableReasoningOptions, id: \.value) { option in
                    Text(option.label).tag(option.value)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: onboardingModelId) { _, _ in
                // Auto-adjust reasoning if current selection is incompatible
                if isGPT5Model && onboardingReasoningEffort == "none" {
                    onboardingReasoningEffort = "minimal"
                } else if isGPT51Model && onboardingReasoningEffort == "minimal" {
                    onboardingReasoningEffort = "none"
                }
            }
            Text("Controls how much the model \"thinks\" before responding. Higher effort improves quality but increases latency and cost.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            Picker("Hard Task Reasoning Effort", selection: $onboardingHardTaskReasoningEffort) {
                ForEach(availableHardTaskReasoningOptions, id: \.value) { option in
                    Text(option.label).tag(option.value)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: onboardingModelId) { _, _ in
                // Auto-adjust hard task reasoning if current selection is incompatible
                // Default to "medium" for both model families
                if isGPT5Model && (onboardingHardTaskReasoningEffort == "none") {
                    onboardingHardTaskReasoningEffort = "medium"
                } else if isGPT51Model && onboardingHardTaskReasoningEffort == "minimal" {
                    onboardingHardTaskReasoningEffort = "medium"
                }
            }
            Text("Used for complex operations like knowledge card generation and profile validation.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
    }

    var onboardingFlexProcessingToggle: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Use Flex Processing (50% cost savings)", isOn: $onboardingFlexProcessing)
                .toggleStyle(.switch)
            Text("Flex tier offers 50% lower cost with variable latency. Requests may be delayed during high-traffic periods. Best for non-time-critical tasks like document ingestion.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
    }

    /// Whether the selected model supports extended prompt cache retention
    var isPromptCacheRetentionCompatible: Bool {
        promptCacheRetentionCompatibleModels.contains(onboardingModelId)
    }

    var onboardingPromptCacheRetentionToggle: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Extended Prompt Cache Retention (24h)", isOn: $onboardingPromptCacheRetention)
                .toggleStyle(.switch)
            if onboardingPromptCacheRetention && !isPromptCacheRetentionCompatible {
                Label("Not supported by \(onboardingModelId). Will be ignored.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
                    .padding(.top, 4)
            } else {
                Text("Extends prompt cache lifetime to 24 hours (vs default 5-10 min). Improves cache hits for longer interview sessions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
    }

    var allOpenRouterModels: [EnabledLLM] {
        enabledLLMStore.enabledModels
            .sorted { lhs, rhs in
                // Sort Gemini 2.0 Flash first, then alphabetically
                if lhs.modelId == "google/gemini-2.0-flash-001" { return true }
                if rhs.modelId == "google/gemini-2.0-flash-001" { return false }
                return (lhs.displayName.isEmpty ? lhs.modelId : lhs.displayName)
                    < (rhs.displayName.isEmpty ? rhs.modelId : rhs.displayName)
            }
    }
    @discardableResult
    func sanitizePDFExtractionModelIfNeeded() -> String {
        let ids = allOpenRouterModels.map(\.modelId)
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
        let fallback = "openai/gpt-4o-mini"
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
