import Foundation
import SwiftyJSON
import UniformTypeIdentifiers
struct OnboardingProcessedUpload {
    let id: String
    let filename: String
    let storageURL: URL
    let sizeInBytes: Int
    let contentType: String?
    func toJSON() -> JSON {
        var json = JSON()
        json["id"].string = id
        json["filename"].string = filename
        json["fileUrl"].string = storageURL.absoluteString
        json["storageUrl"].string = storageURL.absoluteString
        json["url"].string = storageURL.absoluteString
        json["sizeBytes"].int = sizeInBytes
        if let contentType {
            json["contentType"].string = contentType
        }
        return json
    }
}
struct OnboardingUploadStorage {
    private let uploadsDirectory: URL
    private let fileManager = FileManager.default
    init() {
        guard let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            Logger.error("Failed to locate application support directory for uploads")
            // Fallback to temporary directory
            uploadsDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("Sprung/Onboarding/Uploads", isDirectory: true)
            return
        }
        let directory = base.appendingPathComponent("Sprung/Onboarding/Uploads", isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            do {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            } catch {
                Logger.debug("Failed to create uploads directory: \(error)")
            }
        }
        uploadsDirectory = directory
    }
    func processFile(at sourceURL: URL) throws -> OnboardingProcessedUpload {
        Logger.info("📦 [TRACE] processFile called for: \(sourceURL.lastPathComponent)", category: .ai)
        let identifier = UUID().uuidString
        let destinationFilename = "\(identifier)_\(sourceURL.lastPathComponent)"
        let destinationURL = uploadsDirectory.appendingPathComponent(destinationFilename)
        Logger.info("📦 [TRACE] destination: \(destinationURL.path)", category: .ai)

        // Start accessing security-scoped resource (required for files from NSOpenPanel in sandboxed apps)
        Logger.info("📦 [TRACE] About to call startAccessingSecurityScopedResource", category: .ai)
        let didStartAccessing = sourceURL.startAccessingSecurityScopedResource()
        Logger.info("📦 [TRACE] startAccessingSecurityScopedResource returned: \(didStartAccessing)", category: .ai)
        defer {
            if didStartAccessing {
                Logger.info("📦 [TRACE] Calling stopAccessingSecurityScopedResource", category: .ai)
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            Logger.info("📦 [TRACE] Checking if destination exists", category: .ai)
            if fileManager.fileExists(atPath: destinationURL.path) {
                Logger.info("📦 [TRACE] Removing existing file at destination", category: .ai)
                try fileManager.removeItem(at: destinationURL)
            }
            Logger.info("📦 [TRACE] About to copy file", category: .ai)
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            Logger.info("📦 [TRACE] File copy completed successfully", category: .ai)
        } catch {
            Logger.error("📦 [TRACE] File copy failed: \(error.localizedDescription)", category: .ai)
            throw ToolError.executionFailed("Failed to store uploaded file: \(error.localizedDescription)")
        }
        return OnboardingProcessedUpload(
            id: identifier,
            filename: sourceURL.lastPathComponent,
            storageURL: destinationURL,
            sizeInBytes: fileSize(at: destinationURL),
            contentType: contentType(for: destinationURL)
        )
    }
    func removeFile(at url: URL) {
        try? fileManager.removeItem(at: url)
    }
    private func fileSize(at url: URL) -> Int {
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        let size = attributes?[.size] as? NSNumber
        return size?.intValue ?? 0
    }
    private func contentType(for url: URL) -> String? {
        if #available(macOS 12.0, *) {
            return UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
        }
        return nil
    }
}
