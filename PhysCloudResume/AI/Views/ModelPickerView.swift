//
//  ModelPickerView.swift
//  PhysCloudResume
//
//  Created by Claude on 5/20/25.
//

import SwiftUI

/// A reusable view for picking AI models across different providers
struct ModelPickerView: View {
    /// The currently selected model
    @Binding var selectedModel: String
    
    /// The model service for fetching available models
    @EnvironmentObject private var modelService: ModelService
    
    /// Access to app state for selected models
    @Environment(AppState.self) private var appState
    
    /// Optional filter to restrict which providers are shown
    var providerFilter: [String]? = nil
    
    /// Optional title for the picker
    var title: String? = nil
    
    /// Controls whether to show the refresh button
    var showRefreshButton: Bool = true
    
    /// Whether to respect user's model selection preferences (requires AppState)
    var useModelSelection: Bool = true
    
    /// API keys for filtering available providers
    @AppStorage("openAiApiKey") private var openAiApiKey: String = "none"
    @AppStorage("claudeApiKey") private var claudeApiKey: String = "none"
    @AppStorage("grokApiKey") private var grokApiKey: String = "none"
    @AppStorage("geminiApiKey") private var geminiApiKey: String = "none"
    
    /// Initializes a new model picker view
    /// - Parameters:
    ///   - selectedModel: Binding to the selected model
    ///   - providerFilter: Optional array of provider names to include (nil = all providers)
    ///   - title: Optional title for the picker
    ///   - showRefreshButton: Whether to show the refresh button
    ///   - useModelSelection: Whether to respect user's model selection preferences
    init(
        selectedModel: Binding<String>,
        providerFilter: [String]? = nil,
        title: String? = nil,
        showRefreshButton: Bool = true,
        useModelSelection: Bool = true
    ) {
        self._selectedModel = selectedModel
        self.providerFilter = providerFilter
        self.title = title
        self.showRefreshButton = showRefreshButton
        self.useModelSelection = useModelSelection
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Title row with optional refresh button
            if let title = title {
                HStack {
                    Text(title)
                        .font(.headline)
                    
                    Spacer()
                    
                    if showRefreshButton {
                        refreshButton
                    }
                }
            }
            
            // Picker with all models grouped by provider
            Picker("Model", selection: $selectedModel) {
                pickerContent
            }
            .pickerStyle(.menu)
        }
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
    
    private var modelsDict: [String: [String]] {
        if useModelSelection {
            return modelService.getSelectedModels(selectedModels: appState.selectedModels)
        } else {
            return modelService.getAllModels()
        }
    }
    
    @ViewBuilder
    private var pickerContent: some View {
        // Get available providers based on API keys
        let availableProviders = getAvailableProviders()
        
        // Apply provider filter if specified, otherwise use available providers
        let providers = providerFilter != nil ? 
            providerFilter!.filter { availableProviders.contains($0) } : 
            availableProviders
        
        // Check if any models are available
        let hasAnyModels = providers.contains { provider in
            if let models = modelsDict[provider], !models.isEmpty {
                return true
            }
            return false
        }
        
        if !hasAnyModels {
            Text(useModelSelection ? "No models selected - Configure in Settings" : "No models available")
                .foregroundColor(.secondary)
                .tag("")
        } else {
            // Group models by provider
            ForEach(providers, id: \.self) { provider in
                if let models = modelsDict[provider], !models.isEmpty {
                    Section(header: Text(provider)) {
                        ForEach(models, id: \.self) { model in
                            let sanitizedModel = OpenAIModelFetcher.sanitizeModelName(model)
                            Text(formatModelName(sanitizedModel))
                                .tag(sanitizedModel)
                        }
                    }
                }
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
    
    /// Formats a model name for display
    /// - Parameter model: The raw model name
    /// - Returns: A formatted model name
    private func formatModelName(_ model: String) -> String {
        // Show last part of the model name if it has a version timestamp
        if model.contains("-2024") {
            let components = model.components(separatedBy: "-20")
            if components.count > 1 {
                return "\(components[0]) (20\(components[1]))"
            }
        }
        return model
    }
    
    /// Fetches all models from enabled providers
    private func fetchModels() {
        Logger.debug("Fetching all model lists")
        
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
    
    /// Refresh button for the picker
    private var refreshButton: some View {
        Button(action: {
            fetchModels()
        }) {
            Image(systemName: "arrow.clockwise")
                .font(.footnote)
        }
        .buttonStyle(.borderless)
        .help("Refresh model list")
    }
}
