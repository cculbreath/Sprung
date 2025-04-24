//
//  DatabaseBackupManager.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 2/27/25.
//

import Foundation

enum DatabaseBackupManager {
    private static let storeFilename = "default.store"

    static func backupDatabase() {
        // Debug: Print current directory locations
        guard let sourceURL = getSourceStoreURL() else {
            return
        }

        // Check if source file exists
        let fileExists = FileManager.default.fileExists(atPath: sourceURL.path)

        guard let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            return
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HHmm"
        let timestamp = dateFormatter.string(from: Date())
        let destinationURL = downloadsURL.appendingPathComponent("PhysCloudBackup_\(timestamp).store")

        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }

            // Try to list contents of source directory
            if let contents = try? FileManager.default.contentsOfDirectory(at: sourceURL.deletingLastPathComponent(), includingPropertiesForKeys: nil) {}

            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        } catch {}
    }

    static func restoreDatabase(from backupURL: URL) {
        guard let destinationURL = getSourceStoreURL() else {
            return
        }

        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: backupURL, to: destinationURL)
        } catch {}
    }

    private static func getSourceStoreURL() -> URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }

        // Changed this to look directly in Application Support instead of a subfolder
        let storeURL = appSupport.appendingPathComponent(storeFilename)
        return storeURL
    }
}
