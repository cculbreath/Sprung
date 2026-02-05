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

    /// Find skills matching ATS terms from job listing
    func matchingSkills(for terms: [String]) -> [Skill] {
        let normalizedTerms = terms.map { $0.lowercased() }
        return skills.filter { skill in
            let allVariants = ([skill.canonical] + skill.atsVariants).map { $0.lowercased() }
            return normalizedTerms.contains { term in
                allVariants.contains { variant in
                    variant.contains(term) || term.contains(variant)
                }
            }
        }
    }

    /// Group skills by category string
    func groupedByCategory() -> [String: [Skill]] {
        Dictionary(grouping: skills, by: { $0.category })
    }

    /// Get top N skills per category (by proficiency, then evidence count)
    func topSkills(perCategory limit: Int) -> [String: [Skill]] {
        groupedByCategory().mapValues { categorySkills in
            categorySkills.sorted { a, b in
                if a.proficiency != b.proficiency {
                    return a.proficiency.sortOrder < b.proficiency.sortOrder
                }
                return a.evidence.count > b.evidence.count
            }.prefix(limit).map { $0 }
        }
    }
}
