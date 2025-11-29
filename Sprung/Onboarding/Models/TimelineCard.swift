import Foundation
import SwiftyJSON
struct TimelineCard: Identifiable, Equatable {
    var id: String
    var title: String
    var organization: String
    var location: String
    var start: String
    var end: String
    var summary: String
    var highlights: [String]
    init(
        id: String = UUID().uuidString,
        title: String = "",
        organization: String = "",
        location: String = "",
        start: String = "",
        end: String = "",
        summary: String = "",
        highlights: [String] = []
    ) {
        self.id = id
        self.title = title
        self.organization = organization
        self.location = location
        self.start = start
        self.end = end
        self.summary = summary
        self.highlights = highlights
    }
    init?(json: JSON) {
        let rawId = json["id"].string ?? json["identifier"].string
        guard let resolvedId = rawId?.trimmingCharacters(in: .whitespacesAndNewlines), !resolvedId.isEmpty else {
            return nil
        }
        id = resolvedId
        title = json["title"].stringValue
        organization = json["organization"].stringValue
        location = json["location"].stringValue
        start = json["start"].stringValue
        end = json["end"].stringValue
        summary = json["summary"].stringValue
        highlights = json["highlights"].arrayValue.compactMap { entry in
            let trimmed = entry.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }
    init(id: String = UUID().uuidString, fields: JSON) {
        self.id = id
        title = fields["title"].stringValue
        organization = fields["organization"].stringValue
        location = fields["location"].stringValue
        start = fields["start"].stringValue
        end = fields["end"].stringValue
        summary = fields["summary"].stringValue
        highlights = fields["highlights"].arrayValue.compactMap { entry in
            let trimmed = entry.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }
    func applying(fields: JSON) -> TimelineCard {
        TimelineCard(
            id: id,
            title: fields["title"].string ?? title,
            organization: fields["organization"].string ?? organization,
            location: fields["location"].string ?? location,
            start: fields["start"].string ?? start,
            end: fields["end"].string ?? end,
            summary: fields["summary"].string ?? summary,
            highlights: fields["highlights"].array.map { array in
                array.compactMap { entry in
                    let trimmed = entry.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? nil : trimmed
                }
            } ?? highlights
        )
    }
    var json: JSON {
        var payload = JSON()
        payload["id"].string = id
        payload["title"].string = title
        payload["organization"].string = organization
        payload["location"].string = location
        payload["start"].string = start
        payload["end"].string = end
        payload["summary"].string = summary
        payload["highlights"] = JSON(highlights)
        return payload
    }
}

// MARK: - Codable Conformance
extension TimelineCard: Codable {}
