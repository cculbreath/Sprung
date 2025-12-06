//
//  ResRef.swift
//  Sprung
//
//
import Foundation
import SwiftData
@Model
class ResRef: Identifiable, Codable {
    var id: UUID
    var content: String
    var name: String
    var enabledByDefault: Bool
    var enabledResumes: [Resume] = []

    // MARK: - Knowledge Card Attributes (from onboarding)
    /// Category: "job", "skill", "education", "project", or nil for manually created
    var cardType: String?
    /// Date range (e.g., "2020-09 to 2024-06")
    var timePeriod: String?
    /// Company, university, or organization name
    var organization: String?
    /// Location (city, state, or "Remote")
    var location: String?
    /// JSON-encoded sources array linking to evidence artifacts
    var sourcesJSON: String?
    /// Indicates this was created via onboarding interview
    var isFromOnboarding: Bool = false

    init(
        name: String = "", content: String = "",
        enabledByDefault: Bool = false,
        cardType: String? = nil,
        timePeriod: String? = nil,
        organization: String? = nil,
        location: String? = nil,
        sourcesJSON: String? = nil,
        isFromOnboarding: Bool = false
    ) {
        id = UUID()
        self.content = content
        self.name = name
        self.enabledByDefault = enabledByDefault
        self.cardType = cardType
        self.timePeriod = timePeriod
        self.organization = organization
        self.location = location
        self.sourcesJSON = sourcesJSON
        self.isFromOnboarding = isFromOnboarding
    }
    // MARK: - Codable
    enum CodingKeys: String, CodingKey {
        case id
        case content
        case name
        case enabledByDefault
        case cardType
        case timePeriod
        case organization
        case location
        case sourcesJSON
        case isFromOnboarding
    }
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        content = try container.decode(String.self, forKey: .content)
        name = try container.decode(String.self, forKey: .name)
        enabledByDefault = try container.decode(Bool.self, forKey: .enabledByDefault)
        cardType = try container.decodeIfPresent(String.self, forKey: .cardType)
        timePeriod = try container.decodeIfPresent(String.self, forKey: .timePeriod)
        organization = try container.decodeIfPresent(String.self, forKey: .organization)
        location = try container.decodeIfPresent(String.self, forKey: .location)
        sourcesJSON = try container.decodeIfPresent(String.self, forKey: .sourcesJSON)
        isFromOnboarding = try container.decodeIfPresent(Bool.self, forKey: .isFromOnboarding) ?? false
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(content, forKey: .content)
        try container.encode(name, forKey: .name)
        try container.encode(enabledByDefault, forKey: .enabledByDefault)
        try container.encodeIfPresent(cardType, forKey: .cardType)
        try container.encodeIfPresent(timePeriod, forKey: .timePeriod)
        try container.encodeIfPresent(organization, forKey: .organization)
        try container.encodeIfPresent(location, forKey: .location)
        try container.encodeIfPresent(sourcesJSON, forKey: .sourcesJSON)
        try container.encode(isFromOnboarding, forKey: .isFromOnboarding)
    }
}
