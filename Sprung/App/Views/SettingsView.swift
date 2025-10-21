// Sprung/App/Views/SettingsView.swift

import SwiftUI

struct SettingsView: View {
    @AppStorage("fixOverflowMaxIterations") private var fixOverflowMaxIterations: Int = 3
    @AppStorage("reasoningEffort") private var reasoningEffort: String = "medium"
    @AppStorage("onboardingInterviewDefaultModelId") private var onboardingModelId: String = "openai/gpt-5"
    @AppStorage("onboardingInterviewAllowWebSearchDefault") private var onboardingWebSearchAllowed: Bool = true
    @AppStorage("onboardingInterviewAllowWritingAnalysisDefault") private var onboardingWritingAllowed: Bool = false

    @Environment(OnboardingInterviewService.self) private var onboardingInterviewService
    @Environment(EnabledLLMStore.self) private var enabledLLMStore

    private let reasoningOptions: [(value: String, label: String, detail: String)] = [
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

                Toggle("Allow web search during interviews by default", isOn: Binding(
                    get: { onboardingWebSearchAllowed },
                    set: { newValue in
                        onboardingWebSearchAllowed = newValue
                        onboardingInterviewService.setPreferredDefaults(
                            modelId: onboardingModelId,
                            backend: .openAI,
                            webSearchAllowed: newValue
                        )
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
        }
        .formStyle(.grouped)
        .frame(minWidth: 520, idealWidth: 680, maxWidth: 780,
               minHeight: 480, idealHeight: 640, maxHeight: .infinity)
        .padding(.vertical, 12)
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
            if openAIModels.isEmpty {
                Label("Enable OpenAI responses models in Options… before adjusting the interview model.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)
            } else {
                Picker("Default Interview Model", selection: Binding(
                    get: { onboardingModelId },
                    set: { newValue in
                        onboardingModelId = newValue
                        onboardingInterviewService.setPreferredDefaults(
                            modelId: newValue,
                            backend: .openAI,
                            webSearchAllowed: onboardingWebSearchAllowed
                        )
                    }
                )) {
                    ForEach(openAIModels, id: \.modelId) { model in
                        Text(model.displayName.isEmpty ? model.modelId : model.displayName)
                            .tag(model.modelId)
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }

    var openAIModels: [EnabledLLM] {
        enabledLLMStore.enabledModels
            .filter { $0.modelId.lowercased().hasPrefix("openai/") }
            .sorted { lhs, rhs in
                (lhs.displayName.isEmpty ? lhs.modelId : lhs.displayName)
                    < (rhs.displayName.isEmpty ? rhs.modelId : rhs.displayName)
            }
    }
}
