//
//  GenerateCoverLetterView.swift
//  PhysCloudResume
//
//  Created on 6/9/25.
//

import SwiftUI
import SwiftData

/// A unified view for generating cover letters that combines model selection with source management
struct GenerateCoverLetterView: View {
    @Environment(CoverRefStore.self) var coverRefStore: CoverRefStore
    @Environment(CoverLetterStore.self) var coverLetterStore: CoverLetterStore
    @Environment(AppState.self) private var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let jobApp: JobApp
    let onGenerate: (String, [CoverRef], Bool) -> Void
    
    // Live SwiftData query to automatically refresh on model changes
    @Query(sort: \CoverRef.name) private var allCoverRefs: [CoverRef]
    
    @AppStorage("preferredCoverLetterModel") private var selectedModel: String = ""
    @State private var includeResumeRefs: Bool = true
    @State private var selectedBackgroundFacts: Set<String> = []
    @State private var selectedWritingSamples: Set<String> = []
    
    var body: some View {
        VStack(spacing: 0) {
            // Header - Fixed
            VStack(spacing: 8) {
                Text("Generate Cover Letter")
                    .font(.title2)
                    .bold()
                
                Text(jobApp.companyName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.top)
            
            // Model Selection - Fixed
            VStack(alignment: .leading, spacing: 8) {
                Text("AI Model")
                    .font(.headline)
                
                DropdownModelPicker(
                    selectedModel: $selectedModel,
                    requiredCapability: nil
                )
            }
            .padding(.horizontal)
            .padding(.top)
            
            Divider()
                .padding(.horizontal)
            
            // Scrollable content area
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 20) {
                    // Source Management using shared component
                    CoverRefSelectionManagerView(
                        includeResumeRefs: $includeResumeRefs,
                        selectedBackgroundFacts: $selectedBackgroundFacts,
                        selectedWritingSamples: $selectedWritingSamples,
                        showGroupBox: false
                    )
                    
                    // Extra padding at bottom for better scrolling
                    Color.clear.frame(height: 20)
                }
                .padding(.horizontal)
                .padding(.top)
            }
            
            // Action Buttons - Fixed at bottom
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button("Generate") {
                    if !selectedModel.isEmpty {
                        let selectedRefs = allCoverRefs.filter { ref in
                            selectedBackgroundFacts.contains(ref.id.description) ||
                            selectedWritingSamples.contains(ref.id.description)
                        }
                        onGenerate(selectedModel, selectedRefs, includeResumeRefs)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedModel.isEmpty)
            }
            .padding(.horizontal)
            .padding(.bottom)
            .background(Color(.windowBackgroundColor))
        }
        .frame(width: 500, height: 600)
        .onAppear {
            loadDefaultSelections()
        }
    }
    
    private func loadDefaultSelections() {
        // Use the selected model from the dropdown - it will default to the preferred model
        
        // Pre-select enabled by default refs
        let backgroundFacts = allCoverRefs.filter { $0.type == .backgroundFact }
        let writingSamples = allCoverRefs.filter { $0.type == .writingSample }
        
        for ref in backgroundFacts where ref.enabledByDefault {
            selectedBackgroundFacts.insert(ref.id.description)
        }
        
        for ref in writingSamples where ref.enabledByDefault {
            selectedWritingSamples.insert(ref.id.description)
        }
    }
}

/// A row showing a checkable reference with delete capability
struct CheckableRefRow: View {
    let ref: CoverRef
    let isSelected: Bool
    let onToggle: (Bool) -> Void
    let onDelete: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 8) {
            Button(action: {
                onToggle(!isSelected)
            }) {
                HStack(spacing: 8) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isSelected ? .accentColor : .secondary)
                        .font(.system(size: 18))
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ref.name)
                            .font(.body)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        if !ref.content.isEmpty {
                            Text(ref.content)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                    }
                    
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            
            if isHovering {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.gray.opacity(isHovering ? 0.1 : 0))
        )
        .onHover { hovering in
            isHovering = hovering
        }
    }
}