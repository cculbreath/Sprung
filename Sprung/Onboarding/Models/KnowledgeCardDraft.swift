import Foundation
import SwiftyJSON

/// A source reference linking a knowledge card to evidence
struct KnowledgeCardSource: Identifiable, Equatable {
    var id: UUID
    var type: String  // "artifact" or "chat"
    var artifactId: String?
    var chatExcerpt: String?
    var chatContext: String?

    init(
        id: UUID = UUID(),
        type: String,
        artifactId: String? = nil,
        chatExcerpt: String? = nil,
        chatContext: String? = nil
    ) {
        self.id = id
        self.type = type
        self.artifactId = artifactId
        self.chatExcerpt = chatExcerpt
        self.chatContext = chatContext
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
struct KnowledgeCardDraft: Identifiable, Equatable {
    var id: UUID
    var title: String
    var cardType: String?        // "job", "skill", "education", "project"
    var content: String          // Prose summary (500-2000+ words)
    var sources: [KnowledgeCardSource]
    var timePeriod: String?
    var organization: String?
    var location: String?

    init(
        id: UUID = UUID(),
        title: String = "",
        cardType: String? = nil,
        content: String = "",
        sources: [KnowledgeCardSource] = [],
        timePeriod: String? = nil,
        organization: String? = nil,
        location: String? = nil
    ) {
        self.id = id
        self.title = title
        self.cardType = cardType
        self.content = content
        self.sources = sources
        self.timePeriod = timePeriod
        self.organization = organization
        self.location = location
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
struct EvidenceItem: Equatable {
    var quote: String
    var source: String
    var locator: String?
    var artifactSHA: String?
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
struct ArtifactRecord: Identifiable, Equatable {
    var id: String
    var filename: String
    var contentType: String?
    var sizeInBytes: Int
    var sha256: String?
    var extractedContent: String
    var metadata: JSON
    init(
        id: String = UUID().uuidString,
        filename: String,
        contentType: String? = nil,
        sizeInBytes: Int = 0,
        sha256: String? = nil,
        extractedContent: String = "",
        metadata: JSON = JSON()
    ) {
        self.id = id
        self.filename = filename
        self.contentType = contentType
        self.sizeInBytes = sizeInBytes
        self.sha256 = sha256
        self.extractedContent = extractedContent
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
        contentType = json["content_type"].string
        sizeInBytes = json["size_bytes"].intValue
        // Try both keys for compatibility - artifact records use "extracted_text"
        extractedContent = json["extracted_text"].stringValue.isEmpty
            ? json["extracted_content"].stringValue
            : json["extracted_text"].stringValue
        metadata = json["metadata"]
    }
    func toJSON() -> JSON {
        var json = JSON()
        json["id"].string = id
        json["filename"].string = filename
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
struct ExperienceContext {
    var timelineEntry: JSON
    var artifacts: [ArtifactRecord]
    var transcript: String
    init(timelineEntry: JSON, artifacts: [ArtifactRecord] = [], transcript: String = "") {
        self.timelineEntry = timelineEntry
        self.artifacts = artifacts
        self.transcript = transcript
    }
}
