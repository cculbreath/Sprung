import Foundation
import SwiftData

enum CoverRefType: String, Codable {
    case writingSample
    case backgroundFact
}

@Model
class CoverRef: Identifiable, Codable {
    var id: String
    var content: String
    var name: String
    var enabledByDefault: Bool
    var type: CoverRefType

    init(
        name: String = "", content: String = "",
        enabledByDefault: Bool = false, type: CoverRefType
    ) {
        id = UUID().uuidString
        self.content = content
        self.name = name
        self.enabledByDefault = enabledByDefault
        self.type = type
    }

    // Manual Codable implementation
    enum CodingKeys: String, CodingKey {
        case id
        case content
        case name
        case enabledByDefault
        case type
    }

    // Required initializer for Decodable
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        content = try container.decode(String.self, forKey: .content)
        name = try container.decode(String.self, forKey: .name)
        enabledByDefault = try container.decode(Bool.self, forKey: .enabledByDefault)
        type = try container.decode(CoverRefType.self, forKey: .type)
    }

    // Required function for Encodable
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(content, forKey: .content)
        try container.encode(name, forKey: .name)
        try container.encode(enabledByDefault, forKey: .enabledByDefault)
        try container.encode(type, forKey: .type)
    }
}
