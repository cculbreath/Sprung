// PhysCloudResume/App/Views/SettingsView.swift

import SwiftUI

struct SettingsView: View {
    // State variable needed by APIKeysSettingsView callback
    @State private var forceModelFetch = false

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
                    forceModelFetch.toggle() // Trigger state change to signal OpenAIModelSettingsView
                }

                // OpenAI Model Selection Section
                OpenAIModelSettingsView()
                    // Observe the state change to trigger a model fetch
                    .id(forceModelFetch) // Use .id to force recreation/update if needed

                // Resume Styles Section
                ResumeStylesSettingsView()

                // Text-to-Speech Settings Section
                TextToSpeechSettingsView()

                // Preferred API Selection Section
                PreferredAPISettingsView()

                // Fix Overflow Iterations Setting
                FixOverflowSettingsView(fixOverflowMaxIterations: $fixOverflowMaxIterations)
            }
            .padding() // Add padding around the entire content VStack
        }
        // Set the frame for the settings window
        .frame(minWidth: 450, idealWidth: 600, maxWidth: .infinity,
               minHeight: 550, idealHeight: 750, maxHeight: .infinity) // Adjusted ideal height
        .background(Color(NSColor.controlBackgroundColor)) // Use standard control background
        // Allow the sheet to be resized
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// New subview for Fix Overflow settings
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
