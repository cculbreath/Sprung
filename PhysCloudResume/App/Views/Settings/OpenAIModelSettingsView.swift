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
    @AppStorage("claudeApiKey") private var claudeApiKey: String = "none"
    @AppStorage("grokApiKey") private var grokApiKey: String = "none"
    @AppStorage("geminiApiKey") private var geminiApiKey: String = "none"
    @AppStorage("preferredLLMModel") private var preferredLLMModel: String = AIModels.gpt4o // Default to gpt4o

    // Access the model service
    @EnvironmentObject private var modelService: ModelService
    
    // Combined list of all available providers with API keys
    private var availableProviders: [String] {
        var providers: [String] = []
        
        if openAiApiKey != "none" {
            providers.append(AIModels.Provider.openai)
        }
        
        if claudeApiKey != "none" {
            providers.append(AIModels.Provider.claude)
        }
        
        if grokApiKey != "none" {
            providers.append(AIModels.Provider.grok)
        }
        
        if geminiApiKey != "none" {
            providers.append(AIModels.Provider.gemini)
        }
        
        return providers
    }

    var body: some View {
        // HStack for compact toolbar display
        HStack(spacing: 8) {
            if availableProviders.isEmpty {
                Text("No API keys configured")
                    .foregroundColor(.secondary)
                    .font(.caption)
            } else {
                // Use the ModelPickerView with the current model and available providers
                ModelPickerView(
                    selectedModel: $preferredLLMModel,
                    providerFilter: availableProviders.isEmpty ? nil : availableProviders,
                    showRefreshButton: false // Hide refresh button in toolbar for cleaner look
                )
                .onChange(of: preferredLLMModel) { _, newValue in
                    // Fix corrupted model names
                    let sanitized = OpenAIModelFetcher.sanitizeModelName(newValue)
                    if sanitized != newValue {
                        Logger.debug("🔧 Correcting corrupted model name: '\(newValue)' → '\(sanitized)'")
                        preferredLLMModel = sanitized
                    }
                    
                    // Update the LLM client for the new model
                    Task { @MainActor in
                        LLMRequestService.shared.updateClientForCurrentModel()
                    }
                }
            }
        }
        .frame(minWidth: 200, maxHeight: 30) // Fixed height for better alignment
        .onAppear {
            // Fix any corrupted model names on appear
            preferredLLMModel = OpenAIModelFetcher.sanitizeModelName(preferredLLMModel)
            
            // Fetch models on appear if API keys are present
            if !availableProviders.isEmpty {
                fetchAllModels()
            }
        }
        .onChange(of: openAiApiKey) { _, newValue in
            if newValue != "none" {
                modelService.fetchModelsForProvider(provider: AIModels.Provider.openai, apiKey: newValue)
            }
        }
        .onChange(of: claudeApiKey) { _, newValue in
            if newValue != "none" {
                modelService.fetchModelsForProvider(provider: AIModels.Provider.claude, apiKey: newValue)
            }
        }
        .onChange(of: grokApiKey) { _, newValue in
            if newValue != "none" {
                modelService.fetchModelsForProvider(provider: AIModels.Provider.grok, apiKey: newValue)
            }
        }
        .onChange(of: geminiApiKey) { _, newValue in
            if newValue != "none" {
                modelService.fetchModelsForProvider(provider: AIModels.Provider.gemini, apiKey: newValue)
            }
        }
    }
    
    /// Fetches all models from providers with valid API keys
    private func fetchAllModels() {
        // Create a dictionary of API keys by provider
        let apiKeys = [
            AIModels.Provider.openai: openAiApiKey,
            AIModels.Provider.claude: claudeApiKey, 
            AIModels.Provider.grok: grokApiKey,
            AIModels.Provider.gemini: geminiApiKey
        ]
        
        // Use the model service to fetch all models
        modelService.fetchAllModels(apiKeys: apiKeys)
    }
}
