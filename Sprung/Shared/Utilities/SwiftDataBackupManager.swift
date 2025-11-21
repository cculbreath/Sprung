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
    /// Copies known SwiftData store artifacts from Application Support into a timestamped backup folder.
    @discardableResult
    static func backupCurrentStore() throws -> URL {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw SwiftDataBackupError.appSupportNotFound
        }
        // Create backup root and timestamp folder
        let backupRoot = appSupport.appendingPathComponent(backupFolderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: backupRoot, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let dest = backupRoot.appendingPathComponent(stamp, isDirectory: true)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        // Collect candidate files (.sqlite, .sqlite-shm, .sqlite-wal, .store variants)
        let contents = (try? FileManager.default.contentsOfDirectory(at: appSupport, includingPropertiesForKeys: nil)) ?? []
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
    /// Restores the most recent backup by copying files back into Application Support (destructive overwrite).
    /// Use cautiously; caller responsible for closing any open containers first.
    static func restoreMostRecentBackup() throws {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw SwiftDataBackupError.appSupportNotFound
        }
        let backupRoot = appSupport.appendingPathComponent(backupFolderName, isDirectory: true)
        let folders = (try? FileManager.default.contentsOfDirectory(at: backupRoot, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])) ?? []
        guard let latest = folders.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).last else {
            throw SwiftDataBackupError.noBackupFound
        }
        let backups = try FileManager.default.contentsOfDirectory(at: latest, includingPropertiesForKeys: nil)
        for b in backups {
            let target = appSupport.appendingPathComponent(b.lastPathComponent)
            _ = try? FileManager.default.removeItem(at: target)
            try FileManager.default.copyItem(at: b, to: target)
        }
        Logger.info("♻️ SwiftData store restored from backup \(latest.lastPathComponent)")
    }
    /// Permanently deletes the active SwiftData store files so the app can start fresh.
    /// Caller must quit/relaunch afterwards.
    static func destroyCurrentStore() throws {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw SwiftDataBackupError.appSupportNotFound
        }
        let contents = try FileManager.default.contentsOfDirectory(at: appSupport, includingPropertiesForKeys: nil)
        let candidates = contents.filter { url in
            let name = url.lastPathComponent.lowercased()
            return name.hasSuffix(".sqlite")
                || name.hasSuffix(".sqlite-shm")
                || name.hasSuffix(".sqlite-wal")
                || name.contains("default.store")
        }
        for file in candidates {
            do {
                try FileManager.default.removeItem(at: file)
                Logger.debug("🗑️ Removed store artifact: \(file.lastPathComponent)")
            } catch {
                throw SwiftDataBackupError.copyFailed("Failed to remove \(file.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }
}
