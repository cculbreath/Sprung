//
//  ManualJobAppImporter.swift
//  PhysCloudResume
//
//  Created on 5/23/2025.
//

import Foundation
import SwiftData
import SwiftUI

/// Manual importer for JobApp data that works through JobAppStore
/// to avoid direct ModelContext issues
class ManualJobAppImporter {
    
    enum ImportError: Error {
        case invalidConfiguration(String)
    }
    
    /// Convert SQL export to regular format and import using ModelContext
    @MainActor
    static func convertAndImport(from fileURL: URL, to context: ModelContext) async throws -> Int {
        Logger.debug("📥 Converting SQL export and importing...")
        
        // Check if we're using an in-memory database
        let isInMemory = context.container.configurations.first?.isStoredInMemoryOnly ?? false
        if isInMemory {
            Logger.error("❌ Cannot import to in-memory database! Current configuration is in-memory only.")
            throw ImportError.invalidConfiguration("Database is configured as in-memory only")
        }
        
        // Read the JSON file
        let data = try Data(contentsOf: fileURL)
        let json = try JSONSerialization.jsonObject(with: data)
        
        guard let exportData = json as? [String: Any],
              let jobAppsData = exportData["jobApps"] as? [[String: Any]] else {
            throw NSError(domain: "ManualJobAppImporter", code: 1, 
                         userInfo: [NSLocalizedDescriptionKey: "Invalid SQL export format"])
        }
        
        Logger.debug("📋 Found \(jobAppsData.count) JobApps in SQL export")
        
        // Create ExportableJobApp structures
        var exportableJobApps: [JobAppExporter.ExportableJobApp] = []
        
        for jobAppData in jobAppsData {
            // Extract fields from SQL export
            let companyName = (jobAppData["ZCOMPANYNAME"] as? String) ?? ""
            let jobPosition = (jobAppData["ZJOBPOSITION"] as? String) ?? ""
            
            // Skip if essential fields are empty
            if companyName.isEmpty && jobPosition.isEmpty {
                continue
            }
            
            // Create ExportableJobApp with proper field order
            let exportable = JobAppExporter.ExportableJobApp(
                id: UUID(), // Generate new ID or use existing if available
                companyName: companyName,
                jobPosition: jobPosition,
                jobLocation: (jobAppData["ZJOBLOCATION"] as? String) ?? "",
                jobDescription: (jobAppData["ZJOBDESCRIPTION"] as? String) ?? "",
                status: (jobAppData["ZSTATUS"] as? String) ?? "new",
                companyLinkedinId: (jobAppData["ZCOMPANYLINKEDINID"] as? String) ?? "",
                jobPostingTime: (jobAppData["ZJOBPOSTINGTIME"] as? String) ?? "",
                seniorityLevel: (jobAppData["ZSENIORITYLEVEL"] as? String) ?? "",
                employmentType: (jobAppData["ZEMPLOYMENTTYPE"] as? String) ?? "",
                jobFunction: (jobAppData["ZJOBFUNCTION"] as? String) ?? "",
                industries: (jobAppData["ZINDUSTRIES"] as? String) ?? "",
                jobApplyLink: (jobAppData["ZJOBAPPLYLINK"] as? String) ?? "",
                postingURL: (jobAppData["ZPOSTINGURL"] as? String) ?? "",
                notes: (jobAppData["ZNOTES"] as? String) ?? ""
            )
            
            exportableJobApps.append(exportable)
        }
        
        Logger.debug("📋 Converted \(exportableJobApps.count) JobApps to regular format")
        
        // Now use the regular import logic
        var importedCount = 0
        
        for exportable in exportableJobApps {
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
            
            // Set additional properties
            jobApp.id = exportable.id
            jobApp.status = Statuses(rawValue: exportable.status) ?? .new
            jobApp.notes = exportable.notes
            
            context.insert(jobApp)
            importedCount += 1
            
            Logger.debug("✅ Converted and inserted: \(exportable.companyName) - \(exportable.jobPosition)")
        }
        
        // Save all at once
        Logger.debug("💾 About to save \(importedCount) JobApps...")
        Logger.debug("📊 Context has changes: \(context.hasChanges)")
        
        if context.hasChanges {
            try context.save()
            Logger.debug("✅ Save completed")
        } else {
            Logger.debug("⚠️ No changes to save!")
        }
        
        // Check the container configuration
        Logger.debug("📁 Container configuration: \(context.container.configurations)")
        
        // Verify the save
        let descriptor = FetchDescriptor<JobApp>()
        let verifyCount = try context.fetch(descriptor).count
        Logger.debug("🔍 Verification: Found \(verifyCount) JobApps in database")
        
        // Also check in a fresh context
        let freshContext = ModelContext(context.container)
        let freshCount = try freshContext.fetch(descriptor).count
        Logger.debug("🔍 Fresh context verification: Found \(freshCount) JobApps")
        
        // Post notification to refresh UI
        if importedCount > 0 {
            NotificationCenter.default.post(name: NSNotification.Name("RefreshJobApps"), object: nil)
            Logger.debug("📢 Posted RefreshJobApps notification")
        }
        
        return importedCount
    }
    
