//
//  DirectSQLExporter.swift
//  PhysCloudResume
//
//  Created by Claude on 5/23/25.
//

import Foundation
import SQLite3
import SwiftData

/// Direct SQL exporter that bypasses SwiftData to extract JobApps from corrupted database
class DirectSQLExporter {
    
    /// Export JobApps directly using SQLite
    static func exportJobAppsDirectly() throws -> URL {
        // Find the database file
        let containerURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
        let storeURL = containerURL.appendingPathComponent("Application Support/default.store")
        
        Logger.debug("🔍 Looking for database at: \(storeURL.path)")
        
        guard FileManager.default.fileExists(atPath: storeURL.path) else {
            throw NSError(domain: "DirectSQLExporter", code: 1, userInfo: [NSLocalizedDescriptionKey: "Database file not found"])
        }
        
        // Open database
        var db: OpaquePointer?
        guard sqlite3_open_v2(storeURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            let errmsg = String(cString: sqlite3_errmsg(db))
            throw NSError(domain: "DirectSQLExporter", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot open database: \(errmsg)"])
        }
        defer { sqlite3_close(db) }
        
        // Find JobApp table
        let tables = try listTables(db: db)
        Logger.debug("📊 Found tables: \(tables)")
        
        // Look for JobApp table (might be named differently in CoreData)
        let jobAppTable = tables.first { $0.uppercased().contains("JOBAPP") } ?? "ZJOBAPP"
        Logger.debug("🎯 Using table: \(jobAppTable)")
        
        // Get column names
        let columns = try getTableColumns(db: db, tableName: jobAppTable)
        Logger.debug("📋 Columns in \(jobAppTable): \(columns)")
        
        // Query all JobApps
        let query = "SELECT * FROM \(jobAppTable)"
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            let errmsg = String(cString: sqlite3_errmsg(db))
            throw NSError(domain: "DirectSQLExporter", code: 3, userInfo: [NSLocalizedDescriptionKey: "Cannot prepare statement: \(errmsg)"])
        }
        defer { sqlite3_finalize(statement) }
        
        var jobApps: [[String: Any]] = []
        
        while sqlite3_step(statement) == SQLITE_ROW {
            var jobApp: [String: Any] = [:]
            
            for i in 0..<sqlite3_column_count(statement) {
                let columnName = String(cString: sqlite3_column_name(statement, i))
                
                switch sqlite3_column_type(statement, i) {
                case SQLITE_INTEGER:
                    jobApp[columnName] = sqlite3_column_int64(statement, i)
                case SQLITE_FLOAT:
                    jobApp[columnName] = sqlite3_column_double(statement, i)
                case SQLITE_TEXT:
                    if let text = sqlite3_column_text(statement, i) {
                        jobApp[columnName] = String(cString: text)
                    }
                case SQLITE_BLOB:
                    let bytes = sqlite3_column_blob(statement, i)
                    let length = sqlite3_column_bytes(statement, i)
                    if let bytes = bytes {
                        let data = Data(bytes: bytes, count: Int(length))
                        // Try to decode UUID
                        if columnName.uppercased().contains("UUID") || columnName == "Z_PK" {
                            jobApp[columnName] = data.hexString
                        } else {
                            jobApp[columnName] = data.base64EncodedString()
                        }
                    }
                case SQLITE_NULL:
                    jobApp[columnName] = NSNull()
                default:
                    break
                }
            }
            
            jobApps.append(jobApp)
        }
        
        Logger.debug("✅ Found \(jobApps.count) JobApps in direct SQL query")
        
        // Save to JSON
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .medium)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: " ", with: "_")
        
        let fileName = "jobapps_direct_sql_\(timestamp).json"
        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let saveURL = downloadsURL.appendingPathComponent(fileName)
        
        let jsonData = try JSONSerialization.data(withJSONObject: ["jobApps": jobApps, "tableName": jobAppTable, "columns": columns], options: .prettyPrinted)
        try jsonData.write(to: saveURL)
        
        Logger.debug("💾 Saved direct SQL export to: \(saveURL.path)")
        
        return saveURL
    }
    
    /// List all tables in the database
    private static func listTables(db: OpaquePointer?) throws -> [String] {
        let query = "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            throw NSError(domain: "DirectSQLExporter", code: 4, userInfo: [NSLocalizedDescriptionKey: "Cannot list tables"])
        }
        defer { sqlite3_finalize(statement) }
        
        var tables: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let name = sqlite3_column_text(statement, 0) {
                tables.append(String(cString: name))
            }
        }
        
        return tables
    }
    
    /// Get column names for a table
    private static func getTableColumns(db: OpaquePointer?, tableName: String) throws -> [String] {
        let query = "PRAGMA table_info(\(tableName))"
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            throw NSError(domain: "DirectSQLExporter", code: 5, userInfo: [NSLocalizedDescriptionKey: "Cannot get table info"])
        }
        defer { sqlite3_finalize(statement) }
        
        var columns: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let name = sqlite3_column_text(statement, 1) { // Column 1 is the name
                columns.append(String(cString: name))
            }
        }
        
        return columns
    }
}

