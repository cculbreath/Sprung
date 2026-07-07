//
//  ResumeSettingsSection.swift
//  Sprung
//
//
import SwiftUI

struct ResumeSettingsSection: View {
    @Environment(DebugSettingsStore.self) private var debugSettings
    @AppStorage("enableResumeCustomizationTools") private var enableResumeCustomizationTools: Bool = true
    @AppStorage("enableCoherencePass") private var enableCoherencePass: Bool = true

    private var customizationReasoningEffortBinding: Binding<DebugSettingsStore.ReasoningEffortLevel> {
        Binding(
            get: { debugSettings.customizationReasoningEffort },
            set: { debugSettings.customizationReasoningEffort = $0 }
        )
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Customization Reasoning", selection: customizationReasoningEffortBinding) {
                        ForEach(DebugSettingsStore.ReasoningEffortLevel.allCases) { level in
                            Text(level.title).tag(level)
                        }
                    }
                    .pickerStyle(.menu)
                    Text("Enables extended thinking during resume customization. Shows live reasoning in the review queue. On Opus 4.6, thinking depth is adaptive regardless of effort level.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Toggle("AI Follow-up Questions", isOn: $enableResumeCustomizationTools)
                    Text("Allow AI to ask clarifying questions about your experience during resume customization.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Coherence Check", isOn: $enableCoherencePass)
                    Text("Run a final quality check after customization to catch repetition, misalignment, and inconsistencies across sections.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                SettingsSectionHeader(title: "AI Behavior", systemImage: "brain")
            }
        }
        .formStyle(.grouped)
    }
}
