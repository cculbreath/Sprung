//
//  DocumentInventory.swift
//  Sprung
//
//  Per-document inventory of potential knowledge cards.
//

import Foundation

/// Fact categories for R&D and professional resumes
enum FactCategory: String, Codable, CaseIterable {
    // R&D-specific categories
    case hypothesisFormation = "hypothesis_formation"
    case experimentalDesign = "experimental_design"
    case methodologyInnovation = "methodology_innovation"
    case dataAnalysis = "data_analysis"
    case resultsInterpretation = "results_interpretation"
    case peerReview = "peer_review"
    case collaboration = "collaboration"

    // Professional categories
    case leadership = "leadership"
    case achievement = "achievement"
    case technical = "technical"
    case responsibility = "responsibility"
    case impact = "impact"
    case general = "general"

    /// Human-readable description
    var description: String {
        switch self {
        case .hypothesisFormation: return "Hypothesis Formation"
        case .experimentalDesign: return "Experimental Design"
        case .methodologyInnovation: return "Methodology Innovation"
        case .dataAnalysis: return "Data Analysis"
        case .resultsInterpretation: return "Results Interpretation"
        case .peerReview: return "Peer Review"
        case .collaboration: return "Collaboration"
        case .leadership: return "Leadership"
        case .achievement: return "Achievement"
        case .technical: return "Technical"
        case .responsibility: return "Responsibility"
        case .impact: return "Impact"
        case .general: return "General"
        }
    }
}

/// A fact with its category
struct CategorizedFact: Codable, Equatable {
    let category: FactCategory
    let statement: String

    enum CodingKeys: String, CodingKey {
        case category
        case statement
    }

    /// Fallback decoder that handles both structured and plain string facts
    init(from decoder: Decoder) throws {
        // Try decoding as object first
        if let container = try? decoder.container(keyedBy: CodingKeys.self) {
            // Handle category as string or enum
            if let categoryString = try? container.decode(String.self, forKey: .category) {
                self.category = FactCategory(rawValue: categoryString) ?? .general
            } else {
                self.category = try container.decodeIfPresent(FactCategory.self, forKey: .category) ?? .general
            }
            self.statement = try container.decode(String.self, forKey: .statement)
        } else if let plainString = try? decoder.singleValueContainer().decode(String.self) {
            // Fallback: treat plain string as general category
            self.category = .general
            self.statement = plainString
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected object or string")
            )
        }
    }

    init(category: FactCategory, statement: String) {
        self.category = category
        self.statement = statement
    }
}

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
        let keyFacts: [CategorizedFact]
        let technologies: [String]
        let quantifiedOutcomes: [String]
        let dateRange: String?
        let crossReferences: [String]
        let extractionNotes: String?

        /// Convenience accessor for fact statements only (backwards compatibility)
        var keyFactStatements: [String] {
            keyFacts.map { $0.statement }
        }

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
            keyFacts: [CategorizedFact],
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
        /// Handles both new structured facts and legacy plain string facts
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            cardType = try container.decode(CardType.self, forKey: .cardType)
            proposedTitle = try container.decode(String.self, forKey: .proposedTitle)
            evidenceStrength = try container.decode(EvidenceStrength.self, forKey: .evidenceStrength)
            evidenceLocations = try container.decodeIfPresent([String].self, forKey: .evidenceLocations) ?? []
            // Handle both structured facts and plain strings
            keyFacts = try container.decodeIfPresent([CategorizedFact].self, forKey: .keyFacts) ?? []
            technologies = try container.decodeIfPresent([String].self, forKey: .technologies) ?? []
            quantifiedOutcomes = try container.decodeIfPresent([String].self, forKey: .quantifiedOutcomes) ?? []
            dateRange = try container.decodeIfPresent(String.self, forKey: .dateRange)
            crossReferences = try container.decodeIfPresent([String].self, forKey: .crossReferences) ?? []
            extractionNotes = try container.decodeIfPresent(String.self, forKey: .extractionNotes)
        }
    }
}
