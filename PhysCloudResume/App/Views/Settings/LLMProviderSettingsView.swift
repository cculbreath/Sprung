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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("AI Provider API Keys")
                .font(.headline)
                .padding(.bottom, 5)
            
            // Status indicators for each provider
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundColor(.secondary)
                    Text("OpenAI")
                    Spacer()
                    if openAiApiKey == "none" {
                        Text("Not configured")
                            .foregroundColor(.red)
                    } else {
                        HStack {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                            Text("Configured")
                                .foregroundColor(.green)
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            
            Text("Configure API keys in the Settings dialog. OpenAI models will appear in the model picker when their API key is configured.")
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
    }
}
