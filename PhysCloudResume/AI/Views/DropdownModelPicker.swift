//
//  DropdownModelPicker.swift
//  PhysCloudResume
//
//  Created on 6/2/25.
//

import SwiftUI

/// A reusable dropdown-style model picker component that displays in a GroupBox
/// Models shown are filtered first by user's selection in Settings, then by capability requirements
struct DropdownModelPicker: View {
    /// The currently selected model ID
    @Binding var selectedModel: String
    
    /// Access to app state and OpenRouter service
    @Environment(AppState.self) private var appState
    @Environment(EnabledLLMStore.self) private var enabledLLMStore
    
    /// Optional capability filter for operation-specific requirements
    var requiredCapability: ModelCapability? = nil
    
    /// Title for the GroupBox label
    var title: String = "AI Model"
    
    /// Whether to show inside a GroupBox
    var showInGroupBox: Bool = true
    
    /// Optional special option to show at the top (label, value)
    var includeSpecialOption: (String, String)? = nil
    
    private var openRouterService: OpenRouterService {
        appState.openRouterService
    }
    
    var body: some View {
        if showInGroupBox {
            GroupBox(label: Text(title).fontWeight(.medium)) {
                modelPickerContent
                    .padding(.vertical, 4)
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                modelPickerContent
            }
        }
    }
    
    private var modelPickerContent: some View {
        HStack {
            Picker("", selection: $selectedModel) {
                pickerContent
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .id(enabledLLMStore.enabledModelIds) // Force refresh when enabled models change
            
            if appState.hasValidOpenRouterKey {
                refreshButton
            }
        }
        .onAppear {
            // Fetch models if we don't have any and have a valid API key
            if appState.hasValidOpenRouterKey && openRouterService.availableModels.isEmpty {
                Task {
                    await openRouterService.fetchModels()
                }
            }
        }
        .onChange(of: enabledLLMStore.enabledModelIds) { _, newModelIds in
            // Reset selection if the currently selected model is no longer enabled
            if !newModelIds.contains(selectedModel) {
                selectedModel = ""
            }
            Logger.debug("🔄 [DropdownModelPicker] Model list updated - \(newModelIds.count) enabled models")
        }
        .onChange(of: openRouterService.availableModels) { _, _ in
            // Also refresh when the available models from OpenRouter change
            Logger.debug("🔄 [DropdownModelPicker] Available models refreshed from OpenRouter")
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
    
    @ViewBuilder
    private var pickerContent: some View {
        // Add special option first if provided
        if let specialOption = includeSpecialOption {
            Text(specialOption.0)
                .tag(specialOption.1)
            
            if appState.hasValidOpenRouterKey && !availableModels.isEmpty {
                Divider()
            }
        }
        
        if !appState.hasValidOpenRouterKey {
            Text("Configure OpenRouter API key in Settings")
                .foregroundColor(.secondary)
                .tag("")
        } else if availableModels.isEmpty {
            if openRouterService.isLoading {
                Text("Loading models...")
                    .foregroundColor(.secondary)
                    .tag("")
            } else if enabledLLMStore.enabledModelIds.isEmpty {
                Text("No models selected - Configure in Settings")
                    .foregroundColor(.secondary)
                    .tag("")
            } else if requiredCapability != nil {
                let capName = requiredCapability?.displayName ?? "required capability"
                Text("No selected models support \(capName)")
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
                            Text(formatModelName(model))
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
        
        // Show the display name with a shortened version if too long
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
