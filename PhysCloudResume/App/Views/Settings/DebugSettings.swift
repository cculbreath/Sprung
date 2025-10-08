//
//  DebugSettingsView.swift
//  PhysCloudResume
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
        VStack(alignment: .leading, spacing: 10) {
            Text("Debug Settings")
                .font(.headline)
                .padding(.bottom, 5)

            HStack {
                Toggle("Save Debug Files to Downloads", isOn: saveDebugPromptsBinding)
                    .toggleStyle(SwitchToggleStyle())
                    .help("When enabled, debug files will be saved to your Downloads folder")
            }
            .padding(.horizontal, 10)

            HStack {
                Text("Debug Log Level:")
                Picker("Log Level", selection: logLevelBinding) {
                    ForEach(DebugSettingsStore.LogLevelSetting.allCases) { level in
                        Text(level.title).tag(level)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .frame(width: 240)
            }
            .padding(.horizontal, 10)

            Text("These settings control debug output and file saving. Debug files may contain sensitive information such as API requests and responses.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 10)
                .padding(.top, 5)
        }
        .padding(10)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.9))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.7), lineWidth: 1)
        )
    }
}

#Preview {
    DebugSettingsView()
        .environment(DebugSettingsStore())
        .padding()
        .frame(width: 500)
}
