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
    @Environment(ResRefStore.self) private var resRefStore: ResRefStore
    @Environment(ResModelStore.self) private var resModelStore: ResModelStore
    
    var jobApp: JobApp
    var onCreateResume: (ResModel, [ResRef]) -> Void
    
    @State private var selectedSourceIds: Set<UUID> = []
    @State private var selectedModelId: UUID?
    @State private var showResRefSheet: Bool = false
    @State private var selectedResRef: ResRef?
    @State private var isDropTargeted: Bool = false
    
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
                        showResRefSheet = true
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
            
            // Resume Sources Section
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Select Background Documents")
                        .font(.headline)
                    
                    Spacer()
                    
                    // Add button for new resume source
                    Button(action: {
                        showResRefSheet = true
                    }) {
                        Image(systemName: "plus.circle")
                            .imageScale(.medium)
                    }
                    .buttonStyle(.borderless)
                    .help("Add new background document")
                }
                    
                // Section with selectable resume sources
                List {
                    ForEach(resRefStore.resRefs) { source in
                        HStack {
                            // Content
                            Text(source.name)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedResRef = source
                                }
                            
                            Spacer()
                            
                            // View button
                            Button(action: {
                                selectedResRef = source
                            }) {
                                Image(systemName: "eye")
                                    .foregroundColor(.gray)
                            }
                            .buttonStyle(.borderless)
                            .help("View document details")
                            
                            // Checkmark (more elegant than standard checkbox)
                            Image(systemName: selectedSourceIds.contains(source.id) ? 
                                  "checkmark.circle.fill" : "circle")
                                .foregroundColor(selectedSourceIds.contains(source.id) ? 
                                                .accentColor : .gray)
                                .imageScale(.large)
                                .onTapGesture {
                                    toggleSelection(for: source)
                                }
                        }
                        .contentShape(Rectangle())
                        .padding(.vertical, 2)
                    }
                }
                .frame(height: 220)
                .overlay(
                    Group {
                        if resRefStore.resRefs.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "doc.text")
                                    .font(.system(size: 36))
                                    .foregroundColor(.secondary)
                                
                                Text("No background documents available")
                                    .foregroundColor(.secondary)
                                
                                Text("Drag and drop files or add new documents")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Button("Add Document") {
                                    showResRefSheet = true
                                }
                                .buttonStyle(.borderedProminent)
                                .padding(.top, 8)
                            }
                            .padding()
                        }
                    }
                )
            }
            
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
                        let selectedRefs = resRefStore.resRefs.filter { 
                            selectedSourceIds.contains($0.id) 
                        }
                        onCreateResume(selectedModel, selectedRefs)
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
                .disabled(selectedModelId == nil || selectedSourceIds.isEmpty)
            }
        }
        .padding()
        .frame(minWidth: 500, minHeight: 400)
        .sheet(item: $selectedResRef) { resRef in
            // Show the ResRef details view
            ResRefDetailView(resRef: resRef)
                .frame(width: 600, height: 400)
        }
        .sheet(isPresented: $showResRefSheet) {
            if resModelStore.resModels.isEmpty {
                // If no resume models exist, show model form first
                ResModelFormView(sheetPresented: $showResRefSheet)
                    .frame(minWidth: 500, minHeight: 600)
            } else {
                // Show resume source form with drag and drop functionality
                ResRefFormView(isSheetPresented: $showResRefSheet)
                    .frame(width: 500)
            }
        }
        .onDrop(of: ["public.file-url"], isTargeted: $isDropTargeted) { providers in
            return handleFileDrop(providers: providers)
        }
        .onChange(of: isDropTargeted) { _, newValue in
            // Visual indicator could be added here if needed
        }
        .onAppear {
            // Pre-select default sources
            for source in resRefStore.resRefs where source.enabledByDefault {
                selectedSourceIds.insert(source.id)
            }
            
            // Default model selection
            if selectedModelId == nil, let firstModel = resModelStore.resModels.first {
                selectedModelId = firstModel.id
            }
        }
    }
    
    private func toggleSelection(for source: ResRef) {
        if selectedSourceIds.contains(source.id) {
            selectedSourceIds.remove(source.id)
        } else {
            selectedSourceIds.insert(source.id)
        }
    }
    
    /// Handles file drop for creating new resume sources directly
    private func handleFileDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                    guard let urlData = item as? Data,
                          let url = URL(dataRepresentation: urlData, relativeTo: nil)
                    else {
                        return
                    }

                    do {
                        let fileName = url.deletingPathExtension().lastPathComponent
                        let text = try String(contentsOf: url, encoding: .utf8)
                        
                        // Create a new ResRef on the main thread
                        DispatchQueue.main.async {
                            let newSource = ResRef(
                                name: fileName,
                                content: text,
                                enabledByDefault: true
                            )
                            
                            // Add to store and select it
                            resRefStore.addResRef(newSource)
                            selectedSourceIds.insert(newSource.id)
                        }

                    } catch {
                        Logger.debug("Failed to read dropped file: \(error.localizedDescription)")
                    }
                }
                return true
            }
        }
        return false
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
