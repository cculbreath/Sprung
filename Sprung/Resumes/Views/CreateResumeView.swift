//
//  CreateResumeView.swift
//  Sprung
//

import SwiftUI
import SwiftData
import AppKit
import Foundation

// Helper view for creating a resume
struct CreateResumeView: View {
    @Environment(TemplateStore.self) private var templateStore: TemplateStore
    @Environment(ResRefStore.self) private var resRefStore: ResRefStore
    
    var jobApp: JobApp
    var onCreateResume: (Template, [ResRef]) -> Void
    
    @State private var selectedTemplateID: UUID?
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        let templates = templateStore.templates()
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
                    Picker("Select Template", selection: $selectedTemplateID) {
                        Text("Select a template").tag(nil as UUID?)
                        ForEach(templates) { template in
                            Text(template.name).tag(template.id as UUID?)
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
                
                if let templateID = selectedTemplateID,
                   let selectedTemplate = templates.first(where: { $0.id == templateID }) {
                    HStack {
                        Text("Style:")
                            .fontWeight(.semibold)
                        Text(selectedTemplate.name)
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
                    if let templateID = selectedTemplateID,
                       let selectedTemplate = templates.first(where: { $0.id == templateID }) {
                        onCreateResume(selectedTemplate, resRefStore.resRefs)
                        dismiss()
                    } else {
                        // No template selected; allow user to try again
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
                .disabled(selectedTemplateID == nil)
            }
        }
        .padding()
        .frame(minWidth: 500, minHeight: 300)
        .onAppear {
            // Default model selection
            if selectedTemplateID == nil, let firstTemplate = templates.first {
                selectedTemplateID = firstTemplate.id
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
