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
    @AppStorage("geminiApiKey") private var geminiApiKey: String = "none"
    @AppStorage("preferredLLMModel") private var preferredLLMModel: String = AIModels.gpt4o // Default to gpt4o

    // State for managing model list and loading/error status
    @State private var availableOpenAIModels: [String] = []
    @State private var availableGeminiModels: [String] = []
    @State private var isLoadingOpenAIModels: Bool = false
    @State private var isLoadingGeminiModels: Bool = false
    @State private var modelError: String? = nil
    
    // Combined list of all models
    private var allModels: [String] {
        var models: [String] = []
        
        // Add OpenAI models if API key is configured
        if openAiApiKey != "none" {
            models.append(contentsOf: availableOpenAIModels.isEmpty ? defaultOpenAIModels() : availableOpenAIModels)
        }
        
        // Add Gemini models if API key is configured
        if geminiApiKey != "none" {
            models.append(contentsOf: availableGeminiModels.isEmpty ? defaultGeminiModels() : availableGeminiModels)
        }
        
        return models
    }
    
    // Display name for models (adds provider prefix)
    private func displayName(for model: String) -> String {
        if isGeminiModel(model) {
            return "Gemini: \(model)"
        } else {
            return "OpenAI: \(model)"
        }
    }
    
    // Check if a model is from Gemini
    private func isGeminiModel(_ model: String) -> Bool {
        return model.starts(with: "gemini-")
    }

    var body: some View {
        // HStack for compact toolbar display
        HStack(spacing: 8) {
            // Model Selection Picker
            Picker("Model", selection: $preferredLLMModel) {
                // Ensure there's always a default option, even if loading fails
                if allModels.isEmpty {
                    Text(preferredLLMModel).tag(preferredLLMModel) // Show current if list empty
                }
                
                // List all available models
                ForEach(allModels, id: \.self) { model in
                    Text(displayName(for: model)).tag(model)
                }
            }
            .pickerStyle(.menu) // Menu style is good for toolbars
            .disabled(allModels.isEmpty) // Disable if no models available
            .frame(minWidth: 180, idealWidth: 220) // Adjust width for toolbar

            // Refresh Button
            Button(action: fetchAllModels) {
                if isLoadingOpenAIModels || isLoadingGeminiModels {
                    ProgressView().scaleEffect(0.7) // Smaller ProgressView for toolbar
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(PlainButtonStyle()) // Plain style for toolbar buttons
            .disabled((openAiApiKey == "none" && geminiApiKey == "none") || 
                      (isLoadingOpenAIModels || isLoadingGeminiModels))
            .help(openAiApiKey == "none" && geminiApiKey == "none" ? 
                 "Enter API Keys in Settings to load models" : "Refresh model list")
        }
        // Removed padding, background, and border for toolbar suitability
        .onAppear {
            // Fetch models on appear only if API keys are present and models haven't been loaded
            fetchAllModels()
        }
        .onChange(of: openAiApiKey) { _, _ in
            // Fetch OpenAI models if API key changes
            fetchOpenAIModels()
        }
        .onChange(of: geminiApiKey) { _, _ in
            // Fetch Gemini models if API key changes
            fetchGeminiModels()
        }
    }

    // Function to fetch both OpenAI and Gemini models
    private func fetchAllModels() {
        fetchOpenAIModels()
        fetchGeminiModels()
        
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
    private func fetchGeminiModels() {
        guard geminiApiKey != "none" else {
            // Clear models if key is missing
            availableGeminiModels = []
            return
        }

        isLoadingGeminiModels = true
        modelError = nil // Clear previous errors

        Task {
            let models = await GeminiModelFetcher.fetchAvailableModels(apiKey: geminiApiKey)

            await MainActor.run {
                availableGeminiModels = models.isEmpty ? defaultGeminiModels() : models
                isLoadingGeminiModels = false
                validateSelectedModel()
            }
        }
    }
    
    // Validate that the selected model is in the available models list
    private func validateSelectedModel() {
        if !allModels.isEmpty && !allModels.contains(preferredLLMModel) {
            // If the currently selected model is not available, select a default
            if openAiApiKey != "none" && !availableOpenAIModels.isEmpty {
                // Prefer OpenAI models if available
                preferredLLMModel = availableOpenAIModels.first ?? AIModels.gpt4o
            } else if geminiApiKey != "none" && !availableGeminiModels.isEmpty {
                // Fall back to Gemini models
                preferredLLMModel = availableGeminiModels.first ?? AIModels.gemini_1_5_pro
            }
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
    
    // Default Gemini models when API is not available
    private func defaultGeminiModels() -> [String] {
        return [
            AIModels.gemini_1_5_pro,
            AIModels.gemini_1_5_flash,
            AIModels.gemini_1_0_pro
        ]
    }
}