    /// Import JobApps from a SQL export file using JobAppStore  
    /// - Parameters:
    ///   - fileURL: URL to the SQL export JSON file
    ///   - jobAppStore: The JobAppStore instance to use for creating JobApps
    /// - Returns: Number of successfully imported JobApps
    @MainActor
    static func importFromSQLExport(from fileURL: URL, using jobAppStore: JobAppStore) async throws -> Int {
        Logger.debug("📥 Starting SQL export import using JobAppStore")
        
        // Read the JSON file
        let data = try Data(contentsOf: fileURL)
        let json = try JSONSerialization.jsonObject(with: data)
        
        guard let exportData = json as? [String: Any],
              let jobAppsData = exportData["jobApps"] as? [[String: Any]] else {
            throw NSError(domain: "ManualJobAppImporter", code: 1, 
                         userInfo: [NSLocalizedDescriptionKey: "Invalid SQL export format"])
        }
        
        Logger.debug("📋 Found \(jobAppsData.count) JobApps in SQL export")
        
        var importedCount = 0
        
        for jobAppData in jobAppsData {
            // Extract fields from SQL export
            let companyName = (jobAppData["ZCOMPANYNAME"] as? String) ?? ""
            let jobPosition = (jobAppData["ZJOBPOSITION"] as? String) ?? ""
            
            // Skip if essential fields are empty
            if companyName.isEmpty && jobPosition.isEmpty {
                continue
            }
            
            // Create new JobApp directly
            let jobApp = JobApp(
                jobPosition: jobPosition,
                jobLocation: (jobAppData["ZJOBLOCATION"] as? String) ?? "",
                companyName: companyName,
                companyLinkedinId: (jobAppData["ZCOMPANYLINKEDINID"] as? String) ?? "",
                jobPostingTime: (jobAppData["ZJOBPOSTINGTIME"] as? String) ?? "",
                jobDescription: (jobAppData["ZJOBDESCRIPTION"] as? String) ?? "",
                seniorityLevel: (jobAppData["ZSENIORITYLEVEL"] as? String) ?? "",
                employmentType: (jobAppData["ZEMPLOYMENTTYPE"] as? String) ?? "",
                jobFunction: (jobAppData["ZJOBFUNCTION"] as? String) ?? "",
                industries: (jobAppData["ZINDUSTRIES"] as? String) ?? "",
                jobApplyLink: (jobAppData["ZJOBAPPLYLINK"] as? String) ?? "",
                postingURL: (jobAppData["ZPOSTINGURL"] as? String) ?? ""
            )
            
            // Set status
            if let statusRaw = jobAppData["ZSTATUS"] as? String {
                jobApp.status = Statuses(rawValue: statusRaw) ?? .new
            }
            
            // Set notes
            jobApp.notes = (jobAppData["ZNOTES"] as? String) ?? ""
            
            // Use JobAppStore to add the JobApp
            if let added = jobAppStore.addJobApp(jobApp) {
                importedCount += 1
                Logger.debug("✅ Imported via JobAppStore: \(companyName) - \(jobPosition)")
            } else {
                Logger.debug("❌ Failed to add: \(companyName) - \(jobPosition)")
            }
        }
        
        // Save context through JobAppStore
        jobAppStore.saveContext()
        
        Logger.debug("📊 Import Summary:")
        Logger.debug("  ✅ Successfully imported: \(importedCount)")
        Logger.debug("  📁 Total in store: \(jobAppStore.jobApps.count)")
        
        return importedCount
    }
    
}