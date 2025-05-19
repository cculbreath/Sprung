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

    @AppStorage("preferredLLMModel") private var preferredLLMModel: String = AIModels.gpt4o // Default to gpt4o

    // State for managing model list and loading/error status
    @State private var availableOpenAIModels: [String] = []
    @State private var isLoadingOpenAIModels: Bool = false
    @State private var modelError: String? = nil

    // Combined list of all models
    private var allModels: [String] {
        var models: [String] = []
        
        // Add OpenAI models if API key is configured
        if openAiApiKey != "none" {
            models.append(contentsOf: availableOpenAIModels.isEmpty ? defaultOpenAIModels() : availableOpenAIModels)
        }

        return models
    }
    
    // Display name for models (adds provider prefix)
    private func displayName(for model: String) -> String {
        return model
    }
    


    var body: some View {
        // HStack for compact toolbar display
        HStack(spacing: 8) {
            // Model Selection Picker
            Picker("Model", selection: $preferredLLMModel) {
                // Always provide the current selection as an option to prevent invalid state
                if !allModels.contains(preferredLLMModel) {
                    Text(preferredLLMModel).tag(preferredLLMModel)
                }
                
                // List all available models
                ForEach(allModels, id: \.self) { model in
                    Text(displayName(for: model)).tag(model)
                }
            }
            .pickerStyle(.menu) // Menu style is good for toolbars
            .disabled(allModels.isEmpty) // Disable if no models available
            .frame(minWidth: 180, idealWidth: 220) // Adjust width for toolbar
            .onChange(of: preferredLLMModel) { _, newValue in
                // Validate whenever the selection changes
                validateModelSelection(newValue)
            }

            // Refresh Button
            Button(action: fetchAllModels) {
                if isLoadingOpenAIModels  {
                    ProgressView().scaleEffect(0.7) // Smaller ProgressView for toolbar
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(PlainButtonStyle()) // Plain style for toolbar buttons
            .disabled((openAiApiKey == "none") ||
                      (isLoadingOpenAIModels))
            .help(openAiApiKey == "none" ?
                 "Enter API Keys in Settings to load models" : "Refresh model list")
        }
        // Removed padding, background, and border for toolbar suitability
        .onAppear {
            // Fix any corrupted model names first
            fixCorruptedModelName()
            // Fetch models on appear only if API keys are present and models haven't been loaded
            fetchAllModels()
        }
        .onChange(of: openAiApiKey) { _, _ in
            // Fetch OpenAI models if API key changes
            fetchOpenAIModels()
        }

    }

    // Function to fetch both OpenAI models
    private func fetchAllModels() {
        fetchOpenAIModels()

        // Ensure the selected model is still valid
        validateSelectedModel()
    }
    
    // Function to fetch available OpenAI models
    private func fetchOpenAIModels() {
        guard openAiApiKey != "none" else {
            // Clear models if key is missing
            availableOpenAIModels = []
            return
        }

        isLoadingOpenAIModels = true
        modelError = nil // Clear previous errors

        Task {
            let models = await OpenAIModelFetcher.fetchAvailableModels(apiKey: openAiApiKey)

            await MainActor.run {
                availableOpenAIModels = models.isEmpty ? defaultOpenAIModels() : models
                isLoadingOpenAIModels = false
                validateSelectedModel()
            }
        }
    }
    
    // Function to fetch available Gemini models

    
    // Validate that the selected model is in the available models list
    private func validateSelectedModel() {
        // First, fix common corrupted model names
        fixCorruptedModelName()
        
        if !allModels.isEmpty && !allModels.contains(preferredLLMModel) {
            // If the currently selected model is not available, select a default
            if openAiApiKey != "none" && !availableOpenAIModels.isEmpty {
                // Prefer OpenAI models if available
                preferredLLMModel = availableOpenAIModels.first ?? AIModels.gpt4o
            }
        }
    }
    
    // Fix common corrupted model names that might be stored in UserDefaults
    private func fixCorruptedModelName() {
        let sanitized = OpenAIModelFetcher.sanitizeModelName(preferredLLMModel)
        if sanitized != preferredLLMModel {
            Logger.debug("🔧 Correcting corrupted model name: '\(preferredLLMModel)' → '\(sanitized)'")
            preferredLLMModel = sanitized
        }
    }
    
    // Validate model selection in real-time
    private func validateModelSelection(_ newValue: String) {
        // Check if the new value is valid
        if !allModels.contains(newValue) && !newValue.isEmpty {
            Logger.warning("⚠️ Invalid model selection: '\(newValue)'. Available models: \(allModels)")
            
            // Try to find a close match or fallback to default
            if let closestMatch = findClosestModelMatch(for: newValue) {
                preferredLLMModel = closestMatch
                Logger.debug("🔧 Corrected to closest match: '\(closestMatch)'")
            } else {
                // Fallback to default
                preferredLLMModel = AIModels.gpt4o
                Logger.debug("🔧 Fallback to default model: '\(AIModels.gpt4o)'")
            }
        }
    }
    
    // Find the closest matching model name
    private func findClosestModelMatch(for invalidModel: String) -> String? {
        // Check if it's a known corrupted variant
        switch invalidModel {
        case let model where model.contains("o4") && model.contains("mini"):
            return AIModels.gpt4o_mini
        case let model where model.contains("o4") && !model.contains("mini"):
            return AIModels.gpt4o
        case let model where model.contains("3.5") || model.contains("35"):
            return allModels.first { $0.contains("3.5-turbo") }
        case let model where model.contains("4-turbo") || model.contains("4turbo"):
            return allModels.first { $0.contains("4-turbo") }
        default:
            return nil
        }
    }
    
    // Default OpenAI models when API is not available
    private func defaultOpenAIModels() -> [String] {
        return [
            AIModels.gpt4o,
            AIModels.gpt4o_mini,
            AIModels.gpt4_5,
            AIModels.gpt4o_2024_08_06
        ]
    }
    

}
