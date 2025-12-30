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
    /// Token count for this card's content (populated during KC generation)
    var tokenCount: Int?

    // MARK: - Fact-Based Knowledge Card Attributes
    /// JSON-encoded array of extracted facts with source attribution
    /// Each fact has: category, statement, confidence, source (artifact_id, location, verbatim_quote)
    var factsJSON: String?
    /// JSON-encoded array of pre-generated resume bullet templates
    var suggestedBulletsJSON: String?
    /// JSON-encoded array of technologies, tools, and frameworks
    var technologiesJSON: String?

    init(
        name: String = "", content: String = "",
        enabledByDefault: Bool = false,
        cardType: String? = nil,
        timePeriod: String? = nil,
        organization: String? = nil,
        location: String? = nil,
        sourcesJSON: String? = nil,
        isFromOnboarding: Bool = false,
        tokenCount: Int? = nil,
        factsJSON: String? = nil,
        suggestedBulletsJSON: String? = nil,
        technologiesJSON: String? = nil
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
        self.tokenCount = tokenCount
        self.factsJSON = factsJSON
        self.suggestedBulletsJSON = suggestedBulletsJSON
        self.technologiesJSON = technologiesJSON
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
        case tokenCount
        case factsJSON
        case suggestedBulletsJSON
        case technologiesJSON
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
        tokenCount = try container.decodeIfPresent(Int.self, forKey: .tokenCount)
        factsJSON = try container.decodeIfPresent(String.self, forKey: .factsJSON)
        suggestedBulletsJSON = try container.decodeIfPresent(String.self, forKey: .suggestedBulletsJSON)
        technologiesJSON = try container.decodeIfPresent(String.self, forKey: .technologiesJSON)
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
        try container.encodeIfPresent(tokenCount, forKey: .tokenCount)
        try container.encodeIfPresent(factsJSON, forKey: .factsJSON)
        try container.encodeIfPresent(suggestedBulletsJSON, forKey: .suggestedBulletsJSON)
        try container.encodeIfPresent(technologiesJSON, forKey: .technologiesJSON)
    }

    // MARK: - Computed Properties for Fact-Based Cards

    /// Whether this card uses the fact-based format (has structured facts)
    var isFactBasedCard: Bool {
        factsJSON != nil || suggestedBulletsJSON != nil
    }

    /// Decoded array of suggested resume bullets
    var suggestedBullets: [String] {
        get {
            guard let json = suggestedBulletsJSON,
                  let data = json.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([String].self, from: data) else {
                return []
            }
            return decoded
        }
        set {
            if newValue.isEmpty {
                suggestedBulletsJSON = nil
            } else if let data = try? JSONEncoder().encode(newValue),
                      let json = String(data: data, encoding: .utf8) {
                suggestedBulletsJSON = json
            }
            // Update content to reflect bullets
            content = newValue.map { "• \($0)" }.joined(separator: "\n")
        }
    }

    /// Decoded array of technologies
    var technologies: [String] {
        get {
            guard let json = technologiesJSON,
                  let data = json.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([String].self, from: data) else {
                return []
            }
            return decoded
        }
        set {
            if newValue.isEmpty {
                technologiesJSON = nil
            } else if let data = try? JSONEncoder().encode(newValue),
                      let json = String(data: data, encoding: .utf8) {
                technologiesJSON = json
            }
        }
    }

    /// Decoded array of extracted facts
    var facts: [ResRefFact] {
        get {
            guard let json = factsJSON,
                  let data = json.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([ResRefFact].self, from: data) else {
                return []
            }
            return decoded
        }
        set {
            if newValue.isEmpty {
                factsJSON = nil
            } else if let data = try? JSONEncoder().encode(newValue),
                      let json = String(data: data, encoding: .utf8) {
                factsJSON = json
            }
        }
    }

    /// Group facts by category for display
    var factsByCategory: [String: [ResRefFact]] {
        Dictionary(grouping: facts, by: { $0.category })
    }

    /// Card type display name with icon
    var cardTypeDisplay: (name: String, icon: String) {
        switch cardType?.lowercased() {
        case "employment", "job":
            return ("Employment", "briefcase.fill")
        case "project":
            return ("Project", "folder.fill")
        case "skill":
            return ("Skill", "star.fill")
        case "education":
            return ("Education", "graduationcap.fill")
        case "achievement":
            return ("Achievement", "trophy.fill")
        default:
            return (cardType ?? "General", "doc.text.fill")
        }
    }
}

// MARK: - Supporting Types

/// Represents an extracted fact from a knowledge card
struct ResRefFact: Codable, Identifiable {
    var id: String { "\(category)-\(statement.prefix(50))" }

    let category: String
    let statement: String
    let confidence: String?
    let source: ResRefFactSource?

    enum CodingKeys: String, CodingKey {
        case category, statement, confidence, source
    }
}

/// Source attribution for a fact
struct ResRefFactSource: Codable {
    let artifactId: String?
    let location: String?
    let verbatimQuote: String?

    enum CodingKeys: String, CodingKey {
        case artifactId = "artifact_id"
        case location
        case verbatimQuote = "verbatim_quote"
    }
}
