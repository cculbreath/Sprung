//
//  ExtractedRequirements.swift
//  Sprung
//
//  Pre-extracted and prioritized job requirements for resume customization.
//

import Foundation

// MARK: - Text Evidence Types

/// Represents a range of text in a job description where a skill was found
struct TextSpan: Codable, Equatable {
    /// Start character index (0-based, relative to jobDescription)
    let start: Int

    /// End character index (exclusive)
    let end: Int

    /// The exact text at this span (for display without re-parsing)
    let text: String
}

/// Category for job skills relative to user's skill bank
enum JobSkillCategory: String, Codable {
    case matched      // User explicitly has this skill
    case recommended  // User likely has based on adjacent skills
    case unmatched    // Skill gap - user doesn't appear to have it
}

/// A skill extracted from a job description with text evidence
struct JobSkillEvidence: Codable, Equatable, Identifiable {
    var id: String { skillName }

    /// The skill name as extracted (normalized form)
    let skillName: String

    /// Category based on user's skill bank
    let category: JobSkillCategory

    /// All text spans where this skill was mentioned in the job description
    let evidenceSpans: [TextSpan]

    /// UUID of matched user skill (if category is .matched)
    let matchedSkillId: String?
}

// MARK: - Skill Recommendation

/// Skill suggested based on user's existing expertise matching job requirements
struct SkillRecommendation: Codable, Equatable {
    /// The job requirement skill they likely have (e.g., "Flame Cutting")
    let skillName: String

    /// SkillCategory raw value
    let category: String

    /// Confidence level: "high", "medium", "low"
    let confidence: String

    /// Why inferred (adjacency explanation)
    let reason: String

    /// User's existing skills that suggest this capability
    let relatedUserSkills: [String]

    /// KnowledgeCard UUIDs evidencing this capability
    let sourceCardIds: [String]
}

// MARK: - Extracted Requirements

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

    /// UUIDs of existing user skills that match job requirements
    let matchedSkillIds: [String]

    /// Skills suggested based on user's existing expertise that match job requirements
    let skillRecommendations: [SkillRecommendation]

    /// All skills found in job description with text evidence for highlighting
    let skillEvidence: [JobSkillEvidence]

    /// Whether extraction succeeded
    var isValid: Bool {
        !mustHave.isEmpty || !strongSignal.isEmpty
    }

    // MARK: - Migration-Safe Decoding

    enum CodingKeys: String, CodingKey {
        case mustHave, strongSignal, preferred, cultural, atsKeywords
        case extractedAt, extractionModel
        case matchedSkillIds, skillRecommendations, skillEvidence
    }

    init(
        mustHave: [String],
        strongSignal: [String],
        preferred: [String],
        cultural: [String],
        atsKeywords: [String],
        extractedAt: Date,
        extractionModel: String?,
        matchedSkillIds: [String] = [],
        skillRecommendations: [SkillRecommendation] = [],
        skillEvidence: [JobSkillEvidence] = []
    ) {
        self.mustHave = mustHave
        self.strongSignal = strongSignal
        self.preferred = preferred
        self.cultural = cultural
        self.atsKeywords = atsKeywords
        self.extractedAt = extractedAt
        self.extractionModel = extractionModel
        self.matchedSkillIds = matchedSkillIds
        self.skillRecommendations = skillRecommendations
        self.skillEvidence = skillEvidence
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mustHave = try container.decode([String].self, forKey: .mustHave)
        strongSignal = try container.decode([String].self, forKey: .strongSignal)
        preferred = try container.decode([String].self, forKey: .preferred)
        cultural = try container.decode([String].self, forKey: .cultural)
        atsKeywords = try container.decode([String].self, forKey: .atsKeywords)
        extractedAt = try container.decode(Date.self, forKey: .extractedAt)
        extractionModel = try container.decodeIfPresent(String.self, forKey: .extractionModel)
        // Migration-safe: default to empty arrays if fields don't exist (pre-upgrade data)
        matchedSkillIds = try container.decodeIfPresent([String].self, forKey: .matchedSkillIds) ?? []
        skillRecommendations = try container.decodeIfPresent([SkillRecommendation].self, forKey: .skillRecommendations) ?? []
        skillEvidence = try container.decodeIfPresent([JobSkillEvidence].self, forKey: .skillEvidence) ?? []
    }
}
