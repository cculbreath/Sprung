// Sprung/App/Views/SettingsView.swift

import SwiftUI
import SwiftData

struct SettingsView: View {
    @AppStorage("fixOverflowMaxIterations") private var fixOverflowMaxIterations: Int = 3
    @AppStorage("reasoningEffort") private var reasoningEffort: String = "medium"
    @AppStorage("onboardingInterviewDefaultModelId") private var onboardingModelId: String = "openai/gpt-5"
    @AppStorage("onboardingPDFExtractionModelId") private var pdfExtractionModelId: String = "google/gemini-2.0-flash-001"
    @AppStorage("onboardingInterviewAllowWebSearchDefault") private var onboardingWebSearchAllowed: Bool = true
    @AppStorage("onboardingInterviewAllowWritingAnalysisDefault") private var onboardingWritingAllowed: Bool = false

    @Environment(OnboardingInterviewService.self) private var onboardingInterviewService
    @Environment(EnabledLLMStore.self) private var enabledLLMStore
    @Environment(ApplicantProfileStore.self) private var applicantProfileStore
    @Environment(ExperienceDefaultsStore.self) private var experienceDefaultsStore
    @Environment(OnboardingArtifactStore.self) private var onboardingArtifactStore
    @Environment(CareerKeywordStore.self) private var careerKeywordStore
    @Environment(\.modelContext) private var modelContext

    @State private var showFactoryResetConfirmation = false
    @State private var showFinalResetConfirmation = false
    @State private var resetError: String?
    @State private var isResetting = false
    private let dataResetService = DataResetService()
    private let onboardingDefaultModelFallback = "openai/gpt-5"
    private let pdfExtractionFallbackModelId = "google/gemini-2.0-flash-001"

    private let reasoningOptions: [(value: String, label: String, detail: String)] = [
        ("minimal", "Minimal", "Fastest responses; rely on tools and concise reasoning"),
        ("low", "Low", "Faster responses with basic reasoning"),
        ("medium", "Medium", "Balanced speed and reasoning depth"),
        ("high", "High", "Thorough reasoning with detailed analysis"),
    ]

