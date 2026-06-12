//
//  CoverRef.swift
//  Sprung
//
//
import Foundation
import SwiftData
import SwiftyJSON
enum CoverRefType: String, Codable {
    case writingSample
    case voicePrimer  // Voice characteristics extracted from writing samples
}
@Model
class CoverRef: Identifiable, Codable {
    var id: String
    var content: String
    var name: String
    var enabledByDefault: Bool
    var type: CoverRefType

    // Voice primer structured fields (only populated when type == .voicePrimer)
    /// JSON-encoded VoiceProfile from voice analysis (VoiceProfileService)
    var voicePrimerJSON: String?

    init(
        name: String = "", content: String = "",
        enabledByDefault: Bool = false, type: CoverRefType,
        voicePrimerJSON: String? = nil
    ) {
        id = UUID().uuidString
        self.content = content
        self.name = name
        self.enabledByDefault = enabledByDefault
        self.type = type
        self.voicePrimerJSON = voicePrimerJSON
    }
    // Manual Codable implementation
    enum CodingKeys: String, CodingKey {
        case id
        case content
        case name
        case enabledByDefault
        case type
        case voicePrimerJSON
    }
    // Required initializer for Decodable
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        content = try container.decode(String.self, forKey: .content)
        name = try container.decode(String.self, forKey: .name)
        enabledByDefault = try container.decode(Bool.self, forKey: .enabledByDefault)
        type = try container.decode(CoverRefType.self, forKey: .type)
        voicePrimerJSON = try container.decodeIfPresent(String.self, forKey: .voicePrimerJSON)
    }
    // Required function for Encodable
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(content, forKey: .content)
        try container.encode(name, forKey: .name)
        try container.encode(enabledByDefault, forKey: .enabledByDefault)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(voicePrimerJSON, forKey: .voicePrimerJSON)
    }

    // MARK: - Voice Profile Accessor

    /// Decode the stored voice profile (the `.voicePrimer` payload — produced
    /// by voice analysis, rendered in prompts via `characteristicPairs`).
    /// Returns nil if this is not a voice primer or the JSON is not set.
    var voiceProfile: VoiceProfile? {
        guard type == .voicePrimer,
              let jsonString = voicePrimerJSON,
              let data = jsonString.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(VoiceProfile.self, from: data)
    }
}
