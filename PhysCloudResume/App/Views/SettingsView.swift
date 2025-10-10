// PhysCloudResume/App/Views/SettingsView.swift

import SwiftUI

struct SettingsView: View {
    @AppStorage("fixOverflowMaxIterations") private var fixOverflowMaxIterations: Int = 3
    @AppStorage("reasoningEffort") private var reasoningEffort: String = "medium"

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
