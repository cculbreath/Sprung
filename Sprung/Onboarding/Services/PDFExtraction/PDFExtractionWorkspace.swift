//
//  PDFExtractionWorkspace.swift
//  Sprung
//
//  Manages temp files for PDF extraction in a dedicated workspace directory.
//  Location: ~/Library/Application Support/Sprung/Onboarding/pdf-ocr/{document-name}/
//

import Foundation

/// Manages temp files for PDF extraction in a dedicated workspace directory.
actor PDFExtractionWorkspace {

    /// Base directory for all PDF extraction workspaces
    static var baseDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Sprung/Onboarding/pdf-ocr", isDirectory: true)
    }

    let documentName: String
    let workspaceURL: URL

    private let pagesDirectory: URL
    private let compositesDirectory: URL

    /// Create workspace for a document
    init(documentName: String) throws {
        // Sanitize document name for filesystem
        let sanitized = documentName
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: " ", with: "_")
            .prefix(100)

        self.documentName = String(sanitized)
        self.workspaceURL = Self.baseDirectory.appendingPathComponent(self.documentName, isDirectory: true)
        self.pagesDirectory = workspaceURL.appendingPathComponent("pages", isDirectory: true)
        self.compositesDirectory = workspaceURL.appendingPathComponent("composites", isDirectory: true)

        // Create directory structure
        try FileManager.default.createDirectory(at: pagesDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: compositesDirectory, withIntermediateDirectories: true)
    }

    /// URL for input PDF
    var inputPDFURL: URL {
        workspaceURL.appendingPathComponent("input.pdf")
    }

    /// URL for page image
    func pageImageURL(pageIndex: Int) -> URL {
        pagesDirectory.appendingPathComponent("page_\(String(format: "%04d", pageIndex)).jpg")
    }

    /// URL for judge composite image
    func compositeURL(index: Int) -> URL {
        compositesDirectory.appendingPathComponent("judge_\(index).jpg")
    }

    /// URL for final extracted text (debugging)
    var outputTextURL: URL {
        workspaceURL.appendingPathComponent("output.txt")
    }

    /// Get all page images in order
    func allPageImages() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: pagesDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "jpg" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Get all composite images
    func allComposites() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: compositesDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "jpg" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Save extracted text for debugging
    func saveOutput(_ text: String) throws {
        try text.write(to: outputTextURL, atomically: true, encoding: .utf8)
    }

    /// Clean up workspace (call on successful extraction)
    func cleanup() {
        try? FileManager.default.removeItem(at: workspaceURL)
    }

    /// Clean up all old workspaces (e.g., on app launch)
    static func cleanupAllWorkspaces() {
        try? FileManager.default.removeItem(at: baseDirectory)
    }
}
