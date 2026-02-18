//
//  SkillsProcessingTypes.swift
//  Sprung
//
//  Shared value types and error enum for skills processing operations.
//  No logic — pure data contracts for deduplication and ATS expansion.
//

import Foundation

// MARK: - Processing Status

enum SkillsProcessingStatus: Equatable {
    case idle
    case processing(String)
    case completed(String)
    case failed(String)
}

// MARK: - Processing Result

struct SkillsProcessingResult {
    let operation: String
    let skillsProcessed: Int
    let skillsModified: Int
    let details: String
}

// MARK: - Deduplication Types

/// Represents a group of duplicate skills identified by LLM
struct DuplicateGroup: Codable {
    let canonicalName: String
    let skillIds: [String]
    let reasoning: String
}

/// Response from deduplication analysis
struct DeduplicationResponse: Codable {
    let duplicateGroups: [DuplicateGroup]
    /// Set to true if there are more duplicate groups that couldn't fit in this response
    let hasMore: Bool
    /// IDs of skills that have been processed (included in a duplicate group) in this response
    let processedSkillIds: [String]
}

// MARK: - ATS Expansion Types

/// ATS variants for a single skill
struct SkillATSVariants: Codable {
    let skillId: String
    let variants: [String]
}

/// Response from ATS expansion
struct ATSExpansionResponse: Codable {
    let skills: [SkillATSVariants]
}

/// Response from single-skill ATS variant generation
struct SingleSkillATSResponse: Codable {
    let variants: [String]
}

// MARK: - Errors

enum SkillsProcessingError: LocalizedError {
    case llmNotConfigured
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .llmNotConfigured:
            return "LLM service is not configured"
        case .invalidResponse:
            return "Invalid response from LLM"
        }
    }
}
