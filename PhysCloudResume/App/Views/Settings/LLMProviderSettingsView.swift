//
//  LLMProviderSettingsView.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 5/13/25.
//

import SwiftUI

struct LLMProviderSettingsView: View {
    @Environment(\.appState) private var appState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("AI Model Configuration")
                .font(.headline)
                .padding(.bottom, 5)
            
            Text("Additional AI model configuration options will be added here in future updates, including fallback rules and model selection preferences.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding()
                .background(Color(.controlBackgroundColor))
                .cornerRadius(8)
        }
    }
}