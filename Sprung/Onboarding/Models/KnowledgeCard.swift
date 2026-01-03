//
//  KnowledgeCard.swift
//  Sprung
//
//  Narrative-focused knowledge card model for capturing career stories.
//  Skills are extracted separately into the SkillBank.
//

import Foundation

/// Type of knowledge card
enum CardType: String, Codable, CaseIterable {
    case employment  // Role at an organization
    case project     // Specific initiative or deliverable
    case achievement // Award, publication, recognition
    case education   // Degree or credential
}

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
    let domains: [String]     // Fields of expertise (not individual skills)
    let scale: [String]       // Quantified elements (numbers, metrics, scope)
    let keywords: [String]    // High-level terms for job matching

    init(domains: [String] = [], scale: [String] = [], keywords: [String] = []) {
        self.domains = domains
        self.scale = scale
        self.keywords = keywords
    }
}

/// A narrative knowledge card capturing the full story behind a career element
struct KnowledgeCard: Codable, Identifiable, Equatable {
    let id: UUID
    let cardType: CardType
    let title: String
    let narrative: String           // 500-2000 word story with WHY/JOURNEY/LESSONS
    let evidenceAnchors: [EvidenceAnchor]
    let extractable: ExtractableMetadata
    let dateRange: String?
    let organization: String?
    let relatedCardIds: [UUID]

    enum CodingKeys: String, CodingKey {
        case id
        case cardType = "card_type"
        case title
        case narrative
        case evidenceAnchors = "evidence_anchors"
        case extractable
        case dateRange = "date_range"
        case organization
        case relatedCardIds = "related_card_ids"
    }

    /// Custom decoder to handle LLM responses
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Handle id as UUID or String
        if let uuidString = try? container.decode(String.self, forKey: .id) {
            self.id = UUID(uuidString: uuidString) ?? UUID()
        } else {
            self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        }

        self.cardType = try container.decode(CardType.self, forKey: .cardType)
        self.title = try container.decode(String.self, forKey: .title)
        self.narrative = try container.decode(String.self, forKey: .narrative)
        self.evidenceAnchors = try container.decodeIfPresent([EvidenceAnchor].self, forKey: .evidenceAnchors) ?? []
        self.extractable = try container.decodeIfPresent(ExtractableMetadata.self, forKey: .extractable) ?? ExtractableMetadata()
        self.dateRange = try container.decodeIfPresent(String.self, forKey: .dateRange)
        self.organization = try container.decodeIfPresent(String.self, forKey: .organization)

        // Handle relatedCardIds as array of UUIDs or strings
        if let uuidStrings = try? container.decode([String].self, forKey: .relatedCardIds) {
            self.relatedCardIds = uuidStrings.compactMap { UUID(uuidString: $0) }
        } else {
            self.relatedCardIds = try container.decodeIfPresent([UUID].self, forKey: .relatedCardIds) ?? []
        }
    }

    /// Memberwise initializer
    init(
        id: UUID = UUID(),
        cardType: CardType,
        title: String,
        narrative: String,
        evidenceAnchors: [EvidenceAnchor] = [],
        extractable: ExtractableMetadata = ExtractableMetadata(),
        dateRange: String? = nil,
        organization: String? = nil,
        relatedCardIds: [UUID] = []
    ) {
        self.id = id
        self.cardType = cardType
        self.title = title
        self.narrative = narrative
        self.evidenceAnchors = evidenceAnchors
        self.extractable = extractable
        self.dateRange = dateRange
        self.organization = organization
        self.relatedCardIds = relatedCardIds
    }
}

/// Response wrapper for LLM extraction
struct KnowledgeCardExtractionResponse: Codable {
    let documentType: String
    let cards: [KnowledgeCard]

    enum CodingKeys: String, CodingKey {
        case documentType = "document_type"
        case cards
    }
}
