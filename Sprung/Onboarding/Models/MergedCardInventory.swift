//
//  MergedCardInventory.swift
//  Sprung
//
//  Cross-document merged card inventory.
//

import Foundation

/// Cross-document merged card inventory
struct MergedCardInventory: Codable {
    let mergedCards: [MergedCard]
    let gaps: [DocumentationGap]
    let stats: MergeStats
    let generatedAt: Date

    enum CodingKeys: String, CodingKey {
        case mergedCards = "merged_cards"
        case gaps
        case stats
        case generatedAt = "generated_at"
    }

    struct MergedCard: Codable {
        let cardId: String
        let cardType: String
        let title: String

        /// Primary source for this card
        let primarySource: SourceReference

        /// Additional sources
        let supportingSources: [SupportingSource]

        /// All facts from all sources (deduplicated)
        let combinedKeyFacts: [String]
        let combinedTechnologies: [String]
        let combinedOutcomes: [String]

        let dateRange: String?
        let evidenceQuality: EvidenceQuality
        let extractionPriority: ExtractionPriority

        enum CodingKeys: String, CodingKey {
            case cardId = "card_id"
            case cardType = "card_type"
            case title
            case primarySource = "primary_source"
            case supportingSources = "supporting_sources"
            case combinedKeyFacts = "combined_key_facts"
            case combinedTechnologies = "combined_technologies"
            case combinedOutcomes = "combined_outcomes"
            case dateRange = "date_range"
            case evidenceQuality = "evidence_quality"
            case extractionPriority = "extraction_priority"
        }

        struct SourceReference: Codable {
            let documentId: String
            let evidenceLocations: [String]

            enum CodingKeys: String, CodingKey {
                case documentId = "document_id"
                case evidenceLocations = "evidence_locations"
            }
        }

        struct SupportingSource: Codable {
            let documentId: String
            let evidenceLocations: [String]
            let adds: [String]  // What this source uniquely contributes

            enum CodingKeys: String, CodingKey {
                case documentId = "document_id"
                case evidenceLocations = "evidence_locations"
                case adds
            }
        }

        enum EvidenceQuality: String, Codable {
            case strong
            case moderate
            case weak
        }

        enum ExtractionPriority: String, Codable {
            case high
            case medium
            case low
        }
    }

    struct DocumentationGap: Codable {
        let cardTitle: String
        let gapType: GapType
        let currentEvidence: String
        let recommendedDocs: [String]

        enum GapType: String, Codable {
            case missingPrimarySource = "missing_primary_source"
            case insufficientDetail = "insufficient_detail"
            case noQuantifiedOutcomes = "no_quantified_outcomes"
        }

        enum CodingKeys: String, CodingKey {
            case cardTitle = "card_title"
            case gapType = "gap_type"
            case currentEvidence = "current_evidence"
            case recommendedDocs = "recommended_docs"
        }
    }

    struct MergeStats: Codable {
        let totalInputCards: Int
        let mergedOutputCards: Int
        let cardsByType: [String: Int]
        let strongEvidence: Int
        let needsMoreEvidence: Int

        enum CodingKeys: String, CodingKey {
            case totalInputCards = "total_input_cards"
            case mergedOutputCards = "merged_output_cards"
            case cardsByType = "cards_by_type"
            case strongEvidence = "strong_evidence"
            case needsMoreEvidence = "needs_more_evidence"
        }
    }
}
