//
//  ModelSelectionSheet.swift
//  PhysCloudResume
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
    @Binding var isPresented: Bool
    let onModelSelected: (String) -> Void
    
    // MARK: - State
    
    @State private var selectedModel: String = ""
    
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
        }
    }
}

// MARK: - Preview

#Preview {
    ModelSelectionSheet(
        title: "Choose Model for Resume Customization",
        requiredCapability: .structuredOutput,
        isPresented: .constant(true),
        onModelSelected: { modelId in
            print("Selected model: \(modelId)")
        }
    )
}