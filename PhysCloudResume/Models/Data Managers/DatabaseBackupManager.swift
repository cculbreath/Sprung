import Foundation

enum DatabaseBackupManager {
  static private let storeFilename = "default.store"

  static func backupDatabase() {
    // Debug: Print current directory locations
    guard let sourceURL = getSourceStoreURL() else {
      print("❌ Error: Could not locate source database")
      return
    }
    print("📁 Source URL: \(sourceURL)")

    // Check if source file exists
    let fileExists = FileManager.default.fileExists(atPath: sourceURL.path)
    print("📂 Source file exists: \(fileExists)")

    guard let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
      print("❌ Error: Could not locate Downloads directory")
      return
    }
    print("📁 Downloads URL: \(downloadsURL)")

    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd_HHmm"
    let timestamp = dateFormatter.string(from: Date())
    let destinationURL = downloadsURL.appendingPathComponent("PhysCloudBackup_\(timestamp).store")
    print("📁 Destination URL: \(destinationURL)")

    do {
      if FileManager.default.fileExists(atPath: destinationURL.path) {
        try FileManager.default.removeItem(at: destinationURL)
        print("🗑️ Removed existing backup file")
      }

      // Try to list contents of source directory
      if let contents = try? FileManager.default.contentsOfDirectory(at: sourceURL.deletingLastPathComponent(), includingPropertiesForKeys: nil) {
        print("📚 Directory contents: \(contents)")
      }

      try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
      print("✅ Database backup successful: \(destinationURL.lastPathComponent)")
    } catch {
      print("❌ Backup failed with error: \(error.localizedDescription)")
    }
  }

  static func restoreDatabase(from backupURL: URL) {
    guard let destinationURL = getSourceStoreURL() else {
      print("Error: Could not locate destination database")
      return
    }

    do {
      if FileManager.default.fileExists(atPath: destinationURL.path) {
        try FileManager.default.removeItem(at: destinationURL)
      }
      try FileManager.default.copyItem(at: backupURL, to: destinationURL)
      print("Database restore successful")
    } catch {
      print("Restore failed: \(error.localizedDescription)")
    }
  }

  static private func getSourceStoreURL() -> URL? {
    guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
      return nil
    }

    // Changed this to look directly in Application Support instead of a subfolder
    let storeURL = appSupport.appendingPathComponent(storeFilename)
    return storeURL
  }
}
