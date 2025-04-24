// PhysCloudResume/App/Views/SettingsView.swift

import SwiftUI

struct SettingsView: View {
    // State variable needed by APIKeysSettingsView callback
    @State private var forceModelFetch = false

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
            }
            .padding() // Add padding around the entire content VStack
        }
        // Set the frame for the settings window
        .frame(minWidth: 450, idealWidth: 600, maxWidth: .infinity,
               minHeight: 500, idealHeight: 700, maxHeight: .infinity) // Adjusted ideal height
        .background(Color(NSColor.controlBackgroundColor)) // Use standard control background
        // Allow the sheet to be resized
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
