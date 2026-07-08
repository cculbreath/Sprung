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
}
