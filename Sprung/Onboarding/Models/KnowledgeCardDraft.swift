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
