//
//  KnowledgeCard.swift
//  Sprung
//
//  SwiftData model for knowledge cards - the unified representation of
//  career narratives extracted from documents during onboarding or created manually.
//
//  This replaces the former ResRef model and KnowledgeCard struct.
//

import Foundation
import SwiftData

// MARK: - Card Type

/// Type of knowledge card
enum CardType: String, Codable, CaseIterable {
    case employment  // Role at an organization
    case project     // Specific initiative or deliverable
    case achievement // Award, publication, recognition
    case education   // Degree or credential

    var displayName: String {
        switch self {
        case .employment: return "Employment"
        case .project: return "Project"
        case .achievement: return "Achievement"
        case .education: return "Education"
        }
    }

    var icon: String {
        switch self {
        case .employment: return "briefcase.fill"
        case .project: return "folder.fill"
        case .achievement: return "trophy.fill"
        case .education: return "graduationcap.fill"
        }
    }
}

// MARK: - Knowledge Card Model

@Model
class KnowledgeCard: Identifiable, Codable {
    var id: UUID

    // MARK: - Core Fields

    /// Display title for the card
    var title: String

    /// The narrative content (500-2000 word story with WHY/JOURNEY/LESSONS)
    var narrative: String

    /// Type of card (employment, project, achievement, education)
    var cardTypeRaw: String?

    /// Date range (e.g., "2020-09 to 2024-06")
    var dateRange: String?

    /// Company, university, or organization name
    var organization: String?

    /// Location (city, state, or "Remote")
    var location: String?

    // MARK: - Evidence & Metadata (JSON-encoded)

    /// JSON-encoded array of EvidenceAnchor linking narrative to source documents
    var evidenceAnchorsJSON: String?

    /// JSON-encoded ExtractableMetadata (domains, scale, keywords)
    var extractableJSON: String?

    /// JSON-encoded array of related card UUIDs
    var relatedCardIdsJSON: String?

    // MARK: - Resume Integration

    /// Whether this card is enabled by default for new resumes
    var enabledByDefault: Bool = false

    /// Resumes that have this card enabled
    var enabledResumes: [Resume] = []

    // MARK: - Onboarding Metadata

    /// Indicates this was created via onboarding interview
    var isFromOnboarding: Bool = false

    /// Token count for this card's content
    var tokenCount: Int?

    /// Cards created during onboarding start as pending until user approves
    var isPending: Bool = false

    // MARK: - Fact-Based Card Attributes

    /// JSON-encoded array of extracted facts with source attribution
    var factsJSON: String?

    /// JSON-encoded array of pre-generated resume bullet templates
    var suggestedBulletsJSON: String?

    /// JSON-encoded array of technologies, tools, and frameworks
    var technologiesJSON: String?

    /// JSON-encoded array of quantified outcomes
    var outcomesJSON: String?

    /// Evidence quality: "strong", "moderate", "weak"
    var evidenceQuality: String?

    /// JSON-encoded array of verbatim excerpts preserving voice
    var verbatimExcerptsJSON: String?

