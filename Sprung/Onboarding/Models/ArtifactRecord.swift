//
//  ArtifactRecord.swift
//  Sprung
//
//  SwiftData model for artifact records.
//  Consolidated from OnboardingArtifactRecord and the ArtifactRecord struct.
//
import Foundation
import SwiftData
import SwiftyJSON

/// Persisted artifact record with extracted content and metadata.
/// Single source of truth for artifacts - uses SwiftData for persistence.
@Model
final class ArtifactRecord {
    // MARK: - Core Identifiers
    var id: UUID

    // MARK: - Source Information
    /// Source type: "pdf", "git", "vcard", "image", "docx", etc.
    var sourceType: String
    /// Original filename for display
    var filename: String
    /// Hash of source content for detecting re-uploads (SHA256)
    var sha256: String?
    /// MIME content type (e.g., "application/pdf")
    var contentType: String?
    /// File size in bytes
    var sizeInBytes: Int

    // MARK: - Extracted Content
    /// LLM-enriched/extracted text content
    var extractedContent: String
    /// Short summary of the artifact (typically 1-2 paragraphs)
    var summary: String?
    /// Brief description (~10 words)
    var briefDescription: String?
    /// Optional custom title (user-provided or LLM-generated)
    var title: String?

    // MARK: - Knowledge Card Integration
    /// Raw JSON string of the card inventory (DocumentInventory)
    var cardInventoryJSON: String?

    /// True if this artifact has a card inventory (computed from cardInventoryJSON)
    var hasCardInventory: Bool {
        guard let json = cardInventoryJSON else { return false }
        return !json.isEmpty
    }

    // MARK: - Interview Context
    /// When true, full document content is sent to interview LLM (not just summary)
    /// Set for writing samples and resume uploads - helps with voice matching
    var interviewContext: Bool = false

    // MARK: - Metadata
    /// Additional metadata as JSON (git analysis, page count, graphics content, etc.)
    var metadataJSON: String?
    /// Path to raw source file on disk (for files that need to stay on disk)
    var rawFileRelativePath: String?
    /// When the artifact was ingested
    var ingestedAt: Date
    /// Linked plan item ID (if associated with a knowledge card plan item)
    var planItemId: String?

    // MARK: - Session Relationship
    var session: OnboardingSession?

    // MARK: - Computed Properties

    /// True if this artifact is archived (no session, available for reuse)
    var isArchived: Bool {
        session == nil
    }

    /// Display name for the artifact (title if available, otherwise filename)
    var displayName: String {
        if let title, !title.isEmpty {
            return title
        }
        return filename
    }

    /// Folder name for filesystem export (sanitized filename without extension)
    var artifactFolderName: String {
        let baseName: String
        if !filename.isEmpty {
            let nameWithoutExt = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
            baseName = nameWithoutExt.isEmpty ? filename : nameWithoutExt
        } else {
            baseName = id.uuidString
        }
        return baseName
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }

    /// True if this is a PDF document
    var isPDF: Bool {
        contentType == "application/pdf"
    }

    /// True if this is a writing sample (should not have card inventory)
    var isWritingSample: Bool {
        // Check source type
        if sourceType == "writing_sample" {
            return true
        }
        // Check document_type in metadata
        if let docType = metadataString("document_type") {
            if docType == "writingSample" || docType == "writing_sample" {
                return true
            }
        }
        // Check for writing_type in metadata
        if metadataString("writing_type") != nil {
            return true
        }
        return false
    }

    /// ID as string for compatibility with existing code
    var idString: String {
        id.uuidString
    }

    // MARK: - Token Estimation

    /// Estimate token count from text (approximately 4 characters per token for English)
    static func estimateTokens(_ text: String) -> Int {
        max(1, text.count / 4)
    }

    /// Estimated tokens in extracted content
    var extractedContentTokens: Int {
        Self.estimateTokens(extractedContent)
    }

    /// Estimated tokens in summary
    var summaryTokens: Int {
        guard let summary, !summary.isEmpty else { return 0 }
        return Self.estimateTokens(summary)
    }

    // MARK: - Metadata Accessors

    /// Parsed metadata as SwiftyJSON (for backwards compatibility with views)
    var metadata: JSON {
        guard let metadataJSON,
              let data = metadataJSON.data(using: .utf8) else {
            return JSON()
        }
        return (try? JSON(data: data)) ?? JSON()
    }

    /// Parsed card inventory (lazily decoded from JSON string)
    var cardInventory: DocumentInventory? {
        guard let jsonString = cardInventoryJSON,
              let data = jsonString.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(DocumentInventory.self, from: data)
        } catch {
            Logger.warning("Failed to decode card inventory for \(filename): \(error.localizedDescription)", category: .ai)
            return nil
        }
    }

    /// Get a metadata value as a string
    func metadataString(_ key: String) -> String? {
        guard let metadataJSON,
              let data = metadataJSON.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return dict[key] as? String
    }

    /// True if graphics extraction failed for this PDF
    var graphicsExtractionFailed: Bool {
        metadataString("graphics_extraction_status") == "failed"
    }

    /// Error message from graphics extraction (if failed)
    var graphicsExtractionError: String? {
        metadataString("graphics_extraction_error")
    }

    /// True if this artifact has graphics content descriptions
    var hasGraphicsContent: Bool {
        guard let graphics = metadataString("graphics_content") else { return false }
        return !graphics.isEmpty
    }

    /// Plain text content from PDFKit extraction (Pass 1)
    var plainTextContent: String? {
        metadataString("plain_text_content")
    }

    /// Graphics content descriptions from LLM extraction (Pass 2)
    var graphicsContent: String? {
        metadataString("graphics_content")
    }

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        sourceType: String,
        filename: String,
        sha256: String? = nil,
        contentType: String? = nil,
        sizeInBytes: Int = 0,
        extractedContent: String,
        summary: String? = nil,
        briefDescription: String? = nil,
        title: String? = nil,
        cardInventoryJSON: String? = nil,
        interviewContext: Bool = false,
        metadataJSON: String? = nil,
        rawFileRelativePath: String? = nil,
        ingestedAt: Date = Date(),
        planItemId: String? = nil
    ) {
        self.id = id
        self.sourceType = sourceType
        self.filename = filename
        self.sha256 = sha256
        self.contentType = contentType
        self.sizeInBytes = sizeInBytes
        self.extractedContent = extractedContent
        self.summary = summary
        self.briefDescription = briefDescription
        self.title = title
        self.cardInventoryJSON = cardInventoryJSON
        self.interviewContext = interviewContext
        self.metadataJSON = metadataJSON
        self.rawFileRelativePath = rawFileRelativePath
        self.ingestedAt = ingestedAt
        self.planItemId = planItemId
    }
}

// MARK: - Equatable Conformance

extension ArtifactRecord: Equatable {
    static func == (lhs: ArtifactRecord, rhs: ArtifactRecord) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Hashable Conformance

extension ArtifactRecord: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
