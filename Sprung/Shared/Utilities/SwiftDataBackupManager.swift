//
//  SwiftDataBackupManager.swift
//  Sprung
//
//  Creates timestamped backups of the SwiftData store files in Application Support
//  before migrations or on first launch of the day. Also provides a simple restore.
//
import Foundation
enum SwiftDataBackupError: Error, LocalizedError {
    case appSupportNotFound
    case noBackupFound
    case copyFailed(String)
    var errorDescription: String? {
        switch self {
        case .appSupportNotFound: return "Application Support directory not found"
        case .noBackupFound: return "No backup found to restore"
        case .copyFailed(let reason): return "Backup copy failed: \(reason)"
        }
    }
}
struct SwiftDataBackupManager {
    private static let lastBackupKey = "swiftdata.lastBackupTimestamp"
    private static let backupFolderName = "Sprung_Backups"
    private static let pendingResetKey = "swiftdata.pendingStoreReset"
    /// Create a timestamped backup of SwiftData store files if a backup hasn't
    /// been performed in the last 24 hours.
    static func performPreflightBackupIfNeeded() {
        let now = Date().timeIntervalSince1970
        let last = UserDefaults.standard.double(forKey: lastBackupKey)
        let oneDay: Double = 24 * 60 * 60
        if now - last < oneDay { return }
        do {
            try backupCurrentStore()
            UserDefaults.standard.set(now, forKey: lastBackupKey)
            Logger.debug("📦 SwiftData preflight backup created")
        } catch {
            Logger.warning("⚠️ SwiftData backup skipped: \(error.localizedDescription)")
        }
    }
    /// Copies known SwiftData store artifacts from Application Support/Sprung into a timestamped backup folder.
    @discardableResult
    static func backupCurrentStore() throws -> URL {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw SwiftDataBackupError.appSupportNotFound
        }
        let storeDir = appSupport.appendingPathComponent("Sprung", isDirectory: true)

        // Create backup root and timestamp folder
        let backupRoot = appSupport.appendingPathComponent(backupFolderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: backupRoot, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let dest = backupRoot.appendingPathComponent(stamp, isDirectory: true)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)

        // Collect candidate files (.sqlite, .sqlite-shm, .sqlite-wal, .store variants)
        let contents = (try? FileManager.default.contentsOfDirectory(at: storeDir, includingPropertiesForKeys: nil)) ?? []
        let candidates = contents.filter { url in
            let name = url.lastPathComponent.lowercased()
            return name.hasSuffix(".sqlite") || name.hasSuffix(".sqlite-shm") || name.hasSuffix(".sqlite-wal") || name.contains("default.store")
        }
        for file in candidates {
            let target = dest.appendingPathComponent(file.lastPathComponent)
            do { try FileManager.default.copyItem(at: file, to: target) } catch { throw SwiftDataBackupError.copyFailed("\(file.lastPathComponent): \(error.localizedDescription)") }
        }
        return dest
    }
    /// Restores the most recent backup by copying files back into Application Support/Sprung (destructive overwrite).
    /// Use cautiously; caller responsible for closing any open containers first.
    static func restoreMostRecentBackup() throws {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw SwiftDataBackupError.appSupportNotFound
        }
        let storeDir = appSupport.appendingPathComponent("Sprung", isDirectory: true)
        try? FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)

        let backupRoot = appSupport.appendingPathComponent(backupFolderName, isDirectory: true)
        let folders = (try? FileManager.default.contentsOfDirectory(at: backupRoot, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])) ?? []
        guard let latest = folders.max(by: { $0.lastPathComponent < $1.lastPathComponent }) else {
            throw SwiftDataBackupError.noBackupFound
        }
        let backups = try FileManager.default.contentsOfDirectory(at: latest, includingPropertiesForKeys: nil)
        for b in backups {
            let target = storeDir.appendingPathComponent(b.lastPathComponent)
            _ = try? FileManager.default.removeItem(at: target)
            try FileManager.default.copyItem(at: b, to: target)
        }
        Logger.info("♻️ SwiftData store restored from backup \(latest.lastPathComponent)")
    }
    /// Marks the data store for deletion on next launch.
    /// This avoids SQLite errors from deleting files while they're still open.
    /// Caller should prompt user to quit/relaunch afterwards.
    static func destroyCurrentStore() throws {
        UserDefaults.standard.set(true, forKey: pendingResetKey)
        Logger.info("🗑️ Data store marked for deletion on next launch")
    }

    /// Called early in app startup (before ModelContainer creation) to perform
    /// any pending store deletion that was requested in a previous session.
    /// Returns true if deletion was performed.
    @discardableResult
    static func performPendingResetIfNeeded() -> Bool {
        guard UserDefaults.standard.bool(forKey: pendingResetKey) else {
            return false
        }
        // Clear the flag first to avoid infinite loop if deletion fails
        UserDefaults.standard.removeObject(forKey: pendingResetKey)

        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            Logger.error("❌ Pending reset failed: Application Support not found")
            return false
        }

        let storeDir = appSupport.appendingPathComponent("Sprung", isDirectory: true)
        guard FileManager.default.fileExists(atPath: storeDir.path) else {
            Logger.info("ℹ️ No store directory found to delete")
            return false
        }

        do {
            let contents = try FileManager.default.contentsOfDirectory(at: storeDir, includingPropertiesForKeys: nil)
            let candidates = contents.filter { url in
                let name = url.lastPathComponent.lowercased()
                return name.hasSuffix(".sqlite")
                    || name.hasSuffix(".sqlite-shm")
                    || name.hasSuffix(".sqlite-wal")
                    || name.contains("default.store")
            }
            for file in candidates {
                try FileManager.default.removeItem(at: file)
                Logger.debug("🗑️ Removed store artifact: \(file.lastPathComponent)")
            }
            if candidates.isEmpty {
                Logger.info("ℹ️ No store files found to delete")
                return false
            }
            Logger.info("✅ Data store reset completed successfully")
            return true
        } catch {
            Logger.error("❌ Pending reset failed: \(error.localizedDescription)")
            return false
        }
    }
}