    /// For skill cards: JSON-encoded array of KnowledgeCard UUIDs that demonstrate this skill
    var evidenceCardIdsJSON: String?

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        title: String = "",
        narrative: String = "",
        cardType: CardType? = nil,
        dateRange: String? = nil,
        organization: String? = nil,
        location: String? = nil,
        evidenceAnchors: [EvidenceAnchor] = [],
        extractable: ExtractableMetadata? = nil,
        relatedCardIds: [UUID] = [],
        enabledByDefault: Bool = false,
        isFromOnboarding: Bool = false,
        tokenCount: Int? = nil,
        isPending: Bool = false
    ) {
        self.id = id
        self.title = title
        self.narrative = narrative
        self.cardTypeRaw = cardType?.rawValue
        self.dateRange = dateRange
        self.organization = organization
        self.location = location
        self.enabledByDefault = enabledByDefault
        self.isFromOnboarding = isFromOnboarding
        self.tokenCount = tokenCount
        self.isPending = isPending

        // Encode complex types to JSON
        self.evidenceAnchors = evidenceAnchors
        if let extractable = extractable {
            self.extractable = extractable
        }
        self.relatedCardIds = relatedCardIds
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, title, narrative
        case cardTypeRaw = "card_type"
        case dateRange = "date_range"
        case organization, location
        case evidenceAnchorsJSON = "evidence_anchors"
        case extractableJSON = "extractable"
        case relatedCardIdsJSON = "related_card_ids"
        case enabledByDefault
        case isFromOnboarding
        case tokenCount
        case isPending
        case factsJSON, suggestedBulletsJSON, technologiesJSON
        case outcomesJSON, evidenceQuality, verbatimExcerptsJSON
        case evidenceCardIdsJSON
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Handle id as UUID or String
        if let uuidString = try? container.decode(String.self, forKey: .id) {
            self.id = UUID(uuidString: uuidString) ?? UUID()
        } else {
            self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        }

        self.title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        self.narrative = try container.decodeIfPresent(String.self, forKey: .narrative) ?? ""
        self.cardTypeRaw = try container.decodeIfPresent(String.self, forKey: .cardTypeRaw)
        self.dateRange = try container.decodeIfPresent(String.self, forKey: .dateRange)
        self.organization = try container.decodeIfPresent(String.self, forKey: .organization)
        self.location = try container.decodeIfPresent(String.self, forKey: .location)
        self.enabledByDefault = try container.decodeIfPresent(Bool.self, forKey: .enabledByDefault) ?? false
        self.isFromOnboarding = try container.decodeIfPresent(Bool.self, forKey: .isFromOnboarding) ?? false
        self.tokenCount = try container.decodeIfPresent(Int.self, forKey: .tokenCount)
        self.isPending = try container.decodeIfPresent(Bool.self, forKey: .isPending) ?? false

        // Decode evidence anchors - handle both JSON string and direct array
        if let anchorsString = try? container.decode(String.self, forKey: .evidenceAnchorsJSON) {
            self.evidenceAnchorsJSON = anchorsString
        } else if let anchors = try? container.decode([EvidenceAnchor].self, forKey: .evidenceAnchorsJSON),
                  let data = try? JSONEncoder().encode(anchors),
                  let json = String(data: data, encoding: .utf8) {
            self.evidenceAnchorsJSON = json
        }

        // Decode extractable - handle both JSON string and direct object
        if let extractableString = try? container.decode(String.self, forKey: .extractableJSON) {
            self.extractableJSON = extractableString
        } else if let extractable = try? container.decode(ExtractableMetadata.self, forKey: .extractableJSON),
                  let data = try? JSONEncoder().encode(extractable),
                  let json = String(data: data, encoding: .utf8) {
            self.extractableJSON = json
        }

        // Decode related card IDs - handle both JSON string and direct array
        if let relatedString = try? container.decode(String.self, forKey: .relatedCardIdsJSON) {
            self.relatedCardIdsJSON = relatedString
        } else if let relatedIds = try? container.decode([UUID].self, forKey: .relatedCardIdsJSON),
                  let data = try? JSONEncoder().encode(relatedIds),
                  let json = String(data: data, encoding: .utf8) {
            self.relatedCardIdsJSON = json
        } else if let relatedStrings = try? container.decode([String].self, forKey: .relatedCardIdsJSON) {
            let uuids = relatedStrings.compactMap { UUID(uuidString: $0) }
            if let data = try? JSONEncoder().encode(uuids),
               let json = String(data: data, encoding: .utf8) {
                self.relatedCardIdsJSON = json
            }
        }

        // Fact-based card fields
        self.factsJSON = try container.decodeIfPresent(String.self, forKey: .factsJSON)
        self.suggestedBulletsJSON = try container.decodeIfPresent(String.self, forKey: .suggestedBulletsJSON)
        self.technologiesJSON = try container.decodeIfPresent(String.self, forKey: .technologiesJSON)
        self.outcomesJSON = try container.decodeIfPresent(String.self, forKey: .outcomesJSON)
        self.evidenceQuality = try container.decodeIfPresent(String.self, forKey: .evidenceQuality)
        self.verbatimExcerptsJSON = try container.decodeIfPresent(String.self, forKey: .verbatimExcerptsJSON)
        self.evidenceCardIdsJSON = try container.decodeIfPresent(String.self, forKey: .evidenceCardIdsJSON)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(narrative, forKey: .narrative)
        try container.encodeIfPresent(cardTypeRaw, forKey: .cardTypeRaw)
        try container.encodeIfPresent(dateRange, forKey: .dateRange)
        try container.encodeIfPresent(organization, forKey: .organization)
        try container.encodeIfPresent(location, forKey: .location)
        try container.encodeIfPresent(evidenceAnchorsJSON, forKey: .evidenceAnchorsJSON)
        try container.encodeIfPresent(extractableJSON, forKey: .extractableJSON)
        try container.encodeIfPresent(relatedCardIdsJSON, forKey: .relatedCardIdsJSON)
        try container.encode(enabledByDefault, forKey: .enabledByDefault)
        try container.encode(isFromOnboarding, forKey: .isFromOnboarding)
        try container.encodeIfPresent(tokenCount, forKey: .tokenCount)
        try container.encode(isPending, forKey: .isPending)
        try container.encodeIfPresent(factsJSON, forKey: .factsJSON)
        try container.encodeIfPresent(suggestedBulletsJSON, forKey: .suggestedBulletsJSON)
        try container.encodeIfPresent(technologiesJSON, forKey: .technologiesJSON)
        try container.encodeIfPresent(outcomesJSON, forKey: .outcomesJSON)
        try container.encodeIfPresent(evidenceQuality, forKey: .evidenceQuality)
        try container.encodeIfPresent(verbatimExcerptsJSON, forKey: .verbatimExcerptsJSON)
        try container.encodeIfPresent(evidenceCardIdsJSON, forKey: .evidenceCardIdsJSON)
    }

    // MARK: - Computed Properties

    /// Card type as enum
    var cardType: CardType? {
        get {
            guard let raw = cardTypeRaw else { return nil }
            return CardType(rawValue: raw)
        }
        set {
            cardTypeRaw = newValue?.rawValue
        }
    }

    /// Card type display info
    var cardTypeDisplay: (name: String, icon: String) {
        if let type = cardType {
            return (type.displayName, type.icon)
        }
        return (cardTypeRaw ?? "General", "doc.text.fill")
    }

    /// Evidence anchors linking narrative to source documents
    var evidenceAnchors: [EvidenceAnchor] {
        get {
            guard let json = evidenceAnchorsJSON,
                  let data = json.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([EvidenceAnchor].self, from: data) else {
                return []
            }
            return decoded
        }
        set {
            if newValue.isEmpty {
                evidenceAnchorsJSON = nil
            } else if let data = try? JSONEncoder().encode(newValue),
                      let json = String(data: data, encoding: .utf8) {
                evidenceAnchorsJSON = json
            }
        }
    }

    /// Extractable metadata for job matching
    var extractable: ExtractableMetadata {
        get {
            guard let json = extractableJSON,
                  let data = json.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode(ExtractableMetadata.self, from: data) else {
                return ExtractableMetadata()
            }
            return decoded
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let json = String(data: data, encoding: .utf8) {
                extractableJSON = json
            }
        }
    }

    /// Related card IDs
    var relatedCardIds: [UUID] {
        get {
            guard let json = relatedCardIdsJSON,
                  let data = json.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([UUID].self, from: data) else {
                return []
            }
            return decoded
        }
        set {
            if newValue.isEmpty {
                relatedCardIdsJSON = nil
            } else if let data = try? JSONEncoder().encode(newValue),
                      let json = String(data: data, encoding: .utf8) {
                relatedCardIdsJSON = json
            }
        }
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
    var facts: [KnowledgeCardFact] {
        get {
            guard let json = factsJSON,
                  let data = json.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([KnowledgeCardFact].self, from: data) else {
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
    var factsByCategory: [String: [KnowledgeCardFact]] {
        Dictionary(grouping: facts, by: { $0.category })
    }

    /// Decoded array of verbatim excerpts
    var verbatimExcerpts: [VerbatimExcerpt] {
        get {
            guard let json = verbatimExcerptsJSON,
                  let data = json.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([VerbatimExcerpt].self, from: data) else {
                return []
            }
            return decoded
        }
        set {
            if newValue.isEmpty {
                verbatimExcerptsJSON = nil
            } else if let data = try? JSONEncoder().encode(newValue),
                      let json = String(data: data, encoding: .utf8) {
                verbatimExcerptsJSON = json
            }
        }
    }

    /// Evidence card IDs (for skill cards)
    var evidenceCardIds: [UUID] {
        get {
            guard let json = evidenceCardIdsJSON,
                  let data = json.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([UUID].self, from: data) else {
                return []
            }
            return decoded
        }
        set {
            if newValue.isEmpty {
                evidenceCardIdsJSON = nil
            } else if let data = try? JSONEncoder().encode(newValue),
                      let json = String(data: data, encoding: .utf8) {
                evidenceCardIdsJSON = json
            }
        }
    }

    /// Whether this card uses the fact-based format
    var isFactBasedCard: Bool {
        factsJSON != nil || suggestedBulletsJSON != nil
    }
}

// MARK: - Supporting Types

/// Evidence anchor linking narrative to source documents
struct EvidenceAnchor: Codable, Equatable {
    let documentId: String
    let location: String           // "Pages 60-70", "Section 3.2"
    let verbatimExcerpt: String?   // Captured voice excerpt (20-50 words)

    enum CodingKeys: String, CodingKey {
        case documentId = "document_id"
        case location
        case verbatimExcerpt = "verbatim_excerpt"
    }
}

/// Extractable metadata for job matching
struct ExtractableMetadata: Codable, Equatable {
    let domains: [String]     // Fields of expertise
    let scale: [String]       // Quantified elements (numbers, metrics, scope)
    let keywords: [String]    // High-level terms for job matching

    init(domains: [String] = [], scale: [String] = [], keywords: [String] = []) {
        self.domains = domains
        self.scale = scale
        self.keywords = keywords
    }
}

/// Represents an extracted fact from a knowledge card
struct KnowledgeCardFact: Codable, Identifiable {
    var id: String { "\(category)-\(statement.prefix(50))" }

    let category: String
    let statement: String
    let confidence: String?
    let source: KnowledgeCardFactSource?

    enum CodingKeys: String, CodingKey {
        case category, statement, confidence, source
    }
}

/// Source attribution for a fact
struct KnowledgeCardFactSource: Codable {
    let artifactId: String?
    let location: String?
    let verbatimQuote: String?

    enum CodingKeys: String, CodingKey {
        case artifactId = "artifact_id"
        case location
        case verbatimQuote = "verbatim_quote"
    }
}

/// Verbatim excerpt preserving voice and context from source documents
struct VerbatimExcerpt: Codable {
    /// What this excerpt demonstrates
    let context: String
    /// Source document + location
    let location: String
    /// 100-500 word verbatim passage
    let text: String
    /// Why this matters (voice, technical depth, unique insight)
    let preservationReason: String

    enum CodingKeys: String, CodingKey {
        case context, location, text
        case preservationReason = "preservation_reason"
    }
}
