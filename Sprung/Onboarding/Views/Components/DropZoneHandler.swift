//
//  DropZoneHandler.swift
//  Sprung
//
//  Shared utility for handling file drops across the onboarding UI.
//  Extracts common drop handling logic for reuse in multiple drop zones.
//
import SwiftUI
import UniformTypeIdentifiers

/// Shared handler for processing file drops
struct DropZoneHandler {
    /// File extensions accepted for drops
    static let acceptedExtensions = Set([
        "pdf", "docx", "txt", "png", "jpg", "jpeg", "md", "json", "gif", "webp", "heic", "html", "htm"
    ])

    /// UTTypes accepted for drag and drop - includes file URLs and direct image types
    static let acceptedDropTypes: [UTType] = [
        .fileURL,
        .image,
        .png,
        .jpeg,
        .gif,
        .heic
    ]

    /// Process dropped items and return valid file URLs
    static func handleDrop(providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
        Logger.debug("📥 Drop received with \(providers.count) provider(s)", category: .ai)

        // Log what types each provider supports
        for (index, provider) in providers.enumerated() {
            let types = provider.registeredTypeIdentifiers
            Logger.debug("📥 Provider \(index): \(types.joined(separator: ", "))", category: .ai)
        }

        Task {
            var collected: [URL] = []

            for provider in providers {
                // Try file URL first (e.g., from Finder)
                if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                    if let url = await loadFileURL(from: provider) {
                        if isFileTypeAllowed(url) {
                            collected.append(url)
                            Logger.debug("📥 Loaded file URL: \(url.lastPathComponent)", category: .ai)
                        } else {
                            Logger.debug("📥 Rejected file (type not allowed): \(url.lastPathComponent)", category: .ai)
                        }
                    }
                }
                // Try loading as image data (e.g., from Photos app or browser)
                else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    if let url = await loadImageData(from: provider) {
                        collected.append(url)
                        Logger.debug("📥 Loaded image data, saved to: \(url.lastPathComponent)", category: .ai)
                    }
                }
            }

            let finalURLs = collected
            if !finalURLs.isEmpty {
                Logger.info("📥 Processing \(finalURLs.count) dropped file(s)", category: .ai)
                await MainActor.run {
                    completion(finalURLs)
                }
            } else {
                Logger.warning("📥 No valid files found in drop", category: .ai)
            }
        }
    }

    /// Check if file extension is allowed
    static func isFileTypeAllowed(_ url: URL) -> Bool {
        let fileExtension = url.pathExtension.lowercased()
        return acceptedExtensions.contains(fileExtension)
    }

    /// Load a file URL from an NSItemProvider
    static func loadFileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                if let error {
                    Logger.debug("📥 Error loading file URL: \(error.localizedDescription)", category: .ai)
                }
                if let url = item as? URL {
                    continuation.resume(returning: url)
                } else if let data = item as? Data,
                          let string = String(data: data, encoding: .utf8),
                          let url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    /// Load image data and save to a temporary file
    static func loadImageData(from provider: NSItemProvider) async -> URL? {
        // Try specific image types first, then fall back to generic image
        let imageTypes: [UTType] = [.png, .jpeg, .gif, .heic, .image]

        for imageType in imageTypes {
            if provider.hasItemConformingToTypeIdentifier(imageType.identifier) {
                if let url = await loadImageOfType(imageType, from: provider) {
                    return url
                }
            }
        }
        return nil
    }

    private static func loadImageOfType(_ type: UTType, from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, error in
                if let error {
                    Logger.debug("📥 Error loading image data (\(type.identifier)): \(error.localizedDescription)", category: .ai)
                    continuation.resume(returning: nil)
                    return
                }

                guard let data else {
                    continuation.resume(returning: nil)
                    return
                }

                // Determine file extension
                let ext: String
                switch type {
                case .png: ext = "png"
                case .jpeg: ext = "jpg"
                case .gif: ext = "gif"
                case .heic: ext = "heic"
                default: ext = "png" // Default to PNG for generic image type
                }

                // Save to temp file
                let tempDir = FileManager.default.temporaryDirectory
                let filename = "dropped_image_\(UUID().uuidString).\(ext)"
                let tempURL = tempDir.appendingPathComponent(filename)

                do {
                    try data.write(to: tempURL)
                    Logger.debug("📥 Saved dropped image to temp file: \(filename)", category: .ai)
                    continuation.resume(returning: tempURL)
                } catch {
                    Logger.error("📥 Failed to save dropped image: \(error.localizedDescription)", category: .ai)
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
