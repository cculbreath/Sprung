import Foundation
import SwiftData
import SQLite3

/// Fixes database schema issues while preserving existing data
class DatabaseSchemaFixer {
    
    static func fixDatabaseSchema() throws {
        let containerURL = try getApplicationSupportDirectory()
        let dbPath = containerURL.appendingPathComponent("default.store").path
        
        guard FileManager.default.fileExists(atPath: dbPath) else {
            Logger.debug("🔧 No existing database found, skipping schema fix")
            return
        }
        
        Logger.debug("🔧 Starting database schema fix for: \(dbPath)")
        
        // Backup the database first
        try backupDatabase(at: dbPath)
        
        // Open SQLite connection
        var db: OpaquePointer?
        let result = sqlite3_open(dbPath, &db)
        
        guard result == SQLITE_OK else {
            Logger.error("❌ Failed to open database: \(String(cString: sqlite3_errmsg(db)))")
            throw DatabaseSchemaFixerError.cannotOpenDatabase
        }
        
        defer {
            sqlite3_close(db)
        }
        
        try fixTreeNodeSchema(db: db)
        try fixResumeSchema(db: db)
        
        Logger.debug("✅ Database schema fix completed")
    }
    
    private static func backupDatabase(at path: String) throws {
        let backupPath = path + ".backup.\(Int(Date().timeIntervalSince1970))"
        try FileManager.default.copyItem(atPath: path, toPath: backupPath)
        Logger.debug("💾 Database backed up to: \(backupPath)")
    }
    
    private static func fixTreeNodeSchema(db: OpaquePointer?) throws {
        Logger.debug("🔧 Fixing TreeNode schema...")
        
        // Check if Z12CHILDREN column exists
        let checkChildrenColumn = "PRAGMA table_info(ZTREENODE);"
        var hasChildrenColumn = false
        
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, checkChildrenColumn, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                let columnName = String(cString: sqlite3_column_text(stmt, 1))
                if columnName == "Z12CHILDREN" {
                    hasChildrenColumn = true
                    break
                }
            }
        }
        sqlite3_finalize(stmt)
        
        // Add missing columns if needed
        if !hasChildrenColumn {
            Logger.debug("➕ Adding missing Z12CHILDREN column to ZTREENODE")
            let addChildrenColumn = "ALTER TABLE ZTREENODE ADD COLUMN Z12CHILDREN INTEGER;"
            if sqlite3_exec(db, addChildrenColumn, nil, nil, nil) != SQLITE_OK {
                Logger.warning("⚠️ Could not add Z12CHILDREN column (may already exist)")
            }
        }
    }
    
    private static func fixResumeSchema(db: OpaquePointer?) throws {
        Logger.debug("🔧 Fixing Resume schema...")
        
        // Check if Z11FONTSIZENODES column exists
        let checkFontColumn = "PRAGMA table_info(ZRESUME);"
        var hasFontColumn = false
        
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, checkFontColumn, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                let columnName = String(cString: sqlite3_column_text(stmt, 1))
                if columnName == "Z11FONTSIZENODES" {
                    hasFontColumn = true
                    break
                }
            }
        }
        sqlite3_finalize(stmt)
        
        // Add missing columns if needed
        if !hasFontColumn {
            Logger.debug("➕ Adding missing Z11FONTSIZENODES column to ZRESUME")
            let addFontColumn = "ALTER TABLE ZRESUME ADD COLUMN Z11FONTSIZENODES INTEGER;"
            if sqlite3_exec(db, addFontColumn, nil, nil, nil) != SQLITE_OK {
                Logger.warning("⚠️ Could not add Z11FONTSIZENODES column (may already exist)")
            }
        }
        
        // Check if FontSizeNode table exists and has proper resume relationship
        let checkFontSizeTable = "SELECT name FROM sqlite_master WHERE type='table' AND name='ZFONTSIZENODE';"
        var hasFontSizeTable = false
        
        if sqlite3_prepare_v2(db, checkFontSizeTable, -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                hasFontSizeTable = true
            }
        }
        sqlite3_finalize(stmt)
        
        if !hasFontSizeTable {
            Logger.debug("➕ Creating ZFONTSIZENODE table")
            let createFontSizeTable = """
                CREATE TABLE ZFONTSIZENODE (
                    Z_PK INTEGER PRIMARY KEY,
                    Z_ENT INTEGER,
                    Z_OPT INTEGER,
                    ZID TEXT,
                    ZKEY TEXT,
                    ZINDEX INTEGER,
                    ZFONTVALUE REAL,
                    ZRESUME INTEGER
                );
                """
            if sqlite3_exec(db, createFontSizeTable, nil, nil, nil) != SQLITE_OK {
                Logger.warning("⚠️ Could not create ZFONTSIZENODE table")
            }
        }
    }
    
    private static func getApplicationSupportDirectory() throws -> URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        guard let appSupportURL = paths.first else {
            throw DatabaseSchemaFixerError.cannotFindApplicationSupport
        }
        return appSupportURL
    }
}

enum DatabaseSchemaFixerError: Error {
    case cannotOpenDatabase
    case cannotFindApplicationSupport
    case schemaMigrationFailed
}