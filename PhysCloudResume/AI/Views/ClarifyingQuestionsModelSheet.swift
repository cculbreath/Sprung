//
//  ClarifyingQuestionsModelSheet.swift
//  PhysCloudResume
//
//  Created on 6/4/25.
//

import SwiftUI

/// Model selection sheet specifically for clarifying questions workflow
/// Only shows models that support structured output
struct ClarifyingQuestionsModelSheet: View {
    @Binding var isPresented: Bool
    let onModelSelected: (String) -> Void
    
    @State private var selectedModel: String = ""
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    
    private var openRouterService: OpenRouterService {
        appState.openRouterService
    }
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 12) {
                Image("custom.wand.and.sparkles.badge.questionmark")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)
                    .symbolRenderingMode(.hierarchical)
                
                Text("Select AI Model for Clarifying Questions")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Choose an AI model to generate clarifying questions and customize your resume")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top)
            
            // Model Selection
            VStack(spacing: 16) {
                DropdownModelPicker(
                    selectedModel: $selectedModel,
                    requiredCapability: .structuredOutput,
                    title: "AI Model",
                    showInGroupBox: true
                )
                
                if !selectedModel.isEmpty {
                    if let model = openRouterService.findModel(id: selectedModel) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Selected Model Details")
                                .font(.headline)
                            
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(model.displayName)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    
                                    Text(model.costDescription)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    
                                    if let description = model.description {
                                        Text(description)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(3)
                                    }
                                }
                                
                                Spacer()
                                
                                // Capability badges
                                VStack(alignment: .trailing, spacing: 4) {
                                    if model.supportsStructuredOutput {
                                        Label("Structured Output", systemImage: "list.bullet.rectangle")
                                            .font(.caption)
                                            .foregroundStyle(.green)
                                    }
                                    
                                    if model.supportsReasoning {
                                        Label("Reasoning", systemImage: "brain")
                                            .font(.caption)
                                            .foregroundStyle(.blue)
                                    }
                                }
                            }
                        }
                        .padding()
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                    }
                }
            }
            
            Spacer()
            
            // Buttons
            HStack(spacing: 16) {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
                
                Spacer()
                
                Button("Continue with Clarifying Questions") {
                    onModelSelected(selectedModel)
                    dismiss()
                }
                .keyboardShortcut(.return)
                .disabled(selectedModel.isEmpty)
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(minWidth: 600, idealWidth: 700, minHeight: 500)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            // Auto-select the first available model if none selected
            if selectedModel.isEmpty {
                let availableModels = openRouterService.availableModels
                    .filter { appState.selectedOpenRouterModels.contains($0.id) }
                    .filter { $0.supportsStructuredOutput }
                
                if let firstModel = availableModels.first {
                    selectedModel = firstModel.id
                }
            }
        }
    }
}

#Preview {
    ClarifyingQuestionsModelSheet(
        isPresented: .constant(true),
        onModelSelected: { _ in }
    )
    .environment(AppState())
}