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

    // MARK: - Knowledge Extraction
    /// Raw JSON string of extracted skills (Skill array)
    var skillsJSON: String?
    /// Raw JSON string of narrative knowledge cards (KnowledgeCard array)
    var narrativeCardsJSON: String?

    /// True if this artifact has skills extracted
    var hasSkills: Bool {
        guard let json = skillsJSON else { return false }
        return !json.isEmpty
    }

    /// True if this artifact has narrative cards extracted
    var hasNarrativeCards: Bool {
        guard let json = narrativeCardsJSON else { return false }
        return !json.isEmpty
    }

    /// True if this artifact has any knowledge extraction
    var hasKnowledgeExtraction: Bool {
        hasSkills || hasNarrativeCards
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
        ArtifactRecordService.folderName(for: self)
    }

    /// True if this is a PDF document
    var isPDF: Bool {
        contentType == "application/pdf"
    }

    /// True if this is a writing sample (should not have card inventory)
    var isWritingSample: Bool {
        ArtifactRecordService.isWritingSample(self)
    }

    /// True if this is a git repository artifact
    var isGitRepo: Bool {
        sourceType == "git" || sourceType == "git_repository"
    }

    /// True if this is a document artifact (not a writing sample or git repo)
    /// Used for filtering regeneration options
    var isDocumentArtifact: Bool {
        !isWritingSample && !isGitRepo
    }

    /// ID as string for compatibility with existing code
    var idString: String {
        id.uuidString
    }

    // MARK: - Token Estimation

    /// Estimate token count from text (approximately 4 characters per token for English)
    static func estimateTokens(_ text: String) -> Int {
        ArtifactRecordService.estimateTokens(for: text)
    }

    /// Estimated tokens in extracted content
    var extractedContentTokens: Int {
        ArtifactRecordService.estimateExtractedContentTokens(for: self)
    }

    /// Estimated tokens in summary
    var summaryTokens: Int {
        ArtifactRecordService.estimateSummaryTokens(for: self)
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

    /// Parsed skills (lazily decoded from JSON string)
    var skills: [Skill]? {
        ArtifactRecordService.extractSkills(from: self)
    }

    /// Parsed narrative cards (lazily decoded from JSON string)
    var narrativeCards: [KnowledgeCard]? {
        ArtifactRecordService.extractNarrativeCards(from: self)
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
        skillsJSON: String? = nil,
        narrativeCardsJSON: String? = nil,
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
        self.skillsJSON = skillsJSON
        self.narrativeCardsJSON = narrativeCardsJSON
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

// MARK: - Sendable Conformance
// SwiftData @Model classes require @unchecked Sendable for cross-actor usage.
// This is safe because:
// 1. All mutations occur on @MainActor (via ArtifactRecordStore)
// 2. The ModelContext enforces single-threaded access
// 3. Reads across actors access immutable snapshots after model is persisted
//
// THREAD SAFETY REQUIREMENTS:
// - NEVER mutate ArtifactRecord properties outside @MainActor context
// - Always use ArtifactRecordStore methods for updates
// - Treat cross-actor references as read-only snapshots
extension ArtifactRecord: @unchecked Sendable {}

