//
//  StructuredKnowledgeCard.swift
//  Sprung
//
//  Knowledge card with structured evidence blocks (not verbose prose).
//

import Foundation

/// Knowledge card with structured evidence blocks (not verbose prose)
struct StructuredKnowledgeCard: Codable {
    // Identity
    let cardId: String
    let cardType: String  // "employment", "project", "skill", "achievement", "education"
    let title: String

    // Time & Place
    let dateRange: String?
    let organization: String?
    let location: String?

    // Evidence Blocks (the core innovation)
    let evidenceBlocks: [EvidenceBlock]

    // Extracted Facts (structured for retrieval)
    let facts: ExtractedFacts

    // Pre-generated Resume Content
    let resumeBullets: [String]

    // Cross-references
    let relatedCards: [String]
    let keywords: [String]

    // Metadata
    let evidenceQuality: String  // "strong", "moderate", "weak"
    let lastUpdated: Date

    enum CodingKeys: String, CodingKey {
        case cardId = "card_id"
        case cardType = "card_type"
        case title
        case dateRange = "date_range"
        case organization
        case location
        case evidenceBlocks = "evidence_blocks"
        case facts
        case resumeBullets = "resume_bullets"
        case relatedCards = "related_cards"
        case keywords
        case evidenceQuality = "evidence_quality"
        case lastUpdated = "last_updated"
    }

    struct EvidenceBlock: Codable {
        let sourceDocument: String
        let sourceType: String  // "primary", "supporting"
        let locations: [String]
        let extractedContent: ExtractedContent

        enum CodingKeys: String, CodingKey {
            case sourceDocument = "source_document"
            case sourceType = "source_type"
            case locations
            case extractedContent = "extracted_content"
        }

        struct ExtractedContent: Codable {
            let verbatimQuotes: [String]?
            let facts: [String]
            let figures: [FigureReference]?

            enum CodingKeys: String, CodingKey {
                case verbatimQuotes = "verbatim_quotes"
                case facts
                case figures
            }
        }

        struct FigureReference: Codable {
            let figureId: String
            let description: String
            let demonstrates: String

            enum CodingKeys: String, CodingKey {
                case figureId = "figure_id"
                case description
                case demonstrates
            }
        }
    }

    struct ExtractedFacts: Codable {
        let scope: String?
        let responsibilities: [String]?
        let technologies: [String]?
        let outcomes: [String]?
        let quantified: [String]?
        let context: String?
    }
}
