//
//  OnboardingProcessingSettingsView.swift
//  Sprung
//
//  Processing limits and interview settings for onboarding.
//  Model pickers have been moved to ModelsSettingsView.
//

import SwiftUI

struct OnboardingProcessingSettingsView: View {
    @AppStorage("onboardingMaxConcurrentExtractions") private var maxConcurrentExtractions: Int = 5
    @AppStorage("onboardingEphemeralTurns") private var ephemeralTurns: Int = 15
    @AppStorage("onboardingInterviewAllowWebSearchDefault") private var onboardingWebSearchAllowed: Bool = true
    @AppStorage("reasoningEffort") private var reasoningEffort: String = "medium"

    private let reasoningOptions: [(value: String, label: String, detail: String)] = [
        ("none", "None", "Fastest responses, no reasoning tokens"),
        ("minimal", "Minimal", "Lightweight reasoning"),
        ("low", "Low", "Light reasoning for moderately complex tasks"),
        ("medium", "Medium", "Balanced speed and reasoning depth"),
        ("high", "High", "Maximum reasoning; best for complex tasks"),
        ("xhigh", "Extra High", "GPT-5.2+ only; deepest reasoning for the hardest tasks")
    ]

    var body: some View {
        Form {
            Section {
                maxConcurrentExtractionsPicker
                ephemeralTurnsPicker
                Toggle("Allow web search during interviews", isOn: $onboardingWebSearchAllowed)
            } header: {
                SettingsSectionHeader(title: "Processing Limits", systemImage: "slider.horizontal.3")
            }

            Section {
                reasoningEffortPicker
            } header: {
                SettingsSectionHeader(title: "AI Reasoning", systemImage: "brain")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Pickers

    private var reasoningEffortPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("OpenRouter Reasoning Effort", selection: $reasoningEffort) {
                ForEach(reasoningOptions, id: \.value) { option in
                    Text(option.label).tag(option.value)
                }
            }
            .pickerStyle(.menu)
            Text("Controls reasoning depth for knowledge-card refinement, skills-bank processing, and voice-profile generation.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var maxConcurrentExtractionsPicker: some View {
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
        }
    }

    private var ephemeralTurnsPicker: some View {
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
