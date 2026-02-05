//
//  CoherenceReport.swift
//  Sprung
//
//  Types for the post-assembly coherence pass. A single LLM call scans
//  the assembled resume and flags issues like achievement repetition,
//  summary-highlights-skills misalignment, and narrative inconsistency.
//

import Foundation

// MARK: - Coherence Report

/// Result of the post-assembly coherence check.
/// Produced by a single LLM call after the user has reviewed all
/// proposed changes and they have been applied to the resume tree.
struct CoherenceReport: Codable, Sendable {
    /// Individual issues detected in the assembled resume.
    let issues: [CoherenceIssue]

    /// Overall assessment of resume coherence.
    let overallCoherence: CoherenceLevel

    /// Brief narrative summary of the coherence assessment.
    let summary: String
}

// MARK: - Coherence Issue

/// A single coherence issue detected in the assembled resume.
struct CoherenceIssue: Codable, Sendable, Identifiable {
    /// Stable identifier for this issue.
    let id: UUID

    /// Issue category: achievementRepetition, summaryHighlightsAlignment,
    /// skillsContentAlignment, emphasisConsistency, narrativeFlow, sectionRedundancy.
    let category: String

    /// Severity level: high, medium, or low.
    let severity: String

    /// Plain-language explanation of the problem.
    let description: String

    /// Resume locations involved (e.g., ["objective", "work.2.highlights[1]"]).
    let locations: [String]

    /// Recommended fix for this issue.
    let suggestion: String

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, category, severity, description, locations, suggestion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        self.category = try container.decode(String.self, forKey: .category)
        self.severity = try container.decode(String.self, forKey: .severity)
        self.description = try container.decode(String.self, forKey: .description)
        self.locations = try container.decode([String].self, forKey: .locations)
        self.suggestion = try container.decode(String.self, forKey: .suggestion)
    }

    init(
        id: UUID = UUID(),
        category: String,
        severity: String,
        description: String,
        locations: [String],
        suggestion: String
    ) {
        self.id = id
        self.category = category
        self.severity = severity
        self.description = description
        self.locations = locations
        self.suggestion = suggestion
    }
}

// MARK: - Coherence Level

/// Overall coherence assessment grade.
enum CoherenceLevel: String, Codable, Sendable {
    case good
    case fair
    case poor
}
