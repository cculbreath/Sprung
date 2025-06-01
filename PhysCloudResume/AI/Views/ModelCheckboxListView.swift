//
//  ModelCheckboxListView.swift
//  PhysCloudResume
//
//  Created by Claude on 5/20/25.
//

import SwiftUI

/// A reusable view for selecting multiple OpenRouter AI models with checkboxes
struct ModelCheckboxListView: View {
    /// The currently selected model IDs
    @Binding var selectedModels: Set<String>
    
    /// Access to app state and OpenRouter service
    @Environment(AppState.self) private var appState
    
    /// Optional capability filter to restrict which models are shown
    var capabilityFilter: ModelCapability? = nil
    
    /// Whether to show raw model names or display names
    var sanitizeModelNames: Bool = true
    
    /// Whether to respect user's model selection preferences
    var useModelSelection: Bool = true
    
    private var openRouterService: OpenRouterService {
        appState.openRouterService
    }
    
    /// Initializes a new model checkbox list view
    /// - Parameters:
    ///   - selectedModels: Binding to the selected model IDs set
    ///   - capabilityFilter: Optional capability to filter models by
    ///   - sanitizeModelNames: Whether to show display names or raw model names
    ///   - useModelSelection: Whether to respect user's model selection preferences
    init(
        selectedModels: Binding<Set<String>>,
        capabilityFilter: ModelCapability? = nil,
        sanitizeModelNames: Bool = true,
        useModelSelection: Bool = true
    ) {
        self._selectedModels = selectedModels
        self.capabilityFilter = capabilityFilter
        self.sanitizeModelNames = sanitizeModelNames
        self.useModelSelection = useModelSelection
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with controls
            HStack {
                Text("Available Models (\(availableModels.count))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if !availableModels.isEmpty {
                    Button("Select All") {
                        selectedModels = Set(availableModels.map { $0.id })
                    }
                    .font(.caption)
                    
                    Button("Clear All") {
                        selectedModels.removeAll()
                    }
                    .font(.caption)
                }
                
                refreshButton
            }
            
            // Model list
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if !appState.hasValidOpenRouterKey {
                        Text("Configure OpenRouter API key in Settings")
                            .foregroundColor(.secondary)
                            .padding()
                    } else if availableModels.isEmpty {
                        if openRouterService.isLoading {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Loading models...")
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                        } else if useModelSelection && !appState.selectedOpenRouterModels.isEmpty {
                            Text("No models match criteria")
                                .foregroundColor(.secondary)
                                .padding()
                        } else if useModelSelection {
                            Text("No models selected - Configure in Settings")
                                .foregroundColor(.secondary)
                                .padding()
                        } else {
                            Text("No models available")
                                .foregroundColor(.secondary)
                                .padding()
                        }
                    } else {
                        // Group models by provider
                        let groupedModels = Dictionary(grouping: availableModels) { $0.providerName }
                        let sortedProviders = groupedModels.keys.sorted()
                        
                        ForEach(sortedProviders, id: \.self) { provider in
                            if let models = groupedModels[provider] {
                                // Provider header
                                Text(provider)
                                    .font(.headline)
                                    .padding(.top, 8)
                                
                                // Models for this provider
                                ForEach(models.sorted { $0.displayName < $1.displayName }) { model in
                                    modelRow(for: model)
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 300)
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
    
    /// Creates a row for a single model
    private func modelRow(for model: OpenRouterModel) -> some View {
        HStack {
            // Checkbox
            Button(action: {
                if selectedModels.contains(model.id) {
                    selectedModels.remove(model.id)
                } else {
                    selectedModels.insert(model.id)
                }
            }) {
                Image(systemName: selectedModels.contains(model.id) ? "checkmark.square.fill" : "square")
                    .foregroundColor(selectedModels.contains(model.id) ? .blue : .secondary)
            }
            .buttonStyle(.plain)
            
            // Model name
            VStack(alignment: .leading, spacing: 2) {
                Text(sanitizeModelNames ? formatModelName(model) : model.id)
                    .font(.body)
                
                if let description = model.description, description != model.displayName && !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            
            Spacer()
            
            // Capability indicators
            HStack(spacing: 4) {
                if model.supportsStructuredOutput {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.caption2)
                        .foregroundColor(.blue)
                        .help("Supports structured output")
                }
                if model.supportsImages {
                    Image(systemName: "eye")
                        .font(.caption2)
                        .foregroundColor(.purple)
                        .help("Supports images")
                }
                if model.supportsReasoning {
                    Image(systemName: "brain")
                        .font(.caption2)
                        .foregroundColor(.green)
                        .help("Supports reasoning")
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(selectedModels.contains(model.id) ? Color.blue.opacity(0.1) : Color.clear)
        )
        .onTapGesture {
            if selectedModels.contains(model.id) {
                selectedModels.remove(model.id)
            } else {
                selectedModels.insert(model.id)
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
        if displayName.count > 50 {
            return String(displayName.prefix(47)) + "..."
        }
        
        return displayName
    }
    
    /// Refresh button for the list
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