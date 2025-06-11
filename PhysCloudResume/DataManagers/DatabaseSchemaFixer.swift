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
        
        Logger.info("🔧 Starting database schema fix for: \(dbPath)")
        
        // Check if schema fixes are actually needed before backing up
        var needsFixing = false
        
        // Quick check to see if fixes are needed
        var db: OpaquePointer?
        let result = sqlite3_open(dbPath, &db)
        
        guard result == SQLITE_OK else {
            Logger.error("x Failed to open database: \(String(cString: sqlite3_errmsg(db)))")
            throw DatabaseSchemaFixerError.cannotOpenDatabase
        }
        
        defer {
            sqlite3_close(db)
        }
        
        // Check if any fixes are needed
        needsFixing = try checkIfFixesNeeded(db: db)
        
        if !needsFixing {
            Logger.info("✅ Database schema is up to date, no fixes needed")
            return
        }
        
        Logger.info("🔧 Database schema fixes needed, creating backup...")
        // Only backup if we actually need to make changes
        try backupDatabase(at: dbPath)
        
        
        try fixTreeNodeSchema(db: db)
        try fixResumeSchema(db: db)
        try fixResRefRelationshipSchema(db: db)
        
        Logger.info("✅ Database schema fix completed")
    }
    
    /// Checks if any schema fixes are needed without making changes
    private static func checkIfFixesNeeded(db: OpaquePointer?) throws -> Bool {
        var needsFixing = false
        
        // Check TreeNode schema
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
        
        if !hasChildrenColumn {
            needsFixing = true
        }
        
        // Check Resume schema
        let checkFontColumn = "PRAGMA table_info(ZRESUME);"
        var hasFontColumn = false
        
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
        
        if !hasFontColumn {
            needsFixing = true
        }
        
        // Check for join table
        let checkJoinTable = "SELECT name FROM sqlite_master WHERE type='table' AND name='Z_10ENABLEDRESUMES';"
        var hasJoinTable = false
        
        if sqlite3_prepare_v2(db, checkJoinTable, -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                hasJoinTable = true
            }
        }
        sqlite3_finalize(stmt)
        
        if !hasJoinTable {
            needsFixing = true
        }
        
        return needsFixing
    }
    
    private static func backupDatabase(at path: String) throws {
        let backupPath = path + ".backup.\(Int(Date().timeIntervalSince1970))"
        try FileManager.default.copyItem(atPath: path, toPath: backupPath)
        Logger.debug("💾 Database backed up to: \(backupPath)")
    }
    
    private static func fixTreeNodeSchema(db: OpaquePointer?) throws {
        Logger.info("🔧 Fixing TreeNode schema...")
        
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
            Logger.info("➕ Adding missing Z12CHILDREN column to ZTREENODE")
            let addChildrenColumn = "ALTER TABLE ZTREENODE ADD COLUMN Z12CHILDREN INTEGER;"
            if sqlite3_exec(db, addChildrenColumn, nil, nil, nil) != SQLITE_OK {
                Logger.warning("⚠️ Could not add Z12CHILDREN column (may already exist)")
            }
        }
    }
    
    private static func fixResumeSchema(db: OpaquePointer?) throws {
        Logger.info("🔧 Fixing Resume schema...")
        
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
            Logger.info("➕ Adding missing Z11FONTSIZENODES column to ZRESUME")
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
            Logger.info("➕ Creating ZFONTSIZENODE table")
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
    
    private static func fixResRefRelationshipSchema(db: OpaquePointer?) throws {
        Logger.info("🔧 Fixing ResRef relationship schema...")
        
        // Check if the join table exists for the many-to-many relationship
        let checkJoinTable = "SELECT name FROM sqlite_master WHERE type='table' AND name='Z_10ENABLEDRESUMES';"
        var hasJoinTable = false
        
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, checkJoinTable, -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                hasJoinTable = true
            }
        }
        sqlite3_finalize(stmt)
        
        if !hasJoinTable {
            Logger.info("➕ Creating Z_10ENABLEDRESUMES join table for Resume-ResRef relationship")
            
            // Create the join table with the expected structure
            // This table links Resume and ResRef entities in a many-to-many relationship
            let createJoinTable = """
                CREATE TABLE Z_10ENABLEDRESUMES (
                    Z_10ENABLEDSOURCES INTEGER,
                    Z_18ENABLEDRESUMES INTEGER,
                    PRIMARY KEY (Z_10ENABLEDSOURCES, Z_18ENABLEDRESUMES)
                );
                """
            
            if sqlite3_exec(db, createJoinTable, nil, nil, nil) != SQLITE_OK {
                let errorMsg = String(cString: sqlite3_errmsg(db))
                Logger.error("x Failed to create Z_10ENABLEDRESUMES table: \(errorMsg)")
                
                // Try an alternative naming convention that SwiftData might use
                let alternativeCreateTable = """
                    CREATE TABLE IF NOT EXISTS Z_10ENABLEDRESUMES (
                        Z_10ENABLEDSOURCES INTEGER NOT NULL,
                        Z_18ENABLEDRESUMES INTEGER NOT NULL,
                        PRIMARY KEY (Z_10ENABLEDSOURCES, Z_18ENABLEDRESUMES),
                        FOREIGN KEY (Z_10ENABLEDSOURCES) REFERENCES ZRESUME(Z_PK),
                        FOREIGN KEY (Z_18ENABLEDRESUMES) REFERENCES ZRESREF(Z_PK)
                    );
                    """
                
                if sqlite3_exec(db, alternativeCreateTable, nil, nil, nil) == SQLITE_OK {
                    Logger.info("✅ Created Z_10ENABLEDRESUMES table with alternative schema")
                } else {
                    Logger.warning("⚠️ Could not create Z_10ENABLEDRESUMES table")
                }
            } else {
                Logger.info("✅ Created Z_10ENABLEDRESUMES join table")
            }
        } else {
            Logger.debug("✅ Z_10ENABLEDRESUMES join table already exists")
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