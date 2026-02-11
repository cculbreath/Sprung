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
    /// JSON-encoded voice primer analysis from VoicePrimerExtractionService
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

    // MARK: - Voice Primer Accessors

    /// Parse the voice primer JSON into SwiftyJSON for programmatic access.
    /// Returns nil if this is not a voice primer or JSON is not set.
    var voicePrimer: SwiftyJSON.JSON? {
        guard type == .voicePrimer,
              let jsonString = voicePrimerJSON,
              let data = jsonString.data(using: .utf8) else {
            return nil
        }
        return try? SwiftyJSON.JSON(data: data)
    }

    /// Extract specific voice characteristic (e.g., "tone", "structure", "vocabulary", "rhetoric")
    func voiceCharacteristic(_ key: String) -> SwiftyJSON.JSON? {
        voicePrimer?[key]
    }

    /// Get tone description
    var toneDescription: String? {
        voicePrimer?["tone"]["description"].string
    }

    /// Get vocabulary technical level
    var vocabularyLevel: String? {
        voicePrimer?["vocabulary"]["technical_level"].string
    }

    /// Get writing strengths from markers
    var writingStrengths: [String] {
        voicePrimer?["markers"]["strengths"].arrayValue.compactMap { $0.string } ?? []
    }

    /// Get writing recommendations from markers
    var writingRecommendations: [String] {
        voicePrimer?["markers"]["recommendations"].arrayValue.compactMap { $0.string } ?? []
    }
}
