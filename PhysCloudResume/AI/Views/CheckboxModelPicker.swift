//
//  CheckboxModelPicker.swift
//  PhysCloudResume
//
//  Created on 6/2/25.
//

import SwiftUI

/// A reusable checkbox-style model picker component for multi-model selection
/// Models shown are filtered first by user's selection in Settings, then by capability requirements
struct CheckboxModelPicker: View {
    /// The set of selected model IDs
    @Binding var selectedModels: Set<String>
    
    /// Access to app state and OpenRouter service
    @Environment(AppState.self) private var appState
    @Environment(EnabledLLMStore.self) private var enabledLLMStore
    
    /// Optional capability filter for operation-specific requirements
    var requiredCapability: ModelCapability? = nil
    
    /// Title for the GroupBox
    var title: String = "Select Models"
    
    /// Whether to show inside a GroupBox
    var showInGroupBox: Bool = true
    
    /// Whether to show Select All/None buttons
    var showSelectionButtons: Bool = true
    
    private var openRouterService: OpenRouterService {
        appState.openRouterService
    }
    
    var body: some View {
        if showInGroupBox {
            GroupBox(title) {
                content
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                content
            }
        }
    }
    
    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showSelectionButtons && !availableModels.isEmpty {
                HStack {
                    Button("Select All") {
                        for model in availableModels {
                            selectedModels.insert(model.id)
                        }
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    
                    Button("Select None") {
                        for model in availableModels {
                            selectedModels.remove(model.id)
                        }
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    
                    Spacer()
                    
                    if appState.hasValidOpenRouterKey {
                        refreshButton
                    }
                }
            }
            
            modelList
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
    
    private var modelList: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !appState.hasValidOpenRouterKey {
                Text("Configure OpenRouter API key in Settings")
                    .foregroundColor(.secondary)
                    .italic()
            } else if availableModels.isEmpty {
                if openRouterService.isLoading {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Loading models...")
                    }
                    .foregroundColor(.secondary)
                } else if enabledLLMStore.enabledModelIds.isEmpty {
                    Text("No models selected - Configure in Settings")
                        .foregroundColor(.secondary)
                        .italic()
                } else if requiredCapability != nil {
                    Text("No selected models support \(requiredCapability!.displayName)")
                        .foregroundColor(.secondary)
                        .italic()
                } else {
                    Text("No models available")
                        .foregroundColor(.secondary)
                        .italic()
                }
            } else {
                // Group models by provider
                let groupedModels = Dictionary(grouping: availableModels) { $0.providerName }
                let sortedProviders = groupedModels.keys.sorted()
                
                ForEach(sortedProviders, id: \.self) { provider in
                    if let models = groupedModels[provider] {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(provider)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                                
                                // Provider-level selection buttons
                                HStack(spacing: 8) {
                                    Button("All") {
                                        let providerModels = models.map { $0.id }
                                        selectedModels.formUnion(providerModels)
                                    }
                                    .buttonStyle(.borderless)
                                    .font(.caption2)
                                    .foregroundColor(.blue)
                                    
                                    Button("None") {
                                        let providerModels = Set(models.map { $0.id })
                                        selectedModels.subtract(providerModels)
                                    }
                                    .buttonStyle(.borderless)
                                    .font(.caption2)
                                    .foregroundColor(.blue)
                                }
                            }
                            .padding(.top, sortedProviders.first == provider ? 0 : 4)
                            
                            ForEach(models.sorted { $0.displayName < $1.displayName }) { model in
                                Button(action: {
                                    if selectedModels.contains(model.id) {
                                        selectedModels.remove(model.id)
                                    } else {
                                        selectedModels.insert(model.id)
                                    }
                                }) {
                                    HStack {
                                        Image(systemName: selectedModels.contains(model.id) ? "checkmark.circle.fill" : "checkmark.circle")
                                            .foregroundColor(selectedModels.contains(model.id) ? .green : .secondary)
                                            .font(.system(size: 16))
                                        
                                        Text(formatModelName(model))
                                            .font(.system(.body))
                                            .foregroundColor(.primary)
                                        
                                        Spacer()
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }
    
    private var availableModels: [OpenRouterModel] {
        var models = openRouterService.availableModels
        
        // First filter: User's selected models from Settings (global filter)
        models = models.filter { enabledLLMStore.enabledModelIds.contains($0.id) }
        
        // Second filter: Capability requirements for the operation
        if let capability = requiredCapability {
            models = models.filter { model in
                switch capability {
                case .vision:
                    return model.supportsImages
                case .structuredOutput:
                    return model.supportsStructuredOutput
                case .reasoning:
                    return model.supportsReasoning
                case .textOnly:
                    return model.isTextToText && !model.supportsImages
                }
            }
        }
        
        return models
    }
    
    /// Formats a model name for display
    private func formatModelName(_ model: OpenRouterModel) -> String {
        let displayName = model.displayName
        
        // Show the display name with a shortened version if too long
        if displayName.count > 40 {
            return String(displayName.prefix(37)) + "..."
        }
        
        return displayName
    }
    
    /// Refresh button
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

