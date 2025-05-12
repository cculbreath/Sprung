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
    @AppStorage("preferredOpenAIModel") private var preferredOpenAIModel: String = AIModels.gpt4o // Default to gpt4o

    // State for managing model list and loading/error status
    @State private var availableModels: [String] = []
    @State private var isLoadingModels: Bool = false
    @State private var modelError: String? = nil

    var body: some View {
        // HStack for compact toolbar display
        HStack(spacing: 8) {
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
            .pickerStyle(.menu) // Menu style is good for toolbars
            .disabled(isLoadingModels || availableModels.isEmpty || openAiApiKey == "none") // Disable if no key, loading, or empty
            .frame(minWidth: 120, idealWidth: 180) // Adjust width for toolbar

            // Refresh Button
            Button(action: fetchOpenAIModels) {
                if isLoadingModels {
                    ProgressView().scaleEffect(0.7) // Smaller ProgressView for toolbar
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(PlainButtonStyle()) // Plain style for toolbar buttons
            .disabled(openAiApiKey == "none" || isLoadingModels)
            .help(openAiApiKey == "none" ? "Enter OpenAI API Key to load models" : "Refresh model list")
        }
        // Removed padding, background, and border for toolbar suitability
        .onAppear {
            // Fetch models on appear only if the key is present and models haven't been loaded
            if openAiApiKey != "none" && availableModels.isEmpty && !isLoadingModels {
                fetchOpenAIModels()
            }
        }
        .onChange(of: openAiApiKey) { _, newKey in
            // Fetch models if API key changes and is valid
            if newKey != "none" {
                fetchOpenAIModels()
            } else {
                // Clear models if API key is removed
                availableModels = []
                modelError = "API key is required."
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
                        preferredOpenAIModel = models.first ?? AIModels.gpt4o // Default fallback
                    }
                }
                isLoadingModels = false
            }
        }
    }
}
