//
//  DebugSettingsView.swift
//  Sprung
//
//
import SwiftUI
struct DebugSettingsView: View {
    @Environment(DebugSettingsStore.self) private var debugSettings

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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Save debug files to Downloads", isOn: saveDebugPromptsBinding)
                .help("When enabled, key debug transcripts and payloads are written to ~/Downloads for later analysis.")

            Toggle("Show debug button in onboarding interview", isOn: showDebugButtonBinding)
                .help("When enabled, shows the ladybug button in the bottom-right corner of the onboarding interview window for viewing event logs.")

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
        }
    }
}
