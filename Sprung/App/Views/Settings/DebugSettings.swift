//
//  DebugSettingsView.swift
//  Sprung
//
//  Created by Christopher Culbreath on 5/13/25.
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Save debug files to Downloads", isOn: saveDebugPromptsBinding)
                .toggleStyle(.switch)
                .help("When enabled, key debug transcripts and payloads are written to ~/Downloads for later analysis.")

            VStack(alignment: .leading, spacing: 6) {
                Text("Debug Log Level")
                    .font(.headline)
                    .fontWeight(.semibold)
                Picker("Debug Log Level", selection: logLevelBinding) {
                    ForEach(DebugSettingsStore.LogLevelSetting.allCases) { level in
                        Text(level.title).tag(level)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 260)
            }

            Text("These controls adjust diagnostic output and optional log file saving. Debug files can include sensitive request payloads.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
