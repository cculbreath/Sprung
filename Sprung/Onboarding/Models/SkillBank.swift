//
//  SkillBank.swift
//  Sprung
//
//  Collection of skills extracted from documents with ATS matching capabilities.
//

import Foundation

/// A comprehensive collection of skills with matching and grouping capabilities
struct SkillBank: Codable {
    let skills: [Skill]
    let generatedAt: Date
    let sourceDocumentIds: [String]

    /// Group skills by category string
    func groupedByCategory() -> [String: [Skill]] {
        Dictionary(grouping: skills, by: { $0.category })
    }
}
