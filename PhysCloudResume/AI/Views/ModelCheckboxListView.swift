//
//  ModelCheckboxListView.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 5/30/25.
//

import SwiftUI

/// A reusable view for selecting multiple AI models with checkboxes
struct ModelCheckboxListView: View {
    /// The set of selected model identifiers
    @Binding var selectedModels: Set<String>
    
    /// The model service for fetching available models
    @EnvironmentObject private var modelService: ModelService
    
    /// Access to app state for selected models
    @Environment(AppState.self) private var appState
    
    /// Optional filter to restrict which providers are shown
    var providerFilter: [String]? = nil
    
    /// Whether to show provider headers
    var showProviderHeaders: Bool = true
    
    /// Whether to sanitize model names
    var sanitizeModelNames: Bool = true
    
    /// Maximum height for the scroll view
    var maxHeight: CGFloat = 200
    
    /// API keys for filtering available providers
    @AppStorage("openAiApiKey") private var openAiApiKey: String = "none"
    @AppStorage("claudeApiKey") private var claudeApiKey: String = "none"
    @AppStorage("grokApiKey") private var grokApiKey: String = "none"
    @AppStorage("geminiApiKey") private var geminiApiKey: String = "none"
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                let selectedModelsDict = modelService.getSelectedModels(selectedModels: appState.selectedModels)
                
                // Get available providers based on API keys
                let availableProviders = getAvailableProviders()
                
                // Apply provider filter if specified, otherwise use available providers
                let providers = providerFilter != nil ? 
                    providerFilter!.filter { availableProviders.contains($0) } : 
                    availableProviders
                
                // Check if any models are available
                let hasAnyModels = providers.contains { provider in
                    if let models = selectedModelsDict[provider], !models.isEmpty {
                        return true
                    }
                    return false
                }
                
                if !hasAnyModels {
                    VStack(spacing: 10) {
                        Text("No models available")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("Please configure available models in Settings")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
                } else {
                    ForEach(providers, id: \.self) { provider in
                        if let models = selectedModelsDict[provider], !models.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                if showProviderHeaders {
                                    // Provider header with All/None buttons
                                    HStack {
                                        Text(provider)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .textCase(.uppercase)
                                        
                                        Spacer()
                                        
                                        HStack(spacing: 8) {
                                            Button("All") {
                                                // Add all models from this provider
                                                for model in models {
                                                    let modelIdentifier = sanitizeModelNames ? OpenAIModelFetcher.sanitizeModelName(model) : model
                                                    selectedModels.insert(modelIdentifier)
                                                }
                                            }
                                            .buttonStyle(.bordered)
                                            .controlSize(.mini)
                                            
                                            Button("None") {
                                                // Remove all models from this provider
                                                for model in models {
                                                    let modelIdentifier = sanitizeModelNames ? OpenAIModelFetcher.sanitizeModelName(model) : model
                                                    selectedModels.remove(modelIdentifier)
                                                }
                                            }
                                            .buttonStyle(.bordered)
                                            .controlSize(.mini)
                                        }
                                    }
                                }
                                
                                ForEach(models, id: \.self) { model in
                                    let modelIdentifier = sanitizeModelNames ? OpenAIModelFetcher.sanitizeModelName(model) : model
                                    HStack {
                                        Toggle(isOn: Binding(
                                            get: { selectedModels.contains(modelIdentifier) },
                                            set: { isSelected in
                                                if isSelected {
                                                    selectedModels.insert(modelIdentifier)
                                                } else {
                                                    selectedModels.remove(modelIdentifier)
                                                }
                                            }
                                        )) {
                                            Text(model)
                                                .font(.system(.body))
                                        }
                                        .toggleStyle(CheckboxToggleStyle())
                                    }
                                }
                            }
                            .padding(.bottom, showProviderHeaders ? 8 : 4)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: maxHeight)
        .onAppear {
            // Check if we need to auto-fetch models on appear
            let needsFetching = modelService.fetchStatus.values.allSatisfy { status in
                if case .notStarted = status { return true }
                return false
            }
            
            if needsFetching {
                fetchModels()
            }
        }
    }
    
    private func getAvailableProviders() -> [String] {
        var providers: [String] = []
        if openAiApiKey != "none" && !openAiApiKey.isEmpty {
            providers.append(AIModels.Provider.openai)
        }
        if claudeApiKey != "none" && !claudeApiKey.isEmpty {
            providers.append(AIModels.Provider.claude)
        }
        if grokApiKey != "none" && !grokApiKey.isEmpty {
            providers.append(AIModels.Provider.grok)
        }
        if geminiApiKey != "none" && !geminiApiKey.isEmpty {
            providers.append(AIModels.Provider.gemini)
        }
        return providers
    }
    
    /// Fetches all models from enabled providers
    private func fetchModels() {
        // Get API keys from UserDefaults
        let apiKeys = [
            AIModels.Provider.openai: UserDefaults.standard.string(forKey: "openAiApiKey") ?? "none",
            AIModels.Provider.claude: UserDefaults.standard.string(forKey: "claudeApiKey") ?? "none",
            AIModels.Provider.grok: UserDefaults.standard.string(forKey: "grokApiKey") ?? "none",
            AIModels.Provider.gemini: UserDefaults.standard.string(forKey: "geminiApiKey") ?? "none"
        ]
        
        // Filter to just the providers we care about if a filter is set
        if let providerFilter = providerFilter {
            var filteredKeys: [String: String] = [:]
            for provider in providerFilter {
                if let key = apiKeys[provider] {
                    filteredKeys[provider] = key
                }
            }
            modelService.fetchAllModels(apiKeys: filteredKeys)
        } else {
            modelService.fetchAllModels(apiKeys: apiKeys)
        }
    }
}