//
//  ImportJobAppsFromURLsView.swift
//  PhysCloudResume
//
//  Created by Claude on 5/23/25.
//

import SwiftUI
import SwiftData

struct ImportJobAppsFromURLsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(JobAppStore.self) private var jobAppStore
    
    @State private var isImporting = false
    @State private var showFilePicker = false
    @State private var importProgress: Double = 0
    @State private var currentJobName = ""
    @State private var importedCount = 0
    @State private var skippedCount = 0
    @State private var totalCount = 0
    @State private var errorMessage: String?
    @State private var showError = false
    
    init() {
        Logger.debug("🟣 ImportJobAppsFromURLsView initialized")
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "square.and.arrow.down.on.square")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)
                    .symbolRenderingMode(.hierarchical)
                
                Text("Import Job Applications from URLs")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Import job applications from exported JSON file")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top)
            
            Divider()
            
            if isImporting {
                // Progress view
                VStack(spacing: 16) {
                    ProgressView(value: importProgress) {
                        Text("Importing \(Int(importProgress * 100))%")
                            .font(.headline)
                    }
                    .progressViewStyle(.linear)
                    
                    if !currentJobName.isEmpty {
                        Text("Processing: \(currentJobName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack(spacing: 20) {
                        Label("\(importedCount) imported", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Label("\(skippedCount) skipped", systemImage: "xmark.circle")
                            .foregroundStyle(.orange)
                    }
                    .font(.caption)
                }
                .frame(maxWidth: .infinity)
                .padding()
            } else if importedCount > 0 {
                // Success view
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.green)
                    
                    Text("Import Complete!")
                        .font(.title3)
                        .fontWeight(.semibold)
                    
                    Text("Successfully imported \(importedCount) job applications")
                        .foregroundStyle(.secondary)
                    
                    if skippedCount > 0 {
                        Text("(\(skippedCount) entries were skipped)")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .padding()
            } else {
                // Initial state
                VStack(spacing: 16) {
                    Text("Select an exported JSON file to import job applications.")
                        .foregroundStyle(.secondary)
                    
                    Text("Jobs will be created with their URLs and original status preserved.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Button(action: { showFilePicker = true }) {
                        Label("Select Export File", systemImage: "doc.badge.arrow.up")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .padding()
            }
            
            Spacer()
            
            // Footer buttons
            HStack {
                if !isImporting {
                    Button("Cancel") {
                        dismiss()
                    }
                    .keyboardShortcut(.escape)
                }
                
                Spacer()
                
                if importedCount > 0 && !isImporting {
                    Button("Done") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return)
                }
            }
            .padding()
        }
        .frame(width: 500, height: 400)
        .onAppear {
            Logger.debug("🟣 ImportJobAppsFromURLsView appeared on screen")
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    Task {
                        await importJobApps(from: url)
                    }
                }
            case .failure(let error):
                errorMessage = error.localizedDescription
                showError = true
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage ?? "An unknown error occurred")
        }
    }
    
    private func importJobApps(from url: URL) async {
        isImporting = true
        importProgress = 0
        importedCount = 0
        skippedCount = 0
        
        do {
            // Use the existing ImportJobAppsScript that we already have!
            let count = try await ImportJobAppsScript.quickImportByURL(
                from: url,
                jobAppStore: jobAppStore
            )
            
            await MainActor.run {
                importedCount = count
                importProgress = 1.0
                isImporting = false
            }
            
        } catch {
            await MainActor.run {
                errorMessage = "Import failed: \(error.localizedDescription)"
                showError = true
                isImporting = false
            }
        }
    }
}

// Preview
struct ImportJobAppsFromURLsView_Previews: PreviewProvider {
    static var previews: some View {
        ImportJobAppsFromURLsView()
    }
}