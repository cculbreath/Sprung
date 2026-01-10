//
//  CandidateDossier.swift
//  Sprung
//
//  SwiftData model for the candidate dossier - qualitative context about the job seeker
//  that complements structured facts (experience, education, skills).
//
//  Used by:
//  - Discovery module: job fit scoring, company research, networking guidance
//  - Cover letter generation: personalization and strategic positioning
//  - Interview prep: talking points and pitfall mitigation
//

import Foundation
import SwiftData

@Model
class CandidateDossier: Identifiable, Codable {
    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, createdAt, updatedAt
        case jobSearchContext, strengthsToEmphasize, pitfallsToAvoid
        case workArrangementPreferences, availability, uniqueCircumstances, interviewerNotes
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        jobSearchContext = try container.decode(String.self, forKey: .jobSearchContext)
        strengthsToEmphasize = try container.decodeIfPresent(String.self, forKey: .strengthsToEmphasize)
        pitfallsToAvoid = try container.decodeIfPresent(String.self, forKey: .pitfallsToAvoid)
        workArrangementPreferences = try container.decodeIfPresent(String.self, forKey: .workArrangementPreferences)
        availability = try container.decodeIfPresent(String.self, forKey: .availability)
        uniqueCircumstances = try container.decodeIfPresent(String.self, forKey: .uniqueCircumstances)
        interviewerNotes = try container.decodeIfPresent(String.self, forKey: .interviewerNotes)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(jobSearchContext, forKey: .jobSearchContext)
        try container.encodeIfPresent(strengthsToEmphasize, forKey: .strengthsToEmphasize)
        try container.encodeIfPresent(pitfallsToAvoid, forKey: .pitfallsToAvoid)
        try container.encodeIfPresent(workArrangementPreferences, forKey: .workArrangementPreferences)
        try container.encodeIfPresent(availability, forKey: .availability)
        try container.encodeIfPresent(uniqueCircumstances, forKey: .uniqueCircumstances)
        try container.encodeIfPresent(interviewerNotes, forKey: .interviewerNotes)
    }
    // MARK: - Identity

    var id: UUID
    var createdAt: Date
    var updatedAt: Date

    // MARK: - Core Context (Required)

    /// High-level summary of what the candidate is looking for, constraints, and positioning.
    /// Minimum 200 chars for useful content.
    var jobSearchContext: String

    // MARK: - Strategic Positioning (Substantial Narrative)

    /// Hidden or under-emphasized strengths not obvious from resume.
    /// 2-4 paragraphs with evidence and positioning guidance.
    /// Minimum 500 chars when provided.
    var strengthsToEmphasize: String?

    /// Potential concerns, vulnerabilities, or red flags with specific mitigation strategies.
    /// 2-4 paragraphs, each pitfall needs actionable mitigation.
    /// Minimum 500 chars when provided.
    var pitfallsToAvoid: String?

    // MARK: - Preferences and Constraints

    /// Work arrangement preferences (remote, hybrid, on-site) with flexibility notes.
    var workArrangementPreferences: String?

    /// Timeline, start date constraints, notice period, etc.
    var availability: String?

    /// Special circumstances that affect the job search (visa, relocation, health, family).
    /// Private - not for export without consent.
    var uniqueCircumstances: String?

    // MARK: - Private Notes

    /// Interviewer observations, impressions, strategic recommendations.
    /// Includes deal-breakers, cultural fit indicators, communication style notes.
    /// Private - not for export without consent.
    var interviewerNotes: String?

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        jobSearchContext: String = "",
        strengthsToEmphasize: String? = nil,
        pitfallsToAvoid: String? = nil,
        workArrangementPreferences: String? = nil,
        availability: String? = nil,
        uniqueCircumstances: String? = nil,
        interviewerNotes: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.jobSearchContext = jobSearchContext
        self.strengthsToEmphasize = strengthsToEmphasize
        self.pitfallsToAvoid = pitfallsToAvoid
        self.workArrangementPreferences = workArrangementPreferences
        self.availability = availability
        self.uniqueCircumstances = uniqueCircumstances
        self.interviewerNotes = interviewerNotes
    }

    // MARK: - Validation

    /// Minimum character counts for substantive fields
    enum FieldMinimums {
        static let jobSearchContext = 200
        static let strengthsToEmphasize = 500
        static let pitfallsToAvoid = 500
        static let interviewerNotes = 200
    }

    /// Whether the dossier has the minimum required content
    var isComplete: Bool {
        jobSearchContext.count >= FieldMinimums.jobSearchContext &&
        (strengthsToEmphasize?.count ?? 0) >= FieldMinimums.strengthsToEmphasize &&
        (pitfallsToAvoid?.count ?? 0) >= FieldMinimums.pitfallsToAvoid
    }

    /// Validation errors for incomplete fields
    var validationErrors: [String] {
        var errors: [String] = []

        if jobSearchContext.count < FieldMinimums.jobSearchContext {
            errors.append("Job search context needs at least \(FieldMinimums.jobSearchContext) characters (currently \(jobSearchContext.count))")
        }
        if let strengths = strengthsToEmphasize, !strengths.isEmpty, strengths.count < FieldMinimums.strengthsToEmphasize {
            errors.append("Strengths to emphasize needs at least \(FieldMinimums.strengthsToEmphasize) characters (currently \(strengths.count))")
        }
        if let pitfalls = pitfallsToAvoid, !pitfalls.isEmpty, pitfalls.count < FieldMinimums.pitfallsToAvoid {
            errors.append("Pitfalls to avoid needs at least \(FieldMinimums.pitfallsToAvoid) characters (currently \(pitfalls.count))")
        }

        return errors
    }

    /// Word count for display
    var wordCount: Int {
        let allText = [
            jobSearchContext,
            strengthsToEmphasize ?? "",
            pitfallsToAvoid ?? "",
            workArrangementPreferences ?? "",
            availability ?? "",
            uniqueCircumstances ?? "",
            interviewerNotes ?? ""
        ].joined(separator: " ")

        return allText.split(separator: " ").count
    }

    // MARK: - LLM Export Methods

    /// Export dossier content for cover letter generation (excludes private fields)
    func exportForCoverLetter() -> String {
        var parts: [String] = []

        parts.append("Job Search Context:\n\(jobSearchContext)")

        if let strengths = strengthsToEmphasize, !strengths.isEmpty {
            parts.append("Strengths to Emphasize:\n\(strengths)")
        }
        if let pitfalls = pitfallsToAvoid, !pitfalls.isEmpty {
            parts.append("Pitfalls to Avoid:\n\(pitfalls)")
        }
        if let prefs = workArrangementPreferences, !prefs.isEmpty {
            parts.append("Work Arrangement Preferences:\n\(prefs)")
        }
        if let avail = availability, !avail.isEmpty {
            parts.append("Availability:\n\(avail)")
        }

        // Note: uniqueCircumstances and interviewerNotes are NOT exported

        return parts.joined(separator: "\n\n")
    }

    /// Export for job matching/fit scoring (context + constraints only)
    func exportForJobMatching() -> String {
        var parts: [String] = []

        parts.append("<job_search_context>\n\(jobSearchContext)\n</job_search_context>")

        if let prefs = workArrangementPreferences, !prefs.isEmpty {
            parts.append("<work_preferences>\n\(prefs)\n</work_preferences>")
        }
        if let avail = availability, !avail.isEmpty {
            parts.append("<availability>\n\(avail)\n</availability>")
        }

        return parts.joined(separator: "\n\n")
    }

    /// Export for resume customization (includes strategic positioning guidance)
    func exportForResumeCustomization() -> String {
        var parts: [String] = []

        parts.append("<candidate_context>\n\(jobSearchContext)\n</candidate_context>")

        if let strengths = strengthsToEmphasize, !strengths.isEmpty {
            parts.append("<strengths_to_emphasize>\n\(strengths)\n</strengths_to_emphasize>")
        }
        if let pitfalls = pitfallsToAvoid, !pitfalls.isEmpty {
            parts.append("<pitfalls_to_avoid>\n\(pitfalls)\n</pitfalls_to_avoid>")
        }

        return parts.joined(separator: "\n\n")
    }

    /// Export for discovery module (networking, job sources, coaching)
    func exportForDiscovery() -> String {
        var parts: [String] = []

        parts.append("<candidate_profile>")
        parts.append("Job Search Context:\n\(jobSearchContext)")

        if let strengths = strengthsToEmphasize, !strengths.isEmpty {
            parts.append("\nStrengths:\n\(strengths)")
        }
        if let prefs = workArrangementPreferences, !prefs.isEmpty {
            parts.append("\nWork Preferences:\n\(prefs)")
        }
        if let avail = availability, !avail.isEmpty {
            parts.append("\nAvailability:\n\(avail)")
        }
        parts.append("</candidate_profile>")

        return parts.joined(separator: "")
    }

    /// Compact context for system prompts (abbreviated version)
    var promptContextCompact: String {
        let lines = jobSearchContext.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .prefix(5)
            .joined(separator: " ")

        var result = "Candidate: \(lines)"

        if let prefs = workArrangementPreferences, !prefs.isEmpty {
            result += " | Work: \(prefs.prefix(100))"
        }

        return result
    }

    /// Export full dossier including private fields (for backup/restore)
    func exportFull() -> String {
        var parts: [String] = []

        parts.append("Job Search Context:\n\(jobSearchContext)")

        if let strengths = strengthsToEmphasize, !strengths.isEmpty {
            parts.append("Strengths to Emphasize:\n\(strengths)")
        }
        if let pitfalls = pitfallsToAvoid, !pitfalls.isEmpty {
            parts.append("Pitfalls to Avoid:\n\(pitfalls)")
        }
        if let prefs = workArrangementPreferences, !prefs.isEmpty {
            parts.append("Work Arrangement Preferences:\n\(prefs)")
        }
        if let avail = availability, !avail.isEmpty {
            parts.append("Availability:\n\(avail)")
        }
        if let circumstances = uniqueCircumstances, !circumstances.isEmpty {
            parts.append("Unique Circumstances:\n\(circumstances)")
        }
        if let notes = interviewerNotes, !notes.isEmpty {
            parts.append("Interviewer Notes:\n\(notes)")
        }

        return parts.joined(separator: "\n\n")
    }
}
