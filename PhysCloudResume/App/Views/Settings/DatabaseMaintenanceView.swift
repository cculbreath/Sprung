//
//  DatabaseMaintenanceView.swift
//  PhysCloudResume
//
//  Created by Claude on 5/23/25.
//

import SwiftUI
import SwiftData

struct DatabaseMaintenanceView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(JobAppStore.self) private var jobAppStore
    
    @State private var showExportSuccess = false
    @State private var showImportSuccess = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var lastExportURL: URL?
    @State private var importedCount = 0
    @State private var showImportPicker = false
    @State private var showResetConfirmation = false
    @State private var isProcessing = false
    @State private var quickImportMode = false
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "externaldrive.badge.wrench")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)
                    .symbolRenderingMode(.hierarchical)
                
                Text("Database Maintenance")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Backup your job applications before resetting the database")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top)
            
            Divider()
            
            // Export Section
            VStack(alignment: .leading, spacing: 16) {
                Label("Backup Job Applications", systemImage: "square.and.arrow.up")
                    .font(.headline)
                
                Text("Export all your job applications to a JSON file that can be restored later.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                HStack {
                    Button(action: exportJobApps) {
                        Label("Export JobApps", systemImage: "square.and.arrow.up")
                    }
                    .disabled(isProcessing)
                    
                    Button("Direct SQL Export") {
                        do {
                            let url = try DirectSQLExporter.exportJobAppsDirectly()
                            lastExportURL = url
                            showExportSuccess = true
                            NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
                        } catch {
                            errorMessage = "Direct SQL export failed: \(error.localizedDescription)"
                            showError = true
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    
                    // Test button
                    Button("Test Export") {
                        do {
                            let testURL = try JobAppExporter.testExport()
                            Logger.debug("Test export successful: \(testURL)")
                        } catch {
                            Logger.error("Test export failed: \(error)")
                        }
                    }
                    .buttonStyle(.link)
                    
                    // Diagnose button
                    Button("Diagnose") {
                        JobAppExporter.diagnoseDatabase(context: modelContext)
                    }
                    .buttonStyle(.link)
                    
                    // Force refresh button
                    Button("Force Refresh") {
                        // Force the model context to refetch data
                        do {
                            try modelContext.save()
                            
                            // SwiftData doesn't have refreshAllObjects, so we'll force a new fetch
                            // and notify any listening views to update
                            let descriptor = FetchDescriptor<JobApp>()
                            let jobApps = try modelContext.fetch(descriptor)
                            Logger.debug("🔄 Force refresh: found \(jobApps.count) JobApps in database")
                            
                            // Post notification to refresh UI
                            NotificationCenter.default.post(name: NSNotification.Name("RefreshJobApps"), object: nil)
                            
                            // Also try to reset the model container (this forces SwiftData to reload)
                            modelContext.autosaveEnabled = false
                            modelContext.autosaveEnabled = true
                            
                            Logger.debug("✅ Posted refresh notification")
                        } catch {
                            Logger.error("❌ Force refresh failed: \(error)")
                        }
                    }
                    .buttonStyle(.link)
                    
                    if showExportSuccess, let url = lastExportURL {
                        Label("Saved to Downloads", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                        
                        Button("Show in Finder") {
                            NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            
            // Import Section
            VStack(alignment: .leading, spacing: 16) {
                Label("Restore Job Applications", systemImage: "square.and.arrow.down")
                    .font(.headline)
                
                Text("Import job applications from a previously exported backup file.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                HStack {
                    Button(action: { 
                        quickImportMode = false
                        showImportPicker = true 
                    }) {
                        Label("Import JobApps", systemImage: "square.and.arrow.down")
                    }
                    .disabled(isProcessing)
                    
                    Button(action: { 
                        quickImportMode = true
                        showImportPicker = true 
                    }) {
                        Label("Quick Import", systemImage: "bolt.square.fill")
                    }
                    .disabled(isProcessing)
                    .help("Import using the same path as UI - just URLs and status")
                    
                    if showImportSuccess {
                        Label("Imported \(importedCount) jobs", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            
            // Reset Database Section
            VStack(alignment: .leading, spacing: 16) {
                Label("Reset Database", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.red)
                
                Text("⚠️ This will delete ALL data. Make sure to export your JobApps first!")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Button(action: { showResetConfirmation = true }) {
                    Label("Reset Database", systemImage: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(isProcessing)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color.red.opacity(0.1))
            .cornerRadius(8)
            
            Spacer()
            
            // Close button
            Button("Done") {
                dismiss()
            }
            .keyboardShortcut(.escape)
        }
        .padding()
        .frame(width: 500, height: 600)
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .alert("Reset Database?", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                resetDatabase()
            }
        } message: {
            Text("This will delete ALL data including resumes, cover letters, and references. Make sure you've exported your JobApps first!\n\nThis action cannot be undone.")
        }
        .fileImporter(
            isPresented: $showImportPicker,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    importJobApps(from: url)
                }
            case .failure(let error):
                errorMessage = error.localizedDescription
                showError = true
            }
        }
        .overlay {
            if isProcessing {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.3))
            }
        }
    }
    
    private func exportJobApps() {
        isProcessing = true
        showExportSuccess = false
        
        Task {
            do {
                let url = try await JobAppExporter.exportJobApps(from: modelContext)
                await MainActor.run {
                    lastExportURL = url
                    showExportSuccess = true
                    isProcessing = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Export failed: \(error.localizedDescription)"
                    showError = true
                    isProcessing = false
                }
            }
        }
    }
    
    private func importJobApps(from url: URL) {
        isProcessing = true
        showImportSuccess = false
        
        Task {
            do {
                // Start accessing the security-scoped resource
                let accessing = url.startAccessingSecurityScopedResource()
                defer {
                    if accessing {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                
                // Check if this is a direct SQL export
                let data = try Data(contentsOf: url)
                let json = try JSONSerialization.jsonObject(with: data)
                
                let count: Int
                
                // Check if we should use quick import mode
                if quickImportMode {
                    Logger.debug("⚡ Using quick import mode (UI path)")
                    count = try await ImportJobAppsScript.quickImportByURL(from: url, jobAppStore: jobAppStore)
                } else if let dict = json as? [String: Any], dict["jobApps"] != nil && dict["tableName"] != nil {
                    // This is a direct SQL export
                    Logger.debug("📂 Detected direct SQL export format")
                    
                    // Try the UI path for SQL exports too
                    Logger.debug("🚀 Using UI import path for SQL export...")
                    count = try await ImportJobAppsScript.importUsingUIPath(from: url, jobAppStore: jobAppStore)
                } else {
                    // Regular export - also use UI path
                    Logger.debug("📂 Detected regular export format")
                    Logger.debug("🚀 Using UI import path...")
                    count = try await ImportJobAppsScript.importUsingUIPath(from: url, jobAppStore: jobAppStore)
                }
                
                await MainActor.run {
                    importedCount = count
                    showImportSuccess = true
                    isProcessing = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Import failed: \(error.localizedDescription)"
                    showError = true
                    isProcessing = false
                }
            }
        }
    }
    
    private func resetDatabase() {
        isProcessing = true
        
        // Direct file deletion approach
        let fileManager = FileManager.default
        let containerURL = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first!
        let appSupportURL = containerURL.appendingPathComponent("Application Support")
        
        do {
            // Find all SQLite-related files
            let contents = try fileManager.contentsOfDirectory(at: appSupportURL, 
                                                             includingPropertiesForKeys: nil,
                                                             options: .skipsHiddenFiles)
            
            var deletedFiles: [String] = []
            
            for fileURL in contents {
                let filename = fileURL.lastPathComponent
                // Delete any SQLite database files
                if filename.hasSuffix(".sqlite") || 
                   filename.hasSuffix(".sqlite-shm") || 
                   filename.hasSuffix(".sqlite-wal") ||
                   filename == "default.store" ||
                   filename.hasPrefix("Model") {
                    
                    try fileManager.removeItem(at: fileURL)
                    deletedFiles.append(filename)
                    Logger.debug("✅ Deleted: \(filename)")
                }
            }
            
            Logger.debug("🗑️ Deleted \(deletedFiles.count) database files: \(deletedFiles.joined(separator: ", "))")
            
            // Show success message
            DispatchQueue.main.async {
                self.errorMessage = "Database reset successful. Deleted files: \(deletedFiles.joined(separator: ", "))\n\nPlease quit and restart the app."
                self.showError = true
                self.isProcessing = false
            }
            
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = "Reset failed: \(error.localizedDescription)"
                self.showError = true
                self.isProcessing = false
            }
        }
    }
}


// Preview
struct DatabaseMaintenanceView_Previews: PreviewProvider {
    static var previews: some View {
        DatabaseMaintenanceView()
    }
}
