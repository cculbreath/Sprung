//
//  DebugSettingsView.swift
//  Sprung
//
//
import SwiftUI
struct DebugSettingsView: View {
    @Environment(DebugSettingsStore.self) private var debugSettings
    @Environment(SkillStore.self) private var skillStore
    @State private var tokenBudgetHardStop: Int = TokenBudgetPolicy.hardStopBudget
    @State private var showClearSkillsConfirmation = false

    private var saveDebugPromptsBinding: Binding<Bool> {
        Binding(
            get: { debugSettings.saveDebugPrompts },
            set: { debugSettings.saveDebugPrompts = $0 }
        )
    }

    private var logLevelBinding: Binding<DebugSettingsStore.LogLevelSetting> {
        Binding(
            get: { debugSettings.logLevelSetting },
            set: { debugSettings.logLevelSetting = $0 }
        )
    }

    private var showDebugButtonBinding: Binding<Bool> {
        Binding(
            get: { debugSettings.showOnboardingDebugButton },
            set: { debugSettings.showOnboardingDebugButton = $0 }
        )
    }

    private var forceQueryUserExperienceToolBinding: Binding<Bool> {
        Binding(
            get: { debugSettings.forceQueryUserExperienceTool },
            set: { debugSettings.forceQueryUserExperienceTool = $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Save debug files to Downloads", isOn: saveDebugPromptsBinding)
                .help("When enabled, key debug transcripts and payloads are written to ~/Downloads for later analysis.")

            Toggle("Show debug button in onboarding interview", isOn: showDebugButtonBinding)
                .help("When enabled, shows the ladybug button in the bottom-right corner of the onboarding interview window for viewing event logs.")

            Toggle("Force QueryUserExperienceTool in resume customization", isOn: forceQueryUserExperienceToolBinding)
                .help("When enabled, forces the LLM to use the QueryUserExperienceTool as its first response during round 2 of the customize resume workflow.")

            VStack(alignment: .leading, spacing: 8) {
                Picker("Log Level", selection: logLevelBinding) {
                    ForEach(DebugSettingsStore.LogLevelSetting.allCases) { level in
                        Text(level.title).tag(level)
                    }
                }
                .pickerStyle(.menu)
                Text("Controls diagnostic output verbosity. Debug files can include sensitive request payloads.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Divider()
                .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 8) {
                Button("Clear Skills") {
                    showClearSkillsConfirmation = true
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .disabled(skillStore.skills.isEmpty)
                .alert("Clear all skills?", isPresented: $showClearSkillsConfirmation) {
                    Button("Clear Skills", role: .destructive) {
                        let skills = skillStore.skills
                        if !skills.isEmpty {
                            skillStore.deleteAll(skills)
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This removes every skill from the local store, including onboarding and approved skills.")
                }

                Text("Deletes all skills from the local store.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Stepper(value: $tokenBudgetHardStop, in: 25_000...200_000, step: 5_000) {
                    HStack {
                        Text("PRI Reset Threshold")
                        Spacer()
                        Text("\(tokenBudgetHardStop / 1000)k tokens")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .onChange(of: tokenBudgetHardStop) { _, newValue in
                    TokenBudgetPolicy.setHardStopBudget(newValue)
                }
                Text("When input tokens exceed this threshold, the conversation thread resets to prevent runaway context. Default: 75k.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
