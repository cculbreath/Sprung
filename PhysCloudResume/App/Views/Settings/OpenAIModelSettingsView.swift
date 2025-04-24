//
//  OpenAIModelSettingsView.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 4/24/25.
//

import SwiftUI

struct OpenAIModelSettingsView: View {
    // AppStorage properties specific to this view
    @AppStorage("openAiApiKey") private var openAiApiKey: String = "none"
    @AppStorage("preferredOpenAIModel") private var preferredOpenAIModel: String = "gpt-4o-2024-08-06"

    // State for managing model list and loading/error status
    @State private var availableModels: [String] = []
    @State private var isLoadingModels: Bool = false
    @State private var modelError: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("OpenAI Model")
                .font(.headline)

            HStack {
                // Model Selection Picker
                Picker("Model", selection: $preferredOpenAIModel) {
                    // Ensure there's always a default option, even if loading fails
                    if availableModels.isEmpty && !isLoadingModels {
                        Text(preferredOpenAIModel).tag(preferredOpenAIModel) // Show current if list empty
                    }
                    // List fetched models
                    ForEach(availableModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                .disabled(isLoadingModels || availableModels.isEmpty) // Disable while loading or if empty
                .frame(maxWidth: .infinity) // Take available width

                // Refresh Button
                Button(action: fetchOpenAIModels) {
                    if isLoadingModels {
                        ProgressView().scaleEffect(0.8) // Show spinner while loading
                    } else {
                        Image(systemName: "arrow.clockwise") // Refresh icon
                    }
                }
                .buttonStyle(BorderlessButtonStyle())
                .disabled(openAiApiKey == "none" || isLoadingModels) // Disable if no key or loading
                .help(openAiApiKey == "none" ? "Enter OpenAI API Key to load models" : "Refresh model list")
            }

            // Display Error Message if any
            if let error = modelError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            // Prompt user to load models if list is empty
            if availableModels.isEmpty && !isLoadingModels && modelError == nil && openAiApiKey != "none" {
                Text("Click refresh (↻) to load available models.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(10)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.9))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.7), lineWidth: 1)
        )
        .onAppear {
            // Fetch models on appear only if the key is present
            if openAiApiKey != "none" && availableModels.isEmpty {
                fetchOpenAIModels()
            }
        }
    }

    // Function to fetch available OpenAI models
    private func fetchOpenAIModels() {
        guard openAiApiKey != "none" else {
            modelError = "API key is required to fetch models."
            availableModels = [] // Clear models if key is missing
            return
        }

        isLoadingModels = true
        modelError = nil // Clear previous errors

        Task {
            let models = await OpenAIModelFetcher.fetchAvailableModels(apiKey: openAiApiKey)

            await MainActor.run {
                if models.isEmpty {
                    modelError = "Failed to fetch models or no models available."
                    availableModels = [] // Ensure list is empty on failure
                } else {
                    availableModels = models
                    // Ensure the selected model is still valid, otherwise default
                    if !models.contains(preferredOpenAIModel) {
                        preferredOpenAIModel = models.first ?? "gpt-4o-2024-08-06" // Default fallback
                    }
                }
                isLoadingModels = false
            }
        }
    }
}