    var body: some View {
        Form {
            Section {
                APIKeysSettingsView()
            } header: {
                SettingsSectionHeader(title: "API Keys", systemImage: "key.2.on.ring")
            }

            Section {
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
            } header: {
                SettingsSectionHeader(title: "AI Reasoning", systemImage: "sparkles")
            }

            Section {
                onboardingInterviewModelPicker

                pdfExtractionModelPicker

                Toggle("Allow web search during interviews by default", isOn: Binding(
                    get: { onboardingWebSearchAllowed },
                    set: { newValue in
                        onboardingWebSearchAllowed = newValue
                        let sanitized = sanitizeOnboardingModelIfNeeded()
                        let resolved = onboardingInterviewService.setPreferredDefaults(
                            modelId: sanitized,
                            backend: .openAI,
                            webSearchAllowed: newValue
                        )
                        if onboardingModelId != resolved {
                            onboardingModelId = resolved
                        }
                        onboardingInterviewService.clearModelAvailabilityMessage()
                    }
                ))
                .toggleStyle(.switch)

                Toggle("Allow writing-style analysis by default", isOn: Binding(
                    get: { onboardingWritingAllowed },
                    set: { newValue in
                        onboardingWritingAllowed = newValue
                        if onboardingInterviewService.isActive {
                            onboardingInterviewService.setWritingAnalysisConsent(newValue)
                        }
                    }
                ))
                .toggleStyle(.switch)
            } header: {
                SettingsSectionHeader(title: "Onboarding Interview", systemImage: "wand.and.stars")
            }

            Section {
                TextToSpeechSettingsView()
            } header: {
                SettingsSectionHeader(title: "Voice & Audio", systemImage: "speaker.wave.2.fill")
            }

            Section {
                DebugSettingsView()
            } header: {
                SettingsSectionHeader(title: "Debugging", systemImage: "wrench.and.screwdriver")
            }

            Section {
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
            } header: {
                SettingsSectionHeader(title: "Danger Zone", systemImage: "exclamationmark.octagon.fill")
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 520, idealWidth: 680, maxWidth: 780,
               minHeight: 480, idealHeight: 640, maxHeight: .infinity)
        .padding(.vertical, 12)
        .alert("⚠️ Factory Reset", isPresented: $showFactoryResetConfirmation) {
            Button("Cancel", role: .cancel) {
                showFactoryResetConfirmation = false
            }
            Button("Continue to Confirmation", role: .destructive) {
                showFinalResetConfirmation = true
            }
        } message: {
            Text("This will permanently delete all resumes, cover letters, job applications, user profile data, and settings. This action cannot be undone.\n\nAre you sure?")
        }
        .alert("🔴 Confirm Factory Reset", isPresented: $showFinalResetConfirmation) {
            Button("Cancel", role: .cancel) {
                showFinalResetConfirmation = false
            }
            Button("Yes, Reset Everything", role: .destructive) {
                Task {
                    await performReset()
                }
            }
        } message: {
            Text("This is your final chance to cancel. Once confirmed, all data will be deleted and the app will restart.")
        }
        .task {
            sanitizeOnboardingModelIfNeeded()
            sanitizePDFExtractionModelIfNeeded()
        }
        .onChange(of: enabledLLMStore.enabledModels.map(\.modelId)) { _, _ in
            sanitizeOnboardingModelIfNeeded()
            sanitizePDFExtractionModelIfNeeded()
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
                onboardingArtifactStore: onboardingArtifactStore,
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
            if onboardingInterviewModels.isEmpty {
                Label("Enable GPT-5 in Options… to use the onboarding interview.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)
            } else {
                Picker("Default Interview Model", selection: Binding(
                    get: { onboardingModelId },
                    set: { newValue in
                        onboardingModelId = newValue
                        let sanitized = sanitizeOnboardingModelIfNeeded()
                        let resolved = onboardingInterviewService.setPreferredDefaults(
                            modelId: sanitized,
                            backend: .openAI,
                            webSearchAllowed: onboardingWebSearchAllowed
                        )
                        if onboardingModelId != resolved {
                            onboardingModelId = resolved
                        }
                        onboardingInterviewService.clearModelAvailabilityMessage()
                    }
                )) {
                    ForEach(onboardingInterviewModels, id: \.modelId) { model in
                        Text(model.displayName.isEmpty ? model.modelId : model.displayName)
                            .tag(model.modelId)
                    }
                }
                .pickerStyle(.menu)
                .disabled(onboardingInterviewModels.count == 1)

                Text("Currently, only GPT-5 is supported for onboarding interviews.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
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

    var onboardingInterviewModels: [EnabledLLM] {
        // For now, only GPT-5 is supported for onboarding interviews
        enabledLLMStore.enabledModels
            .filter { $0.modelId == "openai/gpt-5" }
    }

    var openAIModels: [EnabledLLM] {
        enabledLLMStore.enabledModels
            .filter { $0.modelId.lowercased().hasPrefix("openai/") }
            .sorted { lhs, rhs in
                (lhs.displayName.isEmpty ? lhs.modelId : lhs.displayName)
                    < (rhs.displayName.isEmpty ? rhs.modelId : rhs.displayName)
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
    func sanitizeOnboardingModelIfNeeded() -> String {
        let ids = onboardingInterviewModels.map(\.modelId)
        onboardingInterviewService.updateAvailableModelIds(ids)
        let (sanitized, adjusted) = ModelPreferenceValidator.sanitize(
            requested: onboardingModelId,
            available: ids,
            fallback: onboardingDefaultModelFallback
        )
        if adjusted {
            onboardingModelId = sanitized
        }
        return sanitized
    }

    @discardableResult
    func sanitizePDFExtractionModelIfNeeded() -> String {
        let ids = allOpenRouterModels.map(\.modelId)
        onboardingInterviewService.updateExtractionModelIds(ids)
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
}
