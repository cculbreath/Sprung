import Foundation
import SwiftData

@Model
class ResRef: Identifiable, Codable {
    var id: UUID // Change from String to UUID
    var content: String
    var name: String
    var enabledByDefault: Bool

    var enabledResumes: [Resume] = []

    init(
        name: String = "", content: String = "",
        enabledByDefault: Bool = false
    ) {
        id = UUID() // Ensure UUID is used correctly
        self.content = content
        self.name = name
        self.enabledByDefault = enabledByDefault
    }

    // MARK: - Codable
    enum CodingKeys: String, CodingKey {
        case id
        case content
        case name
        case enabledByDefault
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        content = try container.decode(String.self, forKey: .content)
        name = try container.decode(String.self, forKey: .name)
        enabledByDefault = try container.decode(Bool.self, forKey: .enabledByDefault)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(content, forKey: .content)
        try container.encode(name, forKey: .name)
        try container.encode(enabledByDefault, forKey: .enabledByDefault)
    }
}
