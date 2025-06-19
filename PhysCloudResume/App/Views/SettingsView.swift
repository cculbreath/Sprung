// PhysCloudResume/App/Views/SettingsView.swift

import SwiftUI

struct SettingsView: View {
    // State variable needed by APIKeysSettingsView callback
    // This can be removed if OpenAIModelSettingsView is no longer a child and handles its own updates.
    // @State private var forceModelFetch = false // Removed as OpenAIModelSettingsView is now in toolbar

    // AppStorage for the new Fix Overflow setting
    @AppStorage("fixOverflowMaxIterations") private var fixOverflowMaxIterations: Int = 3
    
    // AppStorage for reasoning effort setting
    @AppStorage("reasoningEffort") private var reasoningEffort: String = "medium"

    var body: some View {
        // Use a ScrollView to handle potentially long content
        ScrollView(.vertical, showsIndicators: true) {
            // Main VStack containing all setting sections
            VStack(alignment: .leading, spacing: 20) { // Increased spacing between sections
                // API Keys Section
                APIKeysSettingsView {}

                // LLM Provider Info Section
                LLMProviderSettingsView()


                // Text-to-Speech Settings Section
                TextToSpeechSettingsView()

                // Preferred API Selection Section
                PreferredAPISettingsView()

                // Fix Overflow Iterations Setting
                FixOverflowSettingsView(fixOverflowMaxIterations: $fixOverflowMaxIterations)
                
                // Reasoning Effort Setting
                ReasoningEffortSettingsView(reasoningEffort: $reasoningEffort)
                
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

// New subview for Reasoning Effort settings
struct ReasoningEffortSettingsView: View {
    @Binding var reasoningEffort: String
    
    private let effortOptions = [
        ("low", "Low", "Faster responses with basic reasoning"),
        ("medium", "Medium", "Balanced speed and reasoning depth"),
        ("high", "High", "Thorough reasoning with detailed analysis")
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("AI Reasoning Effort")
                .font(.headline)
                .padding(.bottom, 5)
            
            VStack(alignment: .leading, spacing: 8) {
                ForEach(effortOptions, id: \.0) { value, title, description in
                    HStack {
                        RadioButton(
                            isSelected: reasoningEffort == value,
                            action: { reasoningEffort = value }
                        )
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text(description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        reasoningEffort = value
                    }
                }
            }
            .padding(.horizontal, 10)
            
            Text("Controls how much computational effort the AI uses for reasoning when available. Higher effort may result in better quality but slower responses.")
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

// Custom radio button component
struct RadioButton: View {
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(Color.secondary, lineWidth: 2)
                    .frame(width: 16, height: 16)
                
                if isSelected {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 8, height: 8)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

