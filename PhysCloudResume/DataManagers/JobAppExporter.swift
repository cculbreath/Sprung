//
//  JobAppExporter.swift
//  PhysCloudResume
//
//  Created by Claude on 5/23/25.
//

import Foundation
import SwiftData
import SQLite3

/// Handles exporting and importing JobApp data for database migrations
class JobAppExporter {
    
    /// Codable representation of JobApp for export/import
    struct ExportableJobApp: Codable {
        let id: UUID
        let companyName: String
        let jobPosition: String
        let jobLocation: String
        let jobDescription: String
        let status: String
        let companyLinkedinId: String
        let jobPostingTime: String
        let seniorityLevel: String
        let employmentType: String
        let jobFunction: String
        let industries: String
        let jobApplyLink: String
        let postingURL: String
        let notes: String
    }
    
    /// Export all JobApps to a JSON file
    /// - Parameters:
    ///   - context: The model context
    ///   - fileURL: Optional file URL, defaults to Downloads/jobapps_backup_[timestamp].json
    /// - Returns: The URL where the file was saved
    static func exportJobApps(from context: ModelContext, to fileURL: URL? = nil) throws -> URL {
        // Fetch all JobApps
        let descriptor = FetchDescriptor<JobApp>()
        let jobApps = try context.fetch(descriptor)
        
        Logger.debug("🗄️ Found \(jobApps.count) JobApps to export")
        
        // Debug: List all JobApps found
        for (index, jobApp) in jobApps.enumerated() {
            Logger.debug("JobApp \(index + 1): \(jobApp.companyName) - \(jobApp.jobPosition)")
        }
        
        // Convert to exportable format
        let exportableJobApps = jobApps.map { jobApp in
            let exportable = ExportableJobApp(
                id: jobApp.id,
                companyName: jobApp.companyName,
                jobPosition: jobApp.jobPosition,
                jobLocation: jobApp.jobLocation,
                jobDescription: jobApp.jobDescription,
                status: jobApp.status.rawValue,
                companyLinkedinId: jobApp.companyLinkedinId,
                jobPostingTime: jobApp.jobPostingTime,
                seniorityLevel: jobApp.seniorityLevel,
                employmentType: jobApp.employmentType,
                jobFunction: jobApp.jobFunction,
                industries: jobApp.industries,
                jobApplyLink: jobApp.jobApplyLink,
                postingURL: jobApp.postingURL,
                notes: jobApp.notes
            )
            Logger.debug("Created exportable for: \(exportable.companyName)")
            return exportable
        }
        
        Logger.debug("📦 Created \(exportableJobApps.count) exportable JobApps")
        
        // Determine file location
        let saveURL: URL
        if let providedURL = fileURL {
            saveURL = providedURL
        } else {
            let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .medium)
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ":", with: "-")
                .replacingOccurrences(of: " ", with: "_")
            
