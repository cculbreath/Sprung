//
//  ModelPickerView.swift
//  PhysCloudResume
//
//  Created by Claude on 5/20/25.
//

import SwiftUI

/// A reusable view for picking OpenRouter AI models
struct ModelPickerView: View {
    /// The currently selected model ID
    @Binding var selectedModel: String
    
    /// Access to app state and OpenRouter service
    @Environment(AppState.self) private var appState
    
    /// Optional capability filter to restrict which models are shown
    var capabilityFilter: ModelCapability? = nil
    
    /// Optional title for the picker
    var title: String? = nil
    
    /// Controls whether to show the refresh button
    var showRefreshButton: Bool = true
    
    /// Whether to respect user's model selection preferences
    var useModelSelection: Bool = true
    
    private var openRouterService: OpenRouterService {
        appState.openRouterService
    }
    
    /// Initializes a new model picker view
    /// - Parameters:
    ///   - selectedModel: Binding to the selected model ID
    ///   - capabilityFilter: Optional capability to filter models by
    ///   - title: Optional title for the picker
    ///   - showRefreshButton: Whether to show the refresh button
    ///   - useModelSelection: Whether to respect user's model selection preferences
    init(
        selectedModel: Binding<String>,
        capabilityFilter: ModelCapability? = nil,
        title: String? = nil,
        showRefreshButton: Bool = true,
        useModelSelection: Bool = true
    ) {
        self._selectedModel = selectedModel
        self.capabilityFilter = capabilityFilter
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
            
            // Picker with OpenRouter models grouped by provider
            Picker("Model", selection: $selectedModel) {
                pickerContent
            }
            .pickerStyle(.menu)
        }
        .onAppear {
            // Fetch models if we don't have any and have a valid API key
            if appState.hasValidOpenRouterKey && openRouterService.availableModels.isEmpty {
                Task {
                    await openRouterService.fetchModels()
                }
            }
        }
    }
    
    private var availableModels: [OpenRouterModel] {
        var models = openRouterService.availableModels
        
        // Apply capability filter if specified
        if let capability = capabilityFilter {
            models = openRouterService.getModelsWithCapability(capability)
        }
        
        // Apply user selection filter if enabled
        if useModelSelection {
            models = models.filter { appState.selectedOpenRouterModels.contains($0.id) }
        }
        
        return models
    }
    
    @ViewBuilder
    private var pickerContent: some View {
        if !appState.hasValidOpenRouterKey {
            Text("Configure OpenRouter API key in Settings")
                .foregroundColor(.secondary)
                .tag("")
        } else if availableModels.isEmpty {
            if openRouterService.isLoading {
                Text("Loading models...")
                    .foregroundColor(.secondary)
                    .tag("")
            } else if useModelSelection && !appState.selectedOpenRouterModels.isEmpty {
                Text("No models match criteria")
                    .foregroundColor(.secondary)
                    .tag("")
            } else if useModelSelection {
                Text("No models selected - Configure in Settings")
                    .foregroundColor(.secondary)
                    .tag("")
            } else {
                Text("No models available")
                    .foregroundColor(.secondary)
                    .tag("")
            }
        } else {
            // Group models by provider
            let groupedModels = Dictionary(grouping: availableModels) { $0.providerName }
            let sortedProviders = groupedModels.keys.sorted()
            
            ForEach(sortedProviders, id: \.self) { provider in
                if let models = groupedModels[provider] {
                    Section(header: Text(provider)) {
                        ForEach(models.sorted { $0.displayName < $1.displayName }) { model in
                            HStack {
                                Text(formatModelName(model))
                                Spacer()
                                if model.supportsStructuredOutput {
                                    Image(systemName: "list.bullet.rectangle")
                                        .font(.caption2)
                                        .foregroundColor(.blue)
                                }
                                if model.supportsImages {
                                    Image(systemName: "eye")
                                        .font(.caption2)
                                        .foregroundColor(.purple)
                                }
                                if model.supportsReasoning {
                                    Image(systemName: "brain")
                                        .font(.caption2)
                                        .foregroundColor(.green)
                                }
                            }
                            .tag(model.id)
                        }
                    }
                }
            }
        }
    }
    
    /// Formats a model name for display
    private func formatModelName(_ model: OpenRouterModel) -> String {
        let displayName = model.displayName
        
        // If display name is same as model part of ID, show the full display name
        if displayName == model.modelName {
            return displayName
        }
        
        // Otherwise, show the display name with a shortened version if too long
        if displayName.count > 40 {
            return String(displayName.prefix(37)) + "..."
        }
        
        return displayName
    }
    
    /// Refresh button for the picker
    private var refreshButton: some View {
        Button(action: {
            Task {
                await openRouterService.fetchModels()
            }
        }) {
            if openRouterService.isLoading {
                ProgressView()
                    .scaleEffect(0.8)
            } else {
                Image(systemName: "arrow.clockwise")
                    .font(.footnote)
            }
        }
        .buttonStyle(.borderless)
        .help("Refresh model list")
        .disabled(!appState.hasValidOpenRouterKey)
    }
}
