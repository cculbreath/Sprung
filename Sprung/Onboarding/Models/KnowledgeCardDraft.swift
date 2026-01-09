import Foundation
import SwiftyJSON

/// Lightweight display info for artifacts in knowledge card review UI.
/// Uses String id to match KnowledgeCardSource.artifactId references.
struct ArtifactDisplayInfo: Identifiable {
    let id: String
    let filename: String
    let title: String?

    init(from record: ArtifactRecord) {
        self.id = record.id.uuidString
        self.filename = record.filename
        self.title = record.title
    }
}

/// A source reference linking a knowledge card to evidence
struct KnowledgeCardSource: Identifiable, Equatable, Codable {
    var id: UUID
    var type: String  // "artifact" or "chat"
    var artifactId: String?
    var chatExcerpt: String?
    var chatContext: String?

    init(json: JSON) {
        id = UUID(uuidString: json["id"].stringValue) ?? UUID()
        type = json["type"].stringValue
        artifactId = json["artifactId"].string
        chatExcerpt = json["chatExcerpt"].string
        chatContext = json["chatContext"].string
    }

    func toJSON() -> JSON {
        var json = JSON()
        json["id"].string = id.uuidString
        json["type"].string = type
        if let artifactId {
            json["artifactId"].string = artifactId
        }
        if let chatExcerpt {
            json["chatExcerpt"].string = chatExcerpt
        }
        if let chatContext {
            json["chatContext"].string = chatContext
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

    init(json: JSON) {
        id = UUID(uuidString: json["id"].stringValue) ?? UUID()
        title = json["title"].stringValue
        cardType = json["cardType"].string
        content = json["content"].stringValue
        timePeriod = json["timePeriod"].string
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
            json["cardType"].string = cardType
        }
        json["content"].string = content
        json["sources"] = JSON(sources.map { $0.toJSON() })
        if let timePeriod {
            json["timePeriod"].string = timePeriod
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
