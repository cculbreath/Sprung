//
//  DocumentClassification.swift
//  Sprung
//
//  Classification result for a document to determine extraction strategy.
//

import Foundation

/// Classification result for a document
struct DocumentClassification: Codable {
    /// Primary document type
    let documentType: DocumentType

    /// More specific subtype (e.g., "WPAF" for personnel_file)
    let documentSubtype: String?

    /// Recommended extraction strategy
    let extractionStrategy: ExtractionStrategy

    /// Estimated number of cards by type
    let estimatedCardYield: CardYieldEstimate

    /// Structural hints for extraction
    let structureHints: StructureHints

    /// Special handling flags
    let specialHandling: [SpecialHandling]

    enum DocumentType: String, Codable {
        case resume
        case personnelFile = "personnel_file"
        case technicalReport = "technical_report"
        case coverLetter = "cover_letter"
        case referenceLetter = "reference_letter"
        case dissertation
        case grantProposal = "grant_proposal"
        case projectDocumentation = "project_documentation"
        case gitAnalysis = "git_analysis"
        case presentation
        case certificate
        case transcript
        case other
    }

    enum ExtractionStrategy: String, Codable {
        case singlePass = "single_pass"
        case sectioned
        case timelineAware = "timeline_aware"
        case codeAnalysis = "code_analysis"
    }

    struct CardYieldEstimate: Codable {
        let employment: Int
        let project: Int
        let skill: Int
        let achievement: Int
        let education: Int
    }

    struct StructureHints: Codable {
        let hasClearSections: Bool
        let hasTimelineData: Bool
        let hasQuantitativeData: Bool
        let hasFigures: Bool
        let primaryVoice: String  // "first_person", "third_person", "institutional"

        enum CodingKeys: String, CodingKey {
            case hasClearSections = "has_clear_sections"
            case hasTimelineData = "has_timeline_data"
            case hasQuantitativeData = "has_quantitative_data"
            case hasFigures = "has_figures"
            case primaryVoice = "primary_voice"
        }
    }

    enum SpecialHandling: String, Codable {
        case needsFigureExtraction = "needs_figure_extraction"
        case containsMultipleRoles = "contains_multiple_roles"
        case spansMultipleYears = "spans_multiple_years"
        case containsWritingSamples = "contains_writing_samples"
    }

    enum CodingKeys: String, CodingKey {
        case documentType = "document_type"
        case documentSubtype = "document_subtype"
        case extractionStrategy = "extraction_strategy"
        case estimatedCardYield = "estimated_card_yield"
        case structureHints = "structure_hints"
        case specialHandling = "special_handling"
    }

    /// Default classification when LLM is unavailable
    static func `default`(filename: String) -> DocumentClassification {
        DocumentClassification(
            documentType: .other,
            documentSubtype: nil,
            extractionStrategy: .singlePass,
            estimatedCardYield: CardYieldEstimate(
                employment: 0,
                project: 0,
                skill: 0,
                achievement: 0,
                education: 0
            ),
            structureHints: StructureHints(
                hasClearSections: false,
                hasTimelineData: false,
                hasQuantitativeData: false,
                hasFigures: false,
                primaryVoice: "unknown"
            ),
            specialHandling: []
        )
    }
}
