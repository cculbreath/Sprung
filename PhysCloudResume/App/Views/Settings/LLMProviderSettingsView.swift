//
//  LLMProviderSettingsView.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 5/13/25.
//

import SwiftUI

struct LLMProviderSettingsView: View {
    // AppStorage for API keys to check if they're available
    @AppStorage("openAiApiKey") private var openAiApiKey: String = "none"
    @AppStorage("claudeApiKey") private var claudeApiKey: String = "none"
    @AppStorage("grokApiKey") private var grokApiKey: String = "none"
    @AppStorage("geminiApiKey") private var geminiApiKey: String = "none"
    
    // Fetch status of models to show accurate API key status
    @ObservedObject private var modelService = ModelService()
    
    // Access to app state
    @Environment(AppState.self) private var appState
    
    // State for showing model selection sheet
    @State private var showModelSelectionSheet = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("AI Provider API Keys")
                .font(.headline)
                .padding(.bottom, 5)
            
            // Status indicators for each provider
            // Provider status rows
            VStack(alignment: .leading, spacing: 8) {
                // OpenAI Status
                providerStatusRow(
                    name: "OpenAI",
                    icon: "sparkles",
                    provider: AIModels.Provider.openai,
                    apiKey: openAiApiKey
                )
                
                // Claude Status
                providerStatusRow(
                    name: "Claude",
                    icon: "brain",
                    provider: AIModels.Provider.claude,
                    apiKey: claudeApiKey
                )
                
                // Grok Status
                providerStatusRow(
                    name: "Grok",
                    icon: "bolt.fill",
                    provider: AIModels.Provider.grok,
                    apiKey: grokApiKey
                )
                
                // Gemini Status
                providerStatusRow(
                    name: "Gemini",
                    icon: "star.fill",
                    provider: AIModels.Provider.gemini,
                    apiKey: geminiApiKey
                )
                
                // Action buttons
                HStack {
                    // Choose Models button - only show if at least one provider has valid API key
                    if hasAnyValidApiKey() {
                        Button(action: {
                            showModelSelectionSheet = true
                        }) {
                            HStack {
                                Image(systemName: "checklist")
                                Text("Choose Models...")
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(BorderlessButtonStyle())
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(4)
                    }
                    
                    Spacer()
                    
                    // Refresh button for validation
                    Button(action: {
                        // Re-validate all API keys
                        let apiKeys = [
                            AIModels.Provider.openai: openAiApiKey,
                            AIModels.Provider.claude: claudeApiKey,
                            AIModels.Provider.grok: grokApiKey,
                            AIModels.Provider.gemini: geminiApiKey
                        ]
                        modelService.fetchAllModels(apiKeys: apiKeys)
                    }) {
                        HStack {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("Refresh Validation")
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(4)
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 10)
            
            Text("Configure API keys in the Settings dialog. Models will appear in the model picker when their API key is configured.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 10)
                .padding(.top, 5)
        }
        .padding(10)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.9))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.7), lineWidth: 1)
        )
        .onAppear {
            // Check current status of models to ensure we display accurate key validation status
            let apiKeys = [
                AIModels.Provider.openai: openAiApiKey,
                AIModels.Provider.claude: claudeApiKey,
                AIModels.Provider.grok: grokApiKey,
                AIModels.Provider.gemini: geminiApiKey
            ]
            modelService.fetchAllModels(apiKeys: apiKeys)
        }
        .sheet(isPresented: $showModelSelectionSheet) {
            ModelSelectionSheet()
                .environmentObject(modelService)
                .environment(appState)
        }
    }
    
    // Check if any provider has a valid API key
    private func hasAnyValidApiKey() -> Bool {
        let providers = [
            (AIModels.Provider.openai, openAiApiKey),
            (AIModels.Provider.claude, claudeApiKey),
            (AIModels.Provider.grok, grokApiKey),
            (AIModels.Provider.gemini, geminiApiKey)
        ]
        
        for (provider, apiKey) in providers {
            // Check if key is present and has valid format
            if apiKey != "none" && !apiKey.isEmpty {
                if APIKeyValidator.validateAPIKey(apiKey, for: provider) != nil {
                    // Also check if the fetch was successful
                    if let fetchStatus = modelService.fetchStatus[provider] {
                        if case .success = fetchStatus {
                            return true
                        }
                    }
                }
            }
        }
        
        return false
    }
    
    // Reusable provider status row with validity checking
    @ViewBuilder
    private func providerStatusRow(name: String, icon: String, provider: String, apiKey: String) -> some View {
        // Check API validation status
        let statusView = getAPIKeyStatus(provider: provider, apiKey: apiKey)
        
        HStack {
            Image(systemName: icon)
                .foregroundColor(.secondary)
            Text(name)
            Spacer()
            
            statusView
        }
    }
    
    // Get API key status view based on API key and model fetching status
    @ViewBuilder
    private func getAPIKeyStatus(provider: String, apiKey: String) -> some View {
        // First check if the key is present
        if apiKey == "none" || apiKey.isEmpty {
            Text("Not configured")
                .foregroundColor(.red)
        }
        // Check if the key format is valid
        else if APIKeyValidator.validateAPIKey(apiKey, for: provider) == nil {
            HStack {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 8, height: 8)
                Text("Invalid format")
                    .foregroundColor(.orange)
            }
        }
        // Now check the actual fetch status
        else if let fetchStatus = modelService.fetchStatus[provider] {
            switch fetchStatus {
            case .success:
                HStack {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    Text("Valid")
                        .foregroundColor(.green)
                }
            case .error(_):
                HStack {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                    Text("Error: API key invalid")
                        .foregroundColor(.red)
                }
            case .inProgress:
                HStack {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 8, height: 8)
                    Text("Validating...")
                        .foregroundColor(.blue)
                }
            case .notStarted:
                HStack {
                    Circle()
                        .fill(Color.gray)
                        .frame(width: 8, height: 8)
                    Text("Not validated")
                        .foregroundColor(.gray)
                }
            }
        }
        // If we have no fetch status yet, show configured but not validated
        else {
            HStack {
                Circle()
                    .fill(Color.gray)
                    .frame(width: 8, height: 8)
                Text("Configured")
                    .foregroundColor(.gray)
            }
        }
    }
}