extension Data {
    var hexString: String {
        return map { String(format: "%02hhx", $0) }.joined()
    }
}

// MARK: - Direct SQL Import

extension DirectSQLExporter {
    
    /// Import JobApps from a direct SQL export
    @MainActor
    static func importFromDirectSQLExport(from fileURL: URL, to context: ModelContext) throws -> Int {
        // Disable autosave during import
        let originalAutosave = context.autosaveEnabled
        context.autosaveEnabled = false
        defer {
            context.autosaveEnabled = originalAutosave
        }
        
        let data = try Data(contentsOf: fileURL)
        
        // Try to parse JSON
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // Log the first 500 characters of the file for debugging
            let preview = String(data: data.prefix(500), encoding: .utf8) ?? "Unable to decode"
            Logger.error("Failed to parse JSON. Preview: \(preview)")
            throw NSError(domain: "DirectSQLExporter", code: 10, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON format"])
        }
        
        // Log what we found
        Logger.debug("📋 JSON keys: \(json.keys.joined(separator: ", "))")
        
        guard let jobAppsData = json["jobApps"] as? [[String: Any]] else {
            throw NSError(domain: "DirectSQLExporter", code: 11, userInfo: [NSLocalizedDescriptionKey: "No jobApps array found in JSON"])
        }
        
        Logger.debug("📥 Found \(jobAppsData.count) JobApps in SQL export")
        
        // Log first JobApp structure for debugging
        if let firstJobApp = jobAppsData.first {
            Logger.debug("📋 First JobApp keys: \(firstJobApp.keys.sorted().joined(separator: ", "))")
        }
        
        var importedCount = 0
        
        for jobAppData in jobAppsData {
            // Extract fields - CoreData uses Z prefixes (without underscores based on the log)
            let companyName = (jobAppData["ZCOMPANYNAME"] as? String) ?? ""
            let jobPosition = (jobAppData["ZJOBPOSITION"] as? String) ?? ""
            let jobDescription = (jobAppData["ZJOBDESCRIPTION"] as? String) ?? ""
            let jobLocation = (jobAppData["ZJOBLOCATION"] as? String) ?? ""
            
            // Skip if essential fields are empty
            if companyName.isEmpty && jobPosition.isEmpty {
                Logger.debug("⚠️ Skipping JobApp with empty company and position")
                continue
            }
            
            // Create new JobApp
            let jobApp = JobApp(
                jobPosition: jobPosition,
                jobLocation: jobLocation,
                companyName: companyName,
                companyLinkedinId: (jobAppData["ZCOMPANYLINKEDINID"] as? String) ?? "",
                jobPostingTime: (jobAppData["ZJOBPOSTINGTIME"] as? String) ?? "",
                jobDescription: jobDescription,
                seniorityLevel: (jobAppData["ZSENIORITYLEVEL"] as? String) ?? "",
                employmentType: (jobAppData["ZEMPLOYMENTTYPE"] as? String) ?? "",
                jobFunction: (jobAppData["ZJOBFUNCTION"] as? String) ?? "",
                industries: (jobAppData["ZINDUSTRIES"] as? String) ?? "",
                jobApplyLink: (jobAppData["ZJOBAPPLYLINK"] as? String) ?? "",
                postingURL: (jobAppData["ZPOSTINGURL"] as? String) ?? ""
            )
            
            // Set the ID from the original data if available
            if let idString = jobAppData["ZID"] as? String,
               let uuid = UUID(uuidString: idString) {
                jobApp.id = uuid
            }
            
            // Set status
            if let statusRaw = jobAppData["ZSTATUS"] as? String {
                jobApp.status = Statuses(rawValue: statusRaw) ?? .new
            }
            
            // Set notes
            jobApp.notes = (jobAppData["ZNOTES"] as? String) ?? ""
            
            // Try different approach - ensure model is properly tracked
            context.insert(jobApp)
            
            // Don't save after each - batch them
            importedCount += 1
            Logger.debug("✅ Created JobApp #\(importedCount): \(companyName) - \(jobPosition)")
        }
        
        // Save all changes at once
        Logger.debug("💾 Saving \(importedCount) JobApps...")
        
        // Check what we're about to save
        if context.hasChanges {
            Logger.debug("✅ Context has changes to save")
            if let insertedObjects = context.insertedModelsArray as? [JobApp] {
                Logger.debug("📝 About to save \(insertedObjects.count) JobApps")
                for (index, jobApp) in insertedObjects.prefix(3).enumerated() {
                    Logger.debug("  \(index + 1): \(jobApp.companyName) - \(jobApp.jobPosition)")
                }
            }
        } else {
            Logger.debug("⚠️ Context has NO changes!")
        }
        
        try context.save()
        Logger.debug("💾 Save completed for \(importedCount) JobApps")
        
        // Verify the save by fetching
        let descriptor = FetchDescriptor<JobApp>()
        let verifyCount = try context.fetch(descriptor).count
        Logger.debug("🔍 Verification fetch found \(verifyCount) JobApps in database")
        
        // Try a different approach - fetch with a new descriptor
        let allJobApps = try context.fetch(FetchDescriptor<JobApp>(sortBy: [SortDescriptor(\.companyName)]))
        Logger.debug("🔍 Alternative fetch found \(allJobApps.count) JobApps")
        if !allJobApps.isEmpty {
            Logger.debug("🔍 First JobApp: \(allJobApps[0].companyName) - \(allJobApps[0].jobPosition)")
        }
        
        // Check the database file directly
        Logger.debug("🔍 Checking database configuration...")
        Logger.debug("🔍 Context: \(context)")
        Logger.debug("🔍 Container: \(context.container)")
        
        if let container = context.container as? ModelContainer {
            Logger.debug("📁 Container configurations: \(container.configurations.count)")
            
            // Log all configurations
            for (index, config) in container.configurations.enumerated() {
                Logger.debug("📁 Configuration \(index):")
                Logger.debug("  - URL: \(config.url.path)")
                Logger.debug("  - isStoredInMemoryOnly: \(config.isStoredInMemoryOnly)")
            }
            
            if let storeURL = container.configurations.first?.url {
                Logger.debug("📁 Primary database location: \(storeURL.path)")
                
                // Check file size
                if let attributes = try? FileManager.default.attributesOfItem(atPath: storeURL.path),
                   let fileSize = attributes[.size] as? Int64 {
                    Logger.debug("📁 Database file size: \(fileSize) bytes")
                }
            } else {
                Logger.debug("⚠️ No store URL found in container configuration")
            }
        } else {
            Logger.debug("⚠️ Could not cast context.container to ModelContainer")
        }
        
        // Post notification to refresh UI
        NotificationCenter.default.post(name: NSNotification.Name("RefreshJobApps"), object: nil)
        Logger.debug("📢 Posted RefreshJobApps notification")
        
        return importedCount
    }
}