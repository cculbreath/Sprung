//
//  UploadFileService.swift
//  Sprung
//
//  Utilities for file validation, remote downloads, and cleanup during uploads.
//

import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class UploadFileService {
    // MARK: - Remote Downloads
    /// Downloads a file from a remote URL to a temporary location.
    func downloadRemoteFile(from url: URL) async throws -> URL {
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw ToolError.executionFailed("Failed to download file from URL (HTTP error)")
        }

        if data.isEmpty {
            throw ToolError.executionFailed("Downloaded file is empty")
        }

        let filename = url.lastPathComponent.isEmpty ? UUID().uuidString : url.lastPathComponent
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString)_\(filename)")

        try data.write(to: temporary)

        Logger.debug("📥 Downloaded remote file: \(url.absoluteString) → \(temporary.path)", category: .ai)
        return temporary
    }

    // MARK: - Image Validation
    /// Validates that the provided data represents a valid image file.
    func validateImageData(data: Data, fileExtension: String) throws {
        if data.isEmpty {
            throw ToolError.executionFailed("Image upload is empty")
        }

        // Try UTType validation on macOS 12+
        if #available(macOS 12.0, *) {
            if let type = UTType(filenameExtension: fileExtension.lowercased()),
               type.conforms(to: .image) {
                return
            }
        }

        // Fallback: Try to load as NSImage
        if NSImage(data: data) == nil {
            throw ToolError.executionFailed("Uploaded file is not a valid image")
        }
    }

    // MARK: - Cleanup
    /// Removes a temporary file, logging any errors but not throwing.
    func cleanupTemporaryFile(at url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
            Logger.debug("🗑️ Cleaned up temporary file: \(url.path)", category: .ai)
        } catch {
            Logger.warning("⚠️ Failed to cleanup temporary file \(url.path): \(error)", category: .ai)
        }
    }
}
