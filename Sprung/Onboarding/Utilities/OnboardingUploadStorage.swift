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
        json["file_url"].string = storageURL.absoluteString
        json["storageUrl"].string = storageURL.absoluteString
        json["size_bytes"].int = sizeInBytes
        if let contentType {
            json["content_type"].string = contentType
        }
        return json
    }
}

struct OnboardingUploadStorage {
    private let uploadsDirectory: URL
    private let fileManager = FileManager.default

    init() {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent("Onboarding/Uploads", isDirectory: true)
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
        let identifier = UUID().uuidString
        let destinationFilename = "\(identifier)_\(sourceURL.lastPathComponent)"
        let destinationURL = uploadsDirectory.appendingPathComponent(destinationFilename)

        do {
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        } catch {
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
