//
//  ResumeSettingsSection.swift
//  Sprung
//
//
import SwiftUI

struct ResumeSettingsSection: View {
    @AppStorage("fixOverflowMaxIterations") private var fixOverflowMaxIterations: Int = 3
    @AppStorage("reasoningEffort") private var reasoningEffort: String = "medium"
    @AppStorage("enableResumeCustomizationTools") private var enableResumeCustomizationTools: Bool = true
    @AppStorage("enableCoherencePass") private var enableCoherencePass: Bool = true

    private let reasoningOptions: [(value: String, label: String, detail: String)] = [
        ("none", "None", "Fastest responses, no reasoning tokens"),
        ("minimal", "Minimal", "Lightweight reasoning"),
        ("low", "Low", "Light reasoning for moderately complex tasks"),
        ("medium", "Medium", "Balanced speed and reasoning depth"),
        ("high", "High", "Maximum reasoning; best for complex tasks")
    ]

    var body: some View {
        Form {
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
