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
    
    /// Optional capability filter for operation-specific requirements
    var requiredCapability: ModelCapability? = nil
    
    /// Title for the GroupBox label
    var title: String = "AI Model"
    
    /// Whether to show inside a GroupBox
    var showInGroupBox: Bool = true
    
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
    }
    
    private var availableModels: [OpenRouterModel] {
        var models = openRouterService.availableModels
        
        // First filter: User's selected models from Settings (global filter)
        models = models.filter { appState.selectedOpenRouterModels.contains($0.id) }
        
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
        if !appState.hasValidOpenRouterKey {
            Text("Configure OpenRouter API key in Settings")
                .foregroundColor(.secondary)
                .tag("")
        } else if availableModels.isEmpty {
            if openRouterService.isLoading {
                Text("Loading models...")
                    .foregroundColor(.secondary)
                    .tag("")
            } else if appState.selectedOpenRouterModels.isEmpty {
                Text("No models selected - Configure in Settings")
                    .foregroundColor(.secondary)
                    .tag("")
            } else if requiredCapability != nil {
                Text("No selected models support \(requiredCapability!.displayName)")
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