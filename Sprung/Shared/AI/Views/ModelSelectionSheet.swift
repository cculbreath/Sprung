//
//  ModelSelectionSheet.swift
//  Sprung
//
//  Created by Christopher Culbreath on 6/4/25.
//

import SwiftUI

/// Unified model selection sheet for all single model operations
/// Provides consistent UX and eliminates code duplication
struct ModelSelectionSheet: View {
    // MARK: - Properties
    
    let title: String
    let requiredCapability: ModelCapability?
    let operationKey: String? // Optional key for per-operation model persistence
    @Binding var isPresented: Bool
    let onModelSelected: (String) -> Void
    
    // MARK: - State
    
    @State private var selectedModel: String = ""
    @AppStorage("lastSelectedModel") private var lastSelectedModelGlobal: String = ""
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text(title)
                    .font(.headline)
                    .padding(.top)
                
                DropdownModelPicker(
                    selectedModel: $selectedModel,
                    requiredCapability: requiredCapability,
                    title: "AI Model"
                )
                
                HStack(spacing: 12) {
                    Button("Cancel") {
                        isPresented = false
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Continue") {
                        // Save the selected model for future use
                        saveSelectedModel(selectedModel)
                        isPresented = false
                        onModelSelected(selectedModel)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedModel.isEmpty)
                }
                
                Spacer()
            }
            .padding()
            .frame(width: 400, height: 250)
            .onAppear {
                loadLastSelectedModel()
            }
        }
    }
    
    // MARK: - Private Methods
    
    /// Load the last selected model based on operation key or global preference
    private func loadLastSelectedModel() {
        if let operationKey = operationKey {
            // Try to load per-operation model first
            let perOperationKey = "lastSelectedModel_\(operationKey)"
            if let savedModel = UserDefaults.standard.string(forKey: perOperationKey), !savedModel.isEmpty {
                selectedModel = savedModel
                return
            }
        }
        
        // Fall back to global last selected model
        if !lastSelectedModelGlobal.isEmpty {
            selectedModel = lastSelectedModelGlobal
        }
    }
    
    /// Save the selected model for future use
    private func saveSelectedModel(_ model: String) {
        // Save globally
        lastSelectedModelGlobal = model
        
        // Save per-operation if key is provided
        if let operationKey = operationKey {
            let perOperationKey = "lastSelectedModel_\(operationKey)"
            UserDefaults.standard.set(model, forKey: perOperationKey)
        }
    }
}
