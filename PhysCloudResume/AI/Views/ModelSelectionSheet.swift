//
//  ModelSelectionSheet.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 5/30/25.
//

import SwiftUI

struct ModelSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @EnvironmentObject private var modelService: ModelService
    
    @State private var selectedModels: Set<String> = []
    @State private var isLoading = false
    
    // API keys for filtering available providers
    @AppStorage("openAiApiKey") private var openAiApiKey: String = "none"
    @AppStorage("claudeApiKey") private var claudeApiKey: String = "none"
    @AppStorage("grokApiKey") private var grokApiKey: String = "none"
    @AppStorage("geminiApiKey") private var geminiApiKey: String = "none"
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Text("Select Available Models")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Choose which models appear in model selection menus")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            
            Divider()
            
            // Model selection area
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    let allModels = modelService.getAllModels()
                    let providers = getValidProviders()
                    
                    if providers.isEmpty {
                        Text("No providers with valid API keys found")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding()
                    } else {
                        ForEach(providers, id: \.self) { provider in
                            if let models = allModels[provider], !models.isEmpty {
                                providerSection(provider: provider, models: models)
                            }
                        }
                    }
                }
                .padding()
            }
            
            Divider()
            
            // Action buttons
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
                
                Spacer()
                
                Button("Apply") {
                    print("🔍 ModelSelectionSheet Apply Debug:")
                    print("   selectedModels count: \(selectedModels.count)")
                    print("   selectedModels (first 5): \(Array(selectedModels).prefix(5))")
                    print("   Before assignment - appState.selectedModels count: \(appState.selectedModels.count)")
                    appState.selectedModels = selectedModels
                    print("   After assignment - appState.selectedModels count: \(appState.selectedModels.count)")
                    print("   appState.selectedModels (first 5): \(Array(appState.selectedModels).prefix(5))")
                    dismiss()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .disabled(selectedModels.isEmpty)
            }
            .padding()
        }
        .frame(width: 500, height: 600)
        .onAppear {
            // Initialize with current selections
            selectedModels = appState.selectedModels
        }
    }
    
    @ViewBuilder
    private func providerSection(provider: String, models: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Provider header with select all/none buttons
            HStack {
                Label(provider.capitalized, systemImage: providerIcon(for: provider))
                    .font(.headline)
                
                Spacer()
                
                HStack(spacing: 8) {
                    Button("All") {
                        // Add all models from this provider
                        for model in models {
                            selectedModels.insert("\(provider):\(model)")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    Button("None") {
                        // Remove all models from this provider
                        for model in models {
                            selectedModels.remove("\(provider):\(model)")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            
            // Model checkboxes (same style as CreateResumeView)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(models.sorted(), id: \.self) { model in
                    ModelRow(
                        model: model,
                        provider: provider,
                        isSelected: selectedModels.contains("\(provider):\(model)"),
                        onToggle: {
                            let modelId = "\(provider):\(model)"
                            if selectedModels.contains(modelId) {
                                selectedModels.remove(modelId)
                            } else {
                                selectedModels.insert(modelId)
                            }
                        }
                    )
                }
            }
            .padding(.leading, 20)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private func getValidProviders() -> [String] {
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
    
    private func providerIcon(for provider: String) -> String {
        switch provider {
        case AIModels.Provider.openai:
            return "sparkles"
        case AIModels.Provider.claude:
            return "brain"
        case AIModels.Provider.grok:
            return "bolt.fill"
        case AIModels.Provider.gemini:
            return "star.fill"
        default:
            return "questionmark.circle"
        }
    }
}

/// Individual model row with hover effect and full-row clicking
private struct ModelRow: View {
    let model: String
    let provider: String
    let isSelected: Bool
    let onToggle: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        HStack {
            Text(model)
                .font(.system(.body))
                .foregroundColor(.primary)
            
            Spacer()
            
            // Checkmark (same style as CreateResumeView)
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isSelected ? .accentColor : .gray)
                .imageScale(.large)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(backgroundForState)
        .cornerRadius(6)
        .onTapGesture {
            onToggle()
        }
        .onHover { hovering in
            isHovering = hovering
        }
    }
    
    private var backgroundForState: Color {
        if isSelected {
            return Color.accentColor.opacity(0.15)
        } else if isHovering {
            return Color.secondary.opacity(0.08)
        } else {
            return Color.clear
        }
    }
}