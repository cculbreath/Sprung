import Foundation

/// Manages database isolation for testing
struct TestDatabaseManager {
    static let shared = TestDatabaseManager()
    
    private let containerPath = "/Users/cculbreath/Library/Containers/Physics-Cloud.PhysCloudResume/Data/Library/Application Support/"
    private let dbFileName = "default.store"
    private let backupSuffix = ".test_backup"
    
    private var originalDBPath: String {
        containerPath + dbFileName
    }
    
    private var backupDBPath: String {
        containerPath + dbFileName + backupSuffix
    }
    
    /// Safely moves the production database out of the way for testing
    func isolateProductionDatabase() throws {
        let fileManager = FileManager.default
        
        // Check if production database exists
        guard fileManager.fileExists(atPath: originalDBPath) else {
            print("ℹ️ No production database found at: \(originalDBPath)")
            return
        }
        
        // Remove any existing backup
        if fileManager.fileExists(atPath: backupDBPath) {
            try fileManager.removeItem(atPath: backupDBPath)
        }
        
        // Move production database to backup location
        try fileManager.moveItem(atPath: originalDBPath, toPath: backupDBPath)
        print("✅ Production database backed up to: \(backupDBPath)")
        
        // Remove associated files if they exist
        let associatedFiles = [
            containerPath + dbFileName + "-shm",
            containerPath + dbFileName + "-wal"
        ]
        
        for file in associatedFiles {
            if fileManager.fileExists(atPath: file) {
                try? fileManager.removeItem(atPath: file)
            }
        }
        
        print("🧪 Test environment ready - production database isolated")
    }
    
    /// Restores the production database after testing
    func restoreProductionDatabase() throws {
        let fileManager = FileManager.default
        
        // Check if backup exists
        guard fileManager.fileExists(atPath: backupDBPath) else {
            print("⚠️ No backup database found at: \(backupDBPath)")
            return
        }
        
        // Remove any test database that was created
        if fileManager.fileExists(atPath: originalDBPath) {
            try fileManager.removeItem(atPath: originalDBPath)
        }
        
        // Remove associated test files
        let associatedFiles = [
            containerPath + dbFileName + "-shm",
            containerPath + dbFileName + "-wal"
        ]
        
        for file in associatedFiles {
            if fileManager.fileExists(atPath: file) {
                try? fileManager.removeItem(atPath: file)
            }
        }
        
        // Restore production database
        try fileManager.moveItem(atPath: backupDBPath, toPath: originalDBPath)
        print("✅ Production database restored from: \(backupDBPath)")
    }
    
    /// Cleans up any leftover backup files
    func cleanup() throws {
        let fileManager = FileManager.default
        
        if fileManager.fileExists(atPath: backupDBPath) {
            try fileManager.removeItem(atPath: backupDBPath)
            print("🧹 Cleaned up backup database")
        }
    }
}
