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
    /// Section this content belongs to
    let section: ExperienceSectionKey
    /// Target ID (timeline entry ID if entry-specific)
    let targetId: String?
    /// The generated content type and value
    let content: ContentType

    /// Types of generated content
    enum ContentType {
        /// Work highlights (3-4 bullet points)
        case workHighlights([String])
        /// Work summary description
        case workSummary(String)
        /// Education description and courses
        case education(description: String, courses: [String])
        /// Volunteer highlights
        case volunteerHighlights([String])
        /// Project description and highlights
        case project(description: String, highlights: [String], keywords: [String])
        /// Skill groupings (category name -> keywords)
        case skillGroups([SkillGroup])
        /// Award summary
        case awardSummary(String)
        /// Certificate (mostly facts, minimal LLM)
        case certificate
        /// Publication summary
        case publicationSummary(String)
        /// Language fluency descriptions
        case languages([LanguageEntry])
        /// Interest descriptions
        case interests([InterestEntry])
        /// Reference (mostly facts)
        case reference
        /// Objective statement (3-5 sentences)
        case objective(String)
        /// Title options (uses TitleSet from InferenceGuidanceTypes)
        case titleSets([TitleSet])
        /// Custom field value
        case customField(key: String, values: [String])
        /// Raw JSON for complex/unstructured content
        case rawJSON(JSON)
    }

    static func == (lhs: GeneratedContent, rhs: GeneratedContent) -> Bool {
        lhs.section == rhs.section &&
        lhs.targetId == rhs.targetId &&
        lhs.content == rhs.content
    }
}

// MARK: - ContentType Equatable

extension GeneratedContent.ContentType: Equatable {
    static func == (lhs: GeneratedContent.ContentType, rhs: GeneratedContent.ContentType) -> Bool {
        switch (lhs, rhs) {
        case (.workHighlights(let a), .workHighlights(let b)):
            return a == b
        case (.workSummary(let a), .workSummary(let b)):
            return a == b
        case (.education(let descA, let coursesA), .education(let descB, let coursesB)):
            return descA == descB && coursesA == coursesB
        case (.volunteerHighlights(let a), .volunteerHighlights(let b)):
            return a == b
        case (.project(let descA, let highA, let keyA), .project(let descB, let highB, let keyB)):
            return descA == descB && highA == highB && keyA == keyB
        case (.skillGroups(let a), .skillGroups(let b)):
            return a == b
        case (.awardSummary(let a), .awardSummary(let b)):
            return a == b
        case (.certificate, .certificate):
            return true
        case (.publicationSummary(let a), .publicationSummary(let b)):
            return a == b
        case (.languages(let a), .languages(let b)):
            return a == b
        case (.interests(let a), .interests(let b)):
            return a == b
        case (.reference, .reference):
            return true
        case (.objective(let a), .objective(let b)):
            return a == b
        case (.titleSets(let a), .titleSets(let b)):
            return a == b
        case (.customField(let keyA, let valA), .customField(let keyB, let valB)):
            return keyA == keyB && valA == valB
        case (.rawJSON(let a), .rawJSON(let b)):
            // Compare JSON by converting to string
            return a.rawString() == b.rawString()
        default:
            return false
        }
    }
}

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
    /// Extract highlights as string array (for work/volunteer/project)
    var highlights: [String] {
        switch content {
        case .workHighlights(let highlights):
            return highlights
        case .volunteerHighlights(let highlights):
            return highlights
        case .project(_, let highlights, _):
            return highlights
        default:
            return []
        }
    }

    /// Extract summary/description text
    var summaryText: String? {
        switch content {
        case .workSummary(let text):
            return text
        case .education(let description, _):
            return description
        case .project(let description, _, _):
            return description
        case .awardSummary(let text):
            return text
        case .publicationSummary(let text):
            return text
        case .objective(let text):
            return text
        default:
            return nil
        }
    }
}
