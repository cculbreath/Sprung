//
//  CreateResumeView.swift
//  PhysCloudResume
//
//  Created by Claude on 5/19/25.
//

import SwiftUI
import SwiftData
import AppKit
import Foundation

// Helper view for creating a resume
struct CreateResumeView: View {
    @Environment(ResModelStore.self) private var resModelStore: ResModelStore
    @Environment(ResRefStore.self) private var resRefStore: ResRefStore
    
    var jobApp: JobApp
    var onCreateResume: (ResModel, [ResRef]) -> Void
    
    @State private var selectedModelId: UUID?
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Create Resume")
                .font(.title)
                .fontWeight(.bold)
                .padding(.bottom, 10)
            
            // Resume Model Selector
            VStack(alignment: .leading, spacing: 8) {
                Text("Select Template")
                    .font(.headline)
                    
                HStack {
                    Picker("Select Template", selection: $selectedModelId) {
                        Text("Select a template").tag(nil as UUID?)
                        ForEach(resModelStore.resModels) { model in
                            Text(model.name).tag(model.id as UUID?)
                        }
                    }
                    .frame(minWidth: 200)
                    
                    Button(action: {
                        // Open the model viewer in sheet
//                        showResRefSheet = true
                    }) {
                        Image(systemName: "plus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Add new resume template")
                }
                
                if let selectedModelId = selectedModelId, 
                   let selectedModel = resModelStore.resModels.first(where: { $0.id == selectedModelId }) {
                    HStack {
                        Text("Style:")
                            .fontWeight(.semibold)
                        Text(selectedModel.style)
                            .foregroundColor(.gray)
                    }
                }
            }
            .padding(.bottom, 10)
            
            Spacer()
            
            // Action buttons
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button(action: {
                    if let selectedModelId = selectedModelId,
                       let selectedModel = resModelStore.resModels.first(where: { $0.id == selectedModelId }) {
                        // Pass all sources since they're global and used for AI operations
                        onCreateResume(selectedModel, resRefStore.resRefs)
                        dismiss()
                    }
                }) {
                    HStack {
                        Image(systemName: "doc.badge.plus")
                        Text("Create Resume")
                    }
                    .padding(.horizontal, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(selectedModelId == nil)
            }
        }
        .padding()
        .frame(minWidth: 500, minHeight: 300)
        .onAppear {
            // Default model selection
            if selectedModelId == nil, let firstModel = resModelStore.resModels.first {
                selectedModelId = firstModel.id
            }
        }
    }
}

/// A view showing the details of a ResRef (resume source document)
struct ResRefDetailView: View {
    var resRef: ResRef
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Document: \(resRef.name)")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
            .padding(.bottom, 8)
            
            Divider()
            
            // Show the document content in a scrollable text area
            ScrollView {
                Text(resRef.content)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            }
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
            
            HStack {
                Spacer()
                
                if resRef.enabledByDefault {
                    Label("Enabled by default", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else {
                    Label("Not enabled by default", systemImage: "circle")
                        .foregroundColor(.secondary)
                }
            }
            .padding(.top, 8)
        }
        .padding()
    }
}
