// PhysCloudResume/App/Views/SettingsView.swift

import SwiftUI

struct SettingsView: View {
    // State variable needed by APIKeysSettingsView callback
    // This can be removed if OpenAIModelSettingsView is no longer a child and handles its own updates.
    // @State private var forceModelFetch = false // Removed as OpenAIModelSettingsView is now in toolbar

    // AppStorage for the new Fix Overflow setting
    @AppStorage("fixOverflowMaxIterations") private var fixOverflowMaxIterations: Int = 3

    var body: some View {
        // Use a ScrollView to handle potentially long content
        ScrollView(.vertical, showsIndicators: true) {
            // Main VStack containing all setting sections
            VStack(alignment: .leading, spacing: 20) { // Increased spacing between sections
                // API Keys Section
                APIKeysSettingsView {
                    // This closure is called when the OpenAI key is saved in APIKeysSettingsView
                    // If OpenAIModelSettingsView is in the toolbar, it might observe AppStorage directly
                    // or we might need a different mechanism to trigger its refresh if it's not always visible.
                    // For now, this callback might not be strictly necessary if the toolbar view handles its own updates.
                    // forceModelFetch.toggle() // This line can be removed if not used
                }

                // Resume Styles Section
                ResumeStylesSettingsView()

                // Text-to-Speech Settings Section
                TextToSpeechSettingsView()

                // Preferred API Selection Section
                PreferredAPISettingsView()

                // Fix Overflow Iterations Setting
                FixOverflowSettingsView(fixOverflowMaxIterations: $fixOverflowMaxIterations)
                
                // Debug Settings Section
                DebugSettingsView()
            }
            .padding() // Add padding around the entire content VStack
        }
        // Set the frame for the settings window
        .frame(minWidth: 450, idealWidth: 600, maxWidth: .infinity,
               minHeight: 450, idealHeight: 650, maxHeight: .infinity) // Adjusted min and ideal height
        .background(Color(NSColor.controlBackgroundColor)) // Use standard control background
        // Allow the sheet to be resized
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// New subview for Fix Overflow settings (remains unchanged)
struct FixOverflowSettingsView: View {
    @Binding var fixOverflowMaxIterations: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Resume Overflow Correction")
                .font(.headline)
                .padding(.bottom, 5)

            HStack {
                Text("Max Iterations for 'Fix Overflow':")
                Spacer()
                Stepper(value: $fixOverflowMaxIterations, in: 1 ... 10) {
                    Text("\(fixOverflowMaxIterations)")
                }
                .frame(width: 150) // Adjust width as needed
            }
            .padding(.horizontal, 10)

            Text("Controls how many times the AI will attempt to fix overflowing text in the 'Skills & Expertise' section.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 10)
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
