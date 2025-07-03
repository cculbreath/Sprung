//
//  ReviseCoverLetterView.swift
//  PhysCloudResume
//
//  Created on 6/9/25.
//

import SwiftUI

/// A sheet for revising cover letters with model and operation selection
struct ReviseCoverLetterView: View {
    @Environment(CoverLetterStore.self) private var coverLetterStore: CoverLetterStore
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    @Environment(AppState.self) private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    
    let coverLetter: CoverLetter
    let onRevise: (String, CoverLetterPrompts.EditorPrompts, String) -> Void
    
    @AppStorage("preferredRevisionModel") private var selectedModel: String = ""
    @State private var selectedOperation: CoverLetterPrompts.EditorPrompts = .improve
    @State private var customFeedback: String = ""
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Text("Revise Cover Letter")
                    .font(.title2)
                    .bold()
                
                Text(coverLetter.sequencedName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            // Model Selection
            VStack(alignment: .leading, spacing: 8) {
                Text("AI Model")
                    .font(.headline)
                
                DropdownModelPicker(
                    selectedModel: $selectedModel
                )
            }
            
            Divider()
            
            // Revision Operation Selection
            VStack(alignment: .leading, spacing: 16) {
                Text("Revision Type")
                    .font(.headline)
                
                Picker("Revision Operation", selection: $selectedOperation) {
                    ForEach(CoverLetterPrompts.EditorPrompts.allCases, id: \.self) { operation in
                        Text(operation.operation.rawValue.capitalized).tag(operation)
                    }
                }
                .pickerStyle(.segmented)
                
                // Description of selected operation
                Text(operationDescription(for: selectedOperation))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                
                // Custom feedback field (only for custom operation)
                if selectedOperation == .custom {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Custom Instructions")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        TextEditor(text: $customFeedback)
                            .frame(minHeight: 80)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                        
                        if customFeedback.isEmpty {
                            Text("Provide specific instructions for how to revise the cover letter")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            Spacer()
            
            // Action Buttons
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button("Revise") {
                    if !selectedModel.isEmpty {
                        let feedback = selectedOperation == .custom ? customFeedback : ""
                        onRevise(selectedModel, selectedOperation, feedback)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedModel.isEmpty || (selectedOperation == .custom && customFeedback.isEmpty))
            }
        }
        .padding()
        .frame(width: 450, height: 500)
        .onAppear {
            loadDefaultSelections()
        }
    }
    
    private func loadDefaultSelections() {
        // If no model is already selected and we have a generation model, use that
        if selectedModel.isEmpty, let generationModel = coverLetter.generationModel {
            selectedModel = generationModel
        }
        // Otherwise, the @AppStorage will handle persistence
    }
    
    private func operationDescription(for operation: CoverLetterPrompts.EditorPrompts) -> String {
        switch operation {
        case .improve:
            return "Identifies and improves content and writing quality while maintaining the core message and structure."
        case .zissner:
            return "Applies William Zinsser's 'On Writing Well' editing techniques for clarity, brevity, and elegance."
        case .mimic:
            return "Rewrites the cover letter to match the tone and style of your writing samples."
        case .custom:
            return "Incorporates your specific feedback and instructions for targeted improvements."
        }
    }
}