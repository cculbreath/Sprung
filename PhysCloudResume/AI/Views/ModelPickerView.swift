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
    
    /// Optional filter to restrict which providers are shown
    var providerFilter: [String]? = nil
    
    /// Optional title for the picker
    var title: String? = nil
    
    /// Controls whether to show the refresh button
    var showRefreshButton: Bool = true
    
    /// Initializes a new model picker view
    /// - Parameters:
    ///   - selectedModel: Binding to the selected model
    ///   - providerFilter: Optional array of provider names to include (nil = all providers)
    ///   - title: Optional title for the picker
    ///   - showRefreshButton: Whether to show the refresh button
    init(
        selectedModel: Binding<String>,
        providerFilter: [String]? = nil,
        title: String? = nil,
        showRefreshButton: Bool = true
    ) {
        self._selectedModel = selectedModel
        self.providerFilter = providerFilter
        self.title = title
        self.showRefreshButton = showRefreshButton
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
                // Get all available models
                let allModels = modelService.getAllModels()
                
                // Filter providers if requested
                let providers = providerFilter ?? [
                    AIModels.Provider.openai,
                    AIModels.Provider.claude,
                    AIModels.Provider.grok,
                    AIModels.Provider.gemini
                ]
                
                // Group models by provider
                ForEach(providers, id: \.self) { provider in
                    if let models = allModels[provider], !models.isEmpty {
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
