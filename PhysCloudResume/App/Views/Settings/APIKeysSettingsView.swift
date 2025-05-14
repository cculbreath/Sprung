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
    @AppStorage("geminiApiKey") private var geminiApiKey: String = "none"
    @AppStorage("brightDataApiKey") private var brightDataApiKey: String = "none"
    @AppStorage("proxycurlApiKey") private var proxycurlApiKey: String = "none"

    // State for managing editing mode for each key
    @State private var isEditingScrapingDog = false
    @State private var isEditingBrightData = false
    @State private var isEditingOpenAI = false
    @State private var isEditingGemini = false
    @State private var isEditingProxycurl = false

    // State for holding the edited value temporarily
    @State private var editedScrapingDogApiKey = ""
    @State private var editedOpenAiApiKey = ""
    @State private var editedGeminiApiKey = ""
    @State private var editedBrightDataApiKey = ""
    @State private var editedProxycurlApiKey = ""

    // State for hover effects on save/cancel buttons
    @State private var isHoveringCheckmark = false
    @State private var isHoveringXmark = false

    // Action to trigger OpenAI model fetch when key changes
    var onOpenAIKeyUpdate: () -> Void = {} // Callback

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
                // Gemini API Key Row
                apiKeyRow(
                    label: "Gemini",
                    icon: "sparkles.tv", // Custom icon for Gemini
                    value: $geminiApiKey,
                    isEditing: $isEditingGemini,
                    editedValue: $editedGeminiApiKey,
                    isHoveringCheckmark: $isHoveringCheckmark,
                    isHoveringXmark: $isHoveringXmark
                )
                Divider()
                // Bright Data API Key Row
                apiKeyRow(
                    label: "Bright Data",
                    icon: "sun.max.fill", // Changed icon for Bright Data
                    value: $brightDataApiKey,
                    isEditing: $isEditingBrightData,
                    editedValue: $editedBrightDataApiKey,
                    isHoveringCheckmark: $isHoveringCheckmark,
                    isHoveringXmark: $isHoveringXmark
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
                        value.wrappedValue = editedValue.wrappedValue.isEmpty ? "none" : editedValue.wrappedValue
                        isEditing.wrappedValue = false
                        onSave?() // Call the save callback if provided
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
