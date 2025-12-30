import Foundation
import SwiftyJSON

/// A source reference linking a knowledge card to evidence
struct KnowledgeCardSource: Identifiable, Equatable, Codable {
    var id: UUID
    var type: String  // "artifact" or "chat"
    var artifactId: String?
    var chatExcerpt: String?
    var chatContext: String?

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case artifactId = "artifact_id"
        case chatExcerpt = "chat_excerpt"
        case chatContext = "chat_context"
    }

    init(json: JSON) {
        id = UUID(uuidString: json["id"].stringValue) ?? UUID()
        type = json["type"].stringValue
        artifactId = json["artifact_id"].string
        chatExcerpt = json["chat_excerpt"].string
        chatContext = json["chat_context"].string
    }

    func toJSON() -> JSON {
        var json = JSON()
        json["id"].string = id.uuidString
        json["type"].string = type
        if let artifactId {
            json["artifact_id"].string = artifactId
        }
        if let chatExcerpt {
            json["chat_excerpt"].string = chatExcerpt
        }
        if let chatContext {
            json["chat_context"].string = chatContext
        }
        return json
    }
}

/// Knowledge card containing a comprehensive prose summary
struct KnowledgeCardDraft: Identifiable, Equatable, Codable {
    var id: UUID
    var title: String
    var cardType: String?        // "job", "skill", "education", "project"
    var content: String          // Prose summary (500-2000+ words)
    var sources: [KnowledgeCardSource]
    var timePeriod: String?
    var organization: String?
    var location: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case cardType = "type"
        case content
        case sources
        case timePeriod = "time_period"
        case organization
        case location
    }

    init(json: JSON) {
        id = UUID(uuidString: json["id"].stringValue) ?? UUID()
        title = json["title"].stringValue
        cardType = json["type"].string
        content = json["content"].stringValue
        timePeriod = json["time_period"].string
        organization = json["organization"].string
        location = json["location"].string

        // Parse sources array
        if let sourcesArray = json["sources"].array {
            sources = sourcesArray.map { KnowledgeCardSource(json: $0) }
        } else {
            sources = []
        }
    }

    func toJSON() -> JSON {
        var json = JSON()
        json["id"].string = id.uuidString
        json["title"].string = title
        if let cardType {
            json["type"].string = cardType
        }
        json["content"].string = content
        json["sources"] = JSON(sources.map { $0.toJSON() })
        if let timePeriod {
            json["time_period"].string = timePeriod
        }
        if let organization {
            json["organization"].string = organization
        }
        if let location {
            json["location"].string = location
        }
        return json
    }

    /// Word count of the prose content
    var wordCount: Int {
        content.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }
}
struct EvidenceItem: Equatable, Codable {
    var quote: String
    var source: String
    var locator: String?
    var artifactSHA: String?

    enum CodingKeys: String, CodingKey {
        case quote
        case source
        case locator
        case artifactSHA = "artifact_sha"
    }

    init(
        quote: String,
        source: String,
        locator: String? = nil,
        artifactSHA: String? = nil
    ) {
        self.quote = quote
        self.source = source
        self.locator = locator
        self.artifactSHA = artifactSHA
    }
    init(json: JSON) {
        quote = json["quote"].stringValue
        source = json["source"].stringValue
        locator = json["locator"].string
        artifactSHA = json["artifact_sha"].string
    }
    func toJSON() -> JSON {
        var json = JSON()
        json["quote"].string = quote
        json["source"].string = source
        if let locator {
            json["locator"].string = locator
        }
        if let artifactSHA {
            json["artifact_sha"].string = artifactSHA
        }
        return json
    }
}
struct ArtifactRecord: Identifiable, Equatable, Codable {
    var id: String
    var filename: String
    var title: String?
    var contentType: String?
    var sizeInBytes: Int
    var sha256: String?
    var extractedContent: String
    var summary: String?
    var briefDescription: String?
    var metadata: JSON

    enum CodingKeys: String, CodingKey {
        case id
        case filename
        case title
        case contentType = "content_type"
        case sizeInBytes = "size_bytes"
        case sha256
        case extractedContent = "extracted_text"
        case summary
        case briefDescription = "brief_description"
        case metadata
    }

    /// Display name for the artifact (title if available, otherwise filename)
    var displayName: String {
        if let title, !title.isEmpty {
            return title
        }
        return filename
    }

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

    init(
        id: String = UUID().uuidString,
        filename: String,
        title: String? = nil,
        contentType: String? = nil,
        sizeInBytes: Int = 0,
        sha256: String? = nil,
        extractedContent: String = "",
        summary: String? = nil,
        briefDescription: String? = nil,
        metadata: JSON = JSON()
    ) {
        self.id = id
        self.filename = filename
        self.title = title
        self.contentType = contentType
        self.sizeInBytes = sizeInBytes
        self.sha256 = sha256
        self.extractedContent = extractedContent
        self.summary = summary
        self.briefDescription = briefDescription
        self.metadata = metadata
    }
    init(json: JSON) {
        let identifier = json["id"].string
        let sha = json["sha256"].string
        sha256 = sha
        if let identifier, !identifier.isEmpty {
            id = identifier
        } else if let sha, !sha.isEmpty {
            id = sha
        } else {
            id = UUID().uuidString
        }
        filename = json["filename"].stringValue
        // Try multiple sources for title: direct field, or metadata.title
        title = json["title"].string ?? json["metadata"]["title"].string
        contentType = json["content_type"].string
        sizeInBytes = json["size_bytes"].intValue
        // Try both keys for compatibility - artifact records use "extracted_text"
        extractedContent = json["extracted_text"].stringValue.isEmpty
            ? json["extracted_content"].stringValue
            : json["extracted_text"].stringValue
        summary = json["summary"].string
        // Try direct field first, then summary_metadata
        briefDescription = json["brief_description"].string ?? json["summary_metadata"]["brief_description"].string
        metadata = json["metadata"]
    }
    func toJSON() -> JSON {
        var json = JSON()
        json["id"].string = id
        json["filename"].string = filename
        if let title {
            json["title"].string = title
        }
        if let contentType {
            json["content_type"].string = contentType
        }
        json["size_bytes"].int = sizeInBytes
        if let sha256 {
            json["sha256"].string = sha256
        }
        json["extracted_text"].string = extractedContent
        json["metadata"] = metadata
        return json
    }
}
