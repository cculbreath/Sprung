//
//  DocumentInventory.swift
//  Sprung
//
//  Per-document inventory of potential knowledge cards.
//

import Foundation

/// Per-document inventory of potential knowledge cards
struct DocumentInventory: Codable {
    let documentId: String
    let documentType: String
    let proposedCards: [ProposedCardEntry]
    let generatedAt: Date

    enum CodingKeys: String, CodingKey {
        case documentId = "document_id"
        case documentType = "document_type"
        case proposedCards = "cards"
        case generatedAt = "generated_at"
    }

    /// A single proposed card from this document
    struct ProposedCardEntry: Codable {
        let cardType: CardType
        let proposedTitle: String
        let evidenceStrength: EvidenceStrength
        let evidenceLocations: [String]
        let keyFacts: [String]
        let technologies: [String]
        let quantifiedOutcomes: [String]
        let dateRange: String?
        let crossReferences: [String]
        let extractionNotes: String?

        enum CardType: String, Codable {
            case employment
            case project
            case skill
            case achievement
            case education
        }

        enum EvidenceStrength: String, Codable {
            case primary    // This doc is THE main source
            case supporting // Adds detail but not primary
            case mention    // Brief reference only
        }

        enum CodingKeys: String, CodingKey {
            case cardType = "card_type"
            case proposedTitle = "proposed_title"
            case evidenceStrength = "evidence_strength"
            case evidenceLocations = "evidence_locations"
            case keyFacts = "key_facts"
            case technologies
            case quantifiedOutcomes = "quantified_outcomes"
            case dateRange = "date_range"
            case crossReferences = "cross_references"
            case extractionNotes = "extraction_notes"
        }
    }
}
