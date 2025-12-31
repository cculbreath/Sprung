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

    /// Memberwise initializer for constructing from decoded LLM response
    init(documentId: String, documentType: String, proposedCards: [ProposedCardEntry], generatedAt: Date) {
        self.documentId = documentId
        self.documentType = documentType
        self.proposedCards = proposedCards
        self.generatedAt = generatedAt
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

        /// Memberwise initializer (needed since we have a custom decoder)
        init(
            cardType: CardType,
            proposedTitle: String,
            evidenceStrength: EvidenceStrength,
            evidenceLocations: [String],
            keyFacts: [String],
            technologies: [String],
            quantifiedOutcomes: [String],
            dateRange: String?,
            crossReferences: [String],
            extractionNotes: String?
        ) {
            self.cardType = cardType
            self.proposedTitle = proposedTitle
            self.evidenceStrength = evidenceStrength
            self.evidenceLocations = evidenceLocations
            self.keyFacts = keyFacts
            self.technologies = technologies
            self.quantifiedOutcomes = quantifiedOutcomes
            self.dateRange = dateRange
            self.crossReferences = crossReferences
            self.extractionNotes = extractionNotes
        }

        /// Custom decoder that provides defaults for optional arrays
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            cardType = try container.decode(CardType.self, forKey: .cardType)
            proposedTitle = try container.decode(String.self, forKey: .proposedTitle)
            evidenceStrength = try container.decode(EvidenceStrength.self, forKey: .evidenceStrength)
            evidenceLocations = try container.decodeIfPresent([String].self, forKey: .evidenceLocations) ?? []
            keyFacts = try container.decodeIfPresent([String].self, forKey: .keyFacts) ?? []
            technologies = try container.decodeIfPresent([String].self, forKey: .technologies) ?? []
            quantifiedOutcomes = try container.decodeIfPresent([String].self, forKey: .quantifiedOutcomes) ?? []
            dateRange = try container.decodeIfPresent(String.self, forKey: .dateRange)
            crossReferences = try container.decodeIfPresent([String].self, forKey: .crossReferences) ?? []
            extractionNotes = try container.decodeIfPresent(String.self, forKey: .extractionNotes)
        }
    }
}
