import Foundation
import SwiftData

@Model
class ResModel: Identifiable, Equatable, Hashable, Codable {
    var id: UUID
    var dateCreated: Date = Date()
    @Relationship(deleteRule: .cascade, inverse: \Resume.model) var resumes: [Resume]
    var name: String
    var json: String
    var renderedResumeText: String
    var style: String
    var includeFonts: Bool = false

    // Override the initializer to set the type to '.jsonSource'
    init(
        resumes: [Resume] = [],
        name: String,
        json: String,
        renderedResumeText: String,
        style: String = "Typewriter"
    ) {
        id = UUID()
        self.resumes = resumes
        self.name = name
        self.json = json
        self.renderedResumeText = renderedResumeText
        self.style = style
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id
        case dateCreated
        case name
        case json
        case renderedResumeText
        case style
        case includeFonts
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        dateCreated = try container.decode(Date.self, forKey: .dateCreated)
        name = try container.decode(String.self, forKey: .name)
        json = try container.decode(String.self, forKey: .json)
        renderedResumeText = try container.decode(String.self, forKey: .renderedResumeText)
        style = try container.decode(String.self, forKey: .style)
        includeFonts = try container.decode(Bool.self, forKey: .includeFonts)
        resumes = []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(dateCreated, forKey: .dateCreated)
        try container.encode(name, forKey: .name)
        try container.encode(json, forKey: .json)
        try container.encode(renderedResumeText, forKey: .renderedResumeText)
        try container.encode(style, forKey: .style)
        try container.encode(includeFonts, forKey: .includeFonts)
    }
}
