//
//  LLMProviderSettingsView.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 5/13/25.
//

import SwiftUI

struct LLMProviderSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var showModelSelectionSheet = false
    @AppStorage("openRouterApiKey") private var openRouterApiKey: String = ""
    @AppStorage("openAiApiKey") private var openAiApiKey: String = ""
    
    private var openRouterService: OpenRouterService {
        appState.openRouterService
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("AI Model Configuration")
                .font(.headline)
                .padding(.bottom, 5)
            
            // OpenRouter Configuration Section
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "globe")
                        .foregroundColor(.blue)
                        .frame(width: 20)
                    Text("OpenRouter")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    // Status indicator
                    HStack(spacing: 4) {
                        Circle()
                            .fill(appState.hasValidOpenRouterKey ? .green : .red)
                            .frame(width: 8, height: 8)
                        Text(appState.hasValidOpenRouterKey ? "Connected" : "Not Connected")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // API Key Input
                SecureField("OpenRouter API Key", text: $openRouterApiKey)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: openRouterApiKey) { _, newValue in
                        if !newValue.isEmpty {
                            Task {
                                await openRouterService.fetchModels()
                            }
                        }
                    }
                
                Text("Get your API key from openrouter.ai")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(.controlBackgroundColor))
            .cornerRadius(8)
            
            // TTS Configuration Section  
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "speaker.wave.2")
                        .foregroundColor(.orange)
                        .frame(width: 20)
                    Text("Text-to-Speech (OpenAI)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    // Status indicator
                    HStack(spacing: 4) {
                        Circle()
                            .fill(appState.hasValidOpenAiKey ? .green : .red)
                            .frame(width: 8, height: 8)
                        Text(appState.hasValidOpenAiKey ? "Connected" : "Not Connected")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                SecureField("OpenAI API Key", text: $openAiApiKey)
                    .textFieldStyle(.roundedBorder)
                
                Text("Required for text-to-speech functionality")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(.controlBackgroundColor))
            .cornerRadius(8)
            
            // Model Selection Section
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Available Models")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    if openRouterService.isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Text("\(openRouterService.availableModels.count) models")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                HStack {
                    Button("Choose Models...") {
                        showModelSelectionSheet = true
                    }
                    .disabled(!appState.hasValidOpenRouterKey)
                    
                    Spacer()
                    
                    Button("Refresh Models") {
                        Task {
                            await openRouterService.fetchModels()
                        }
                    }
                    .disabled(!appState.hasValidOpenRouterKey)
                }
            }
            .padding()
            .background(Color(.controlBackgroundColor))
            .cornerRadius(8)
            
            if let error = openRouterService.lastError {
                Text("Error: \(error)")
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }
        }
        .onAppear {
            if !openRouterApiKey.isEmpty && openRouterService.availableModels.isEmpty {
                Task {
                    await openRouterService.fetchModels()
                }
            }
        }
        .sheet(isPresented: $showModelSelectionSheet) {
            OpenRouterModelSelectionSheet()
                .environment(appState)
        }
    }
}