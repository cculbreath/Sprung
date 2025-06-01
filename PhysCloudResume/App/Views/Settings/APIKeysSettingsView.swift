//
//  APIKeysSettingsView.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 4/24/25.
//

import SwiftUI

struct APIKeysSettingsView: View {
    // AppStorage properties specific to this view
    @AppStorage("scrapingDogApiKey") private var scrapingDogApiKey: String = "none"
    @AppStorage("openAiApiKey") private var openAiApiKey: String = "none"
    @AppStorage("proxycurlApiKey") private var proxycurlApiKey: String = "none"
    @AppStorage("claudeApiKey") private var claudeApiKey: String = "none"
    @AppStorage("grokApiKey") private var grokApiKey: String = "none"
    @AppStorage("geminiApiKey") private var geminiApiKey: String = "none"

    // State for managing editing mode for each key
    @State private var isEditingScrapingDog = false
    @State private var isEditingOpenAI = false
    @State private var isEditingProxycurl = false
    @State private var isEditingClaude = false
    @State private var isEditingGrok = false
    @State private var isEditingGemini = false

    // State for holding the edited value temporarily
    @State private var editedScrapingDogApiKey = ""
    @State private var editedOpenAiApiKey = ""
    @State private var editedProxycurlApiKey = ""
    @State private var editedClaudeApiKey = ""
    @State private var editedGrokApiKey = ""
    @State private var editedGeminiApiKey = ""

    // State for hover effects on save/cancel buttons
    @State private var isHoveringCheckmark = false
    @State private var isHoveringXmark = false

    // Action to trigger model fetch when keys change
    var onOpenAIKeyUpdate: () -> Void = {} // Callback
    
    // Note: API validation can be implemented per-service as needed
    
    // Initialize LLMRequestService to update client when keys change
    private func updateLLMClient() {
        Task { @MainActor in
            // This will initialize the appropriate client based on current model and available API keys
            LLMRequestService.shared.updateClientForCurrentModel()
            
            // Also validate the API key that changed
            if isEditingOpenAI {
                modelService.fetchModelsForProvider(provider: AIModels.Provider.openai, apiKey: openAiApiKey)
            } else if isEditingClaude {
                modelService.fetchModelsForProvider(provider: AIModels.Provider.claude, apiKey: claudeApiKey)
            } else if isEditingGrok {
                modelService.fetchModelsForProvider(provider: AIModels.Provider.grok, apiKey: grokApiKey)
            } else if isEditingGemini {
                modelService.fetchModelsForProvider(provider: AIModels.Provider.gemini, apiKey: geminiApiKey)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("API Keys")
                .font(.headline)
                .padding(.bottom, 5)

            VStack(spacing: 0) {
                // Scraping Dog API Key Row
                apiKeyRow(
                    label: "Scraping Dog",
                    icon: "dog.fill",
                    value: $scrapingDogApiKey,
                    isEditing: $isEditingScrapingDog,
                    editedValue: $editedScrapingDogApiKey,
                    isHoveringCheckmark: $isHoveringCheckmark,
                    isHoveringXmark: $isHoveringXmark
                )
                Divider()
                // OpenAI API Key Row
                apiKeyRow(
                    label: "OpenAI",
                    icon: "sparkles", // Changed icon for OpenAI
                    value: $openAiApiKey,
                    isEditing: $isEditingOpenAI,
                    editedValue: $editedOpenAiApiKey,
                    isHoveringCheckmark: $isHoveringCheckmark,
                    isHoveringXmark: $isHoveringXmark,
                    onSave: onOpenAIKeyUpdate // Trigger model fetch on save
                )
                Divider()
                // Claude API Key Row
                apiKeyRow(
                    label: "Claude",
                    icon: "brain", // Icon for Anthropic Claude
                    value: $claudeApiKey,
                    isEditing: $isEditingClaude,
                    editedValue: $editedClaudeApiKey,
                    isHoveringCheckmark: $isHoveringCheckmark,
                    isHoveringXmark: $isHoveringXmark,
                    onSave: onOpenAIKeyUpdate // Trigger model fetch on save
                )
                Divider()
                // Grok API Key Row
                apiKeyRow(
                    label: "Grok",
                    icon: "bolt.fill", // Icon for xAI Grok
                    value: $grokApiKey,
                    isEditing: $isEditingGrok,
                    editedValue: $editedGrokApiKey,
                    isHoveringCheckmark: $isHoveringCheckmark,
                    isHoveringXmark: $isHoveringXmark,
                    onSave: onOpenAIKeyUpdate // Trigger model fetch on save
                )
                Divider()
                // Gemini API Key Row
                apiKeyRow(
                    label: "Gemini",
                    icon: "star.fill", // Icon for Google Gemini
                    value: $geminiApiKey,
                    isEditing: $isEditingGemini,
                    editedValue: $editedGeminiApiKey,
                    isHoveringCheckmark: $isHoveringCheckmark,
                    isHoveringXmark: $isHoveringXmark,
                    onSave: onOpenAIKeyUpdate // Trigger model fetch on save
                )
                Divider()
                // Proxycurl API Key Row
                apiKeyRow(
                    label: "Proxycurl",
                    icon: "link.circle.fill", // Changed icon for Proxycurl
                    value: $proxycurlApiKey,
                    isEditing: $isEditingProxycurl,
                    editedValue: $editedProxycurlApiKey,
                    isHoveringCheckmark: $isHoveringCheckmark,
                    isHoveringXmark: $isHoveringXmark
                )
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

    // Reusable view builder for each API key row
    @ViewBuilder
    private func apiKeyRow(
        label: String,
        icon: String,
        value: Binding<String>,
        isEditing: Binding<Bool>,
        editedValue: Binding<String>,
        isHoveringCheckmark: Binding<Bool>, // Pass hover state bindings
        isHoveringXmark: Binding<Bool>,
        onSave: (() -> Void)? = nil // Optional save action callback
    ) -> some View {
        HStack {
            // Label and Icon
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.secondary) // Use secondary color for icon
                Text(label)
                    .fontWeight(.medium)
            }
            .frame(width: 120, alignment: .leading) // Align label width

            Spacer()

            // Editing State: TextField and Save/Cancel Buttons
            if isEditing.wrappedValue {
                HStack(spacing: 8) {
                    // Use SecureField for API keys
                    SecureField("Enter API Key", text: editedValue)
                        .textFieldStyle(PlainTextFieldStyle()) // Keep it simple
                        .padding(.vertical, 4) // Add some padding
                        .background(Color(NSColor.textBackgroundColor)) // Standard background
                        .cornerRadius(4)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray.opacity(0.5)))

                    // Save Button
                    Button {
                        // Trim the key to remove any whitespace
                        let cleanKey = editedValue.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        value.wrappedValue = cleanKey.isEmpty ? "none" : cleanKey
                        isEditing.wrappedValue = false
                        
                        // Log key update (without revealing the entire key)
                        if cleanKey != "none" && !cleanKey.isEmpty {
                            let firstChars = String(cleanKey.prefix(4))
                            let length = cleanKey.count
                            Logger.debug("🔑 Updated API key for \(label): First chars: \(firstChars), Length: \(length)")
                        }
                        
                        onSave?() // Call the save callback if provided
                        updateLLMClient() // Update the LLM client when any API key changes
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(isHoveringCheckmark.wrappedValue ? .green : .gray)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    .onHover { hovering in isHoveringCheckmark.wrappedValue = hovering }

                    // Cancel Button
                    Button {
                        isEditing.wrappedValue = false // Just cancel editing
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(isHoveringXmark.wrappedValue ? .red : .gray)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    .onHover { hovering in isHoveringXmark.wrappedValue = hovering }
                }
                .frame(maxWidth: .infinity) // Allow editing controls to take space

                // Display State: Masked Key and Edit Button
            } else {
                HStack {
                    // Mask the API key for display
                    Text(maskApiKey(value.wrappedValue))
                        .italic()
                        .foregroundColor(.gray)
                        .fontWeight(.light)
                        .lineLimit(1)
                        .truncationMode(.middle) // Show middle part if too long

                    Spacer() // Push edit button to the right

                    // Edit Button
                    Button {
                        editedValue.wrappedValue = (value.wrappedValue == "none" ? "" : value.wrappedValue)
                        isEditing.wrappedValue = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    .foregroundColor(.gray) // Subtle edit icon color
                }
                .frame(maxWidth: .infinity) // Allow display controls to take space
            }
        }
        .padding(.vertical, 8)
    }

    // Helper function to mask API keys
    private func maskApiKey(_ key: String) -> String {
        guard key != "none", key.count > 8 else {
            return key // Show "none" or short keys as is
        }
        // Show first 4 and last 4 characters
        return "\(key.prefix(4))...\(key.suffix(4))"
    }
}
