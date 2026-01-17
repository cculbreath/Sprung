//
//  OnboardingProcessingSettingsView.swift
//  Sprung
//
//  Processing limits and interview settings for onboarding.
//  Model pickers have been moved to ModelsSettingsView.
//

import SwiftUI

struct OnboardingProcessingSettingsView: View {
    @AppStorage("knowledgeCardTokenLimit") private var knowledgeCardTokenLimit: Int = 8000
    @AppStorage("onboardingMaxConcurrentExtractions") private var maxConcurrentExtractions: Int = 5
    @AppStorage("maxConcurrentPDFExtractions") private var maxConcurrentPDFExtractions: Int = 30
    @AppStorage("pdfJudgeUseFourUp") private var pdfJudgeUseFourUp: Bool = false
    @AppStorage("pdfJudgeDPI") private var pdfJudgeDPI: Int = 150
    @AppStorage("onboardingEphemeralTurns") private var ephemeralTurns: Int = 15
    @AppStorage("onboardingInterviewAllowWebSearchDefault") private var onboardingWebSearchAllowed: Bool = true

    var body: some View {
        Form {
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
    }

    // MARK: - Pickers

    private var knowledgeCardTokenLimitPicker: some View {
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
