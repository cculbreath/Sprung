//
//  GeneratedContent.swift
//  Sprung
//
//  Wrapper for LLM-generated content in the Seed Generation Module.
//

import Foundation
import SwiftyJSON

/// Wrapper for LLM-generated content
struct GeneratedContent: Equatable {
    /// The generated content type and value
    let type: ContentType
    /// Raw JSON response from LLM (for debugging/inspection)
    let rawJSON: JSON

    init(type: ContentType, rawJSON: JSON = JSON()) {
        self.type = type
        self.rawJSON = rawJSON
    }

    /// Types of generated content
    enum ContentType {
        // MARK: - Work Section
        /// Work highlights (3-4 bullet points for a specific job)
        case workHighlights(targetId: String, highlights: [String])
        /// Work summary description
        case workSummary(targetId: String, summary: String)

        // MARK: - Education Section
        /// Education description and courses
        case educationDescription(targetId: String, description: String, courses: [String])

        // MARK: - Volunteer Section
        /// Volunteer description and highlights
        case volunteerDescription(targetId: String, summary: String, highlights: [String])

        // MARK: - Projects Section
        /// Project description, highlights, and keywords
        case projectDescription(targetId: String, description: String, highlights: [String], keywords: [String])

        // MARK: - Skills Section
        /// Skill groupings (category name -> keywords)
        case skillGroups([SkillGroup])

        // MARK: - Awards Section
        /// Award summary
        case awardSummary(targetId: String, summary: String)

        // MARK: - Certificates Section
        /// Certificate (mostly facts, minimal LLM)
        case certificate(targetId: String)

        // MARK: - Publications Section
        /// Publication summary
        case publicationSummary(targetId: String, summary: String)

        // MARK: - Languages Section
        /// Language fluency descriptions
        case languages([LanguageEntry])

        // MARK: - Interests Section
        /// Interest descriptions
        case interests([InterestEntry])

        // MARK: - References Section
        /// Reference (mostly facts)
        case reference(targetId: String)

        // MARK: - Summary/Objective
        /// Objective statement (3-5 sentences)
        case objective(summary: String)

        // MARK: - Title Options
        /// Title options (uses TitleSet from InferenceGuidanceTypes)
        case titleSets([TitleSet])

        // MARK: - Custom Fields
        /// Custom field value
        case customField(key: String, values: [String])

        // MARK: - Fallback
        /// Raw JSON for complex/unstructured content
        case rawJSON(JSON)
    }

    static func == (lhs: GeneratedContent, rhs: GeneratedContent) -> Bool {
        lhs.type == rhs.type
    }
}

// MARK: - ContentType Equatable

extension GeneratedContent.ContentType: Equatable {
    static func == (lhs: GeneratedContent.ContentType, rhs: GeneratedContent.ContentType) -> Bool {
        switch (lhs, rhs) {
        case (.workHighlights(let idA, let hA), .workHighlights(let idB, let hB)):
            return idA == idB && hA == hB
        case (.workSummary(let idA, let sA), .workSummary(let idB, let sB)):
            return idA == idB && sA == sB
        case (.educationDescription(let idA, let dA, let cA), .educationDescription(let idB, let dB, let cB)):
            return idA == idB && dA == dB && cA == cB
        case (.volunteerDescription(let idA, let sA, let hA), .volunteerDescription(let idB, let sB, let hB)):
            return idA == idB && sA == sB && hA == hB
        case (.projectDescription(let idA, let dA, let hA, let kA), .projectDescription(let idB, let dB, let hB, let kB)):
            return idA == idB && dA == dB && hA == hB && kA == kB
        case (.skillGroups(let a), .skillGroups(let b)):
            return a == b
        case (.awardSummary(let idA, let sA), .awardSummary(let idB, let sB)):
            return idA == idB && sA == sB
        case (.certificate(let idA), .certificate(let idB)):
            return idA == idB
        case (.publicationSummary(let idA, let sA), .publicationSummary(let idB, let sB)):
            return idA == idB && sA == sB
        case (.languages(let a), .languages(let b)):
            return a == b
        case (.interests(let a), .interests(let b)):
            return a == b
        case (.reference(let idA), .reference(let idB)):
            return idA == idB
        case (.objective(let a), .objective(let b)):
            return a == b
        case (.titleSets(let a), .titleSets(let b)):
            return a == b
        case (.customField(let keyA, let valA), .customField(let keyB, let valB)):
            return keyA == keyB && valA == valB
        case (.rawJSON(let a), .rawJSON(let b)):
            return a.rawString() == b.rawString()
        default:
            return false
        }
    }
}

// MARK: - Supporting Types

/// A grouping of skills under a category
struct SkillGroup: Equatable, Codable {
    /// Category title (e.g., "Data Engineering")
    var name: String
    /// Individual skills in this group
    var keywords: [String]

    init(name: String, keywords: [String]) {
        self.name = name
        self.keywords = keywords
    }
}

/// Language entry with fluency
struct LanguageEntry: Equatable, Codable {
    var language: String
    var fluency: String
}

/// Interest entry with keywords
struct InterestEntry: Equatable, Codable {
    var name: String
    var keywords: [String]
}

// MARK: - Content Extraction Helpers

extension GeneratedContent {
    /// Extract the target ID from the content type if present
    var targetId: String? {
        switch type {
        case .workHighlights(let id, _),
             .workSummary(let id, _),
             .educationDescription(let id, _, _),
             .volunteerDescription(let id, _, _),
             .projectDescription(let id, _, _, _),
             .awardSummary(let id, _),
             .certificate(let id),
             .publicationSummary(let id, _),
             .reference(let id):
            return id
        default:
            return nil
        }
    }

    /// Extract highlights as string array (for work/volunteer/project)
    var highlights: [String] {
        switch type {
        case .workHighlights(_, let highlights):
            return highlights
        case .volunteerDescription(_, _, let highlights):
            return highlights
        case .projectDescription(_, _, let highlights, _):
            return highlights
        default:
            return []
        }
    }

    /// Extract summary/description text
    var summaryText: String? {
        switch type {
        case .workSummary(_, let text):
            return text
        case .educationDescription(_, let description, _):
            return description
        case .volunteerDescription(_, let summary, _):
            return summary
        case .projectDescription(_, let description, _, _):
            return description
        case .awardSummary(_, let text):
            return text
        case .publicationSummary(_, let text):
            return text
        case .objective(let text):
            return text
        default:
            return nil
        }
    }

    /// Get the section key this content belongs to
    var section: ExperienceSectionKey? {
        switch type {
        case .workHighlights, .workSummary:
            return .work
        case .educationDescription:
            return .education
        case .volunteerDescription:
            return .volunteer
        case .projectDescription:
            return .projects
        case .skillGroups:
            return .skills
        case .awardSummary:
            return .awards
        case .certificate:
            return .certificates
        case .publicationSummary:
            return .publications
        case .languages:
            return .languages
        case .interests:
            return .interests
        case .reference:
            return .references
        case .objective, .titleSets, .customField, .rawJSON:
            return nil
        }
    }
}
