//
//  DebugSettingsView.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 5/13/25.
//

import SwiftUI

struct DebugSettingsView: View {
    // AppStorage for the global debug settings
    @AppStorage("saveDebugPrompts") private var saveDebugPrompts: Bool = false
    @AppStorage("debugLogLevel") private var debugLogLevel: Int = 1 // 0=None, 1=Basic, 2=Verbose
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Debug Settings")
                .font(.headline)
                .padding(.bottom, 5)
            
            // Toggle for saving debug prompts
            HStack {
                Toggle("Save Debug Files to Downloads", isOn: $saveDebugPrompts)
                    .toggleStyle(SwitchToggleStyle())
                    .help("When enabled, debug files will be saved to your Downloads folder")
            }
            .padding(.horizontal, 10)
            
            // Debug log level selection
            HStack {
                Text("Debug Log Level:")
                Picker("Log Level", selection: $debugLogLevel) {
                    Text("None").tag(0)
                    Text("Basic").tag(1)
                    Text("Verbose").tag(2)
                }
                .pickerStyle(SegmentedPickerStyle())
                .frame(width: 200)
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
        .padding()
        .frame(width: 500)
}
