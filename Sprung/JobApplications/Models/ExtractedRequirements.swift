//
//  ExtractedRequirements.swift
//  Sprung
//
//  Pre-extracted and prioritized job requirements for resume customization.
//

import Foundation

/// Pre-extracted and prioritized job requirements
struct ExtractedRequirements: Codable {
    /// Requirements explicitly stated as required (deal-breakers)
    let mustHave: [String]

    /// Requirements mentioned multiple times or emphasized
    let strongSignal: [String]

    /// Nice-to-have requirements mentioned once
    let preferred: [String]

    /// Soft skills, team fit, work style expectations
    let cultural: [String]

    /// All technical terms for ATS keyword matching
    let atsKeywords: [String]

    /// When extraction was performed
    let extractedAt: Date

    /// Model used for extraction (for debugging)
    let extractionModel: String?

    /// Whether extraction succeeded
    var isValid: Bool {
        !mustHave.isEmpty || !strongSignal.isEmpty
    }

    /// All requirements flattened for search
    var allRequirements: [String] {
        mustHave + strongSignal + preferred + cultural
    }

    /// Empty/failed extraction
    static var empty: ExtractedRequirements {
        ExtractedRequirements(
            mustHave: [],
            strongSignal: [],
            preferred: [],
            cultural: [],
            atsKeywords: [],
            extractedAt: Date(),
            extractionModel: nil
        )
    }
}