            let fileName = "jobapps_backup_\(timestamp).json"
            let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
            saveURL = downloadsURL.appendingPathComponent(fileName)
        }
        
        // Encode and save
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        Logger.debug("🔄 Encoding \(exportableJobApps.count) JobApps...")
        let data = try encoder.encode(exportableJobApps)
        Logger.debug("📊 Encoded data size: \(data.count) bytes")
        
        // Debug: Print first 500 characters of JSON
        if let jsonString = String(data: data, encoding: .utf8) {
            let preview = String(jsonString.prefix(500))
            Logger.debug("📝 JSON preview: \(preview)...")
        }
        
        try data.write(to: saveURL)
        
        // Verify the file was written
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: saveURL.path) {
            let attributes = try fileManager.attributesOfItem(atPath: saveURL.path)
            let fileSize = attributes[.size] as? Int ?? 0
            Logger.debug("✅ File written successfully. Size: \(fileSize) bytes")
        } else {
            Logger.error("❌ File was not created at: \(saveURL.path)")
        }
        
        Logger.debug("✅ Exported \(jobApps.count) JobApps to: \(saveURL.path)")
        
        return saveURL
    }
    
    /// Import JobApps from a JSON file
    /// - Parameters:
    ///   - fileURL: The URL of the backup file
    ///   - context: The model context
    /// - Returns: Number of JobApps imported
    @MainActor
    static func importJobApps(from fileURL: URL, to context: ModelContext) throws -> Int {
        // Read and decode the file
        let data = try Data(contentsOf: fileURL)
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let exportableJobApps = try decoder.decode([ExportableJobApp].self, from: data)
        
        Logger.debug("📥 Found \(exportableJobApps.count) JobApps to import")
        
        // Check for existing JobApps to avoid duplicates
        let descriptor = FetchDescriptor<JobApp>()
        let existingJobApps = try context.fetch(descriptor)
        let existingIds = Set(existingJobApps.map { $0.id })
        
        var importedCount = 0
        
        for exportable in exportableJobApps {
            // Skip if already exists
            if existingIds.contains(exportable.id) {
                Logger.debug("⏭️ Skipping duplicate JobApp: \(exportable.companyName) - \(exportable.jobPosition)")
                continue
            }
            
            // Create new JobApp
            let jobApp = JobApp(
                jobPosition: exportable.jobPosition,
                jobLocation: exportable.jobLocation,
                companyName: exportable.companyName,
                companyLinkedinId: exportable.companyLinkedinId,
                jobPostingTime: exportable.jobPostingTime,
                jobDescription: exportable.jobDescription,
                seniorityLevel: exportable.seniorityLevel,
                employmentType: exportable.employmentType,
                jobFunction: exportable.jobFunction,
                industries: exportable.industries,
                jobApplyLink: exportable.jobApplyLink,
                postingURL: exportable.postingURL
            )
            
            // Set all properties
            jobApp.id = exportable.id
            jobApp.status = Statuses(rawValue: exportable.status) ?? .new
            jobApp.notes = exportable.notes
            
            context.insert(jobApp)
            importedCount += 1
        }
        
        // Save changes
        try context.save()
        
        Logger.debug("✅ Imported \(importedCount) new JobApps")
        
        return importedCount
    }
    
    /// Test export function that creates a simple test file
    @MainActor
    static func testExport() throws -> URL {
        let testData = ["test": "This is a test export"]
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        
        let data = try encoder.encode(testData)
        
        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let testURL = downloadsURL.appendingPathComponent("test_export.json")
        
        try data.write(to: testURL)
        
        Logger.debug("Test file written to: \(testURL.path)")
        
        return testURL
    }
    
    /// Get the default backup directory
    static var defaultBackupDirectory: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
    }
    
    /// Diagnostic function to check database contents
    @MainActor
    static func diagnoseDatabase(context: ModelContext) {
        Logger.debug("🔍 Starting database diagnosis...")
        
        do {
            // Try to fetch all JobApps
            let descriptor = FetchDescriptor<JobApp>()
            let jobApps = try context.fetch(descriptor)
            Logger.debug("📊 Found \(jobApps.count) JobApps in database")
            
            // List first 5 JobApps
            for (index, jobApp) in jobApps.prefix(5).enumerated() {
                Logger.debug("  JobApp \(index + 1): \(jobApp.companyName) - \(jobApp.jobPosition) (Status: \(jobApp.status.rawValue))")
            }
            
            // Try different fetch approaches
            let allJobApps = try context.fetch(FetchDescriptor<JobApp>())
            Logger.debug("📊 Alternative fetch found \(allJobApps.count) JobApps")
            
            // Check if there are any model configuration issues
            if jobApps.isEmpty && allJobApps.isEmpty {
                Logger.warning("⚠️ No JobApps found in database - might be a model context issue")
                
                // Try direct SQL query to verify
                verifyWithDirectSQL()
            }
            
        } catch {
            Logger.error("❌ Database diagnosis failed: \(error)")
        }
    }
    
    /// Verify database contents with direct SQL
    static func verifyWithDirectSQL() {
        let containerURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
        let storeURL = containerURL.appendingPathComponent("Application Support/default.store")
        
        var db: OpaquePointer?
        guard sqlite3_open_v2(storeURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            Logger.error("Cannot open database for verification")
            return
        }
        defer { sqlite3_close(db) }
        
        // Count JobApps
        let query = "SELECT COUNT(*) FROM ZJOBAPP"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            defer { sqlite3_finalize(statement) }
            
            if sqlite3_step(statement) == SQLITE_ROW {
                let count = sqlite3_column_int(statement, 0)
                Logger.debug("🔍 Direct SQL found \(count) JobApps in ZJOBAPP table")
            }
        }
    }
    
    /// List available backup files
    static func listBackupFiles() -> [URL] {
        let downloadsURL = defaultBackupDirectory
        let fileManager = FileManager.default
        
        do {
            let files = try fileManager.contentsOfDirectory(at: downloadsURL, 
                                                           includingPropertiesForKeys: [.creationDateKey],
                                                           options: .skipsHiddenFiles)
            
            return files.filter { $0.lastPathComponent.hasPrefix("jobapps_backup_") && $0.pathExtension == "json" }
                       .sorted { url1, url2 in
                           let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                           let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                           return date1 > date2  // Most recent first
                       }
        } catch {
            Logger.error("Failed to list backup files: \(error)")
            return []
        }
    }
}