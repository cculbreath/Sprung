//
//  CardMetadata.swift
//  Sprung
//
//  Metadata extracted from document summaries for knowledge card generation.
//  Used by MetadataExtractionService to provide context to KC agents.
//

import Foundation

/// Metadata for a knowledge card, extracted from document summaries.
struct CardMetadata {
    /// Card type (job, skill, education, project)
    let cardType: String

    /// Title for the knowledge card
    let title: String

    /// Organization name (company, university, etc.)
    let organization: String?

    /// Time period (e.g., "2020-01 to 2023-06" or "2020-01 to Present")
    let timePeriod: String?

    /// Location (city, state, country, or "Remote")
    let location: String?

    /// Default metadata when extraction fails or for unknown document types
    static func defaults(fromFilename filename: String) -> CardMetadata {
        CardMetadata(
            cardType: "project",
            title: filename
                .replacingOccurrences(of: ".pdf", with: "")
                .replacingOccurrences(of: ".docx", with: "")
                .replacingOccurrences(of: ".txt", with: "")
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " "),
            organization: nil,
            timePeriod: nil,
            location: nil
        )
    }
}
