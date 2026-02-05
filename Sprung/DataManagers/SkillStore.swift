//
//  SkillStore.swift
//  Sprung
//
//  Store for managing Skill persistence via SwiftData.
//

import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class SkillStore: SwiftDataStore {
    unowned let modelContext: ModelContext

    /// Change counter to trigger SwiftUI view updates when skills are mutated.
    /// @Observable only tracks stored properties, not computed SwiftData fetches.
    /// Views reading skills will observe this, ensuring re-render after mutations.
    private(set) var changeVersion: Int = 0

    // MARK: - Computed Collections

    /// All skills - SwiftData is the single source of truth
    var skills: [Skill] {
        _ = changeVersion  // Touch to establish observation dependency
        return (try? modelContext.fetch(FetchDescriptor<Skill>())) ?? []
    }

    /// Skills created during onboarding
    var onboardingSkills: [Skill] {
        skills.filter { $0.isFromOnboarding }
    }

    /// Skills pending user approval (created during onboarding but not yet approved)
    var pendingSkills: [Skill] {
        skills.filter { $0.isPending }
    }

    /// Skills that have been approved (not pending)
    var approvedSkills: [Skill] {
        skills.filter { !$0.isPending }
    }

    /// Skills grouped by category string
    var skillsByCategory: [String: [Skill]] {
        Dictionary(grouping: skills, by: { $0.category })
    }

    // MARK: - Initialization

    init(context: ModelContext) {
        modelContext = context
    }

    // MARK: - CRUD Operations

    /// Adds a new Skill to the store
    func add(_ skill: Skill) {
        modelContext.insert(skill)
        saveContext()
        changeVersion += 1
    }

    /// Adds multiple Skills to the store
    func addAll(_ skills: [Skill]) {
        for skill in skills {
            modelContext.insert(skill)
        }
        saveContext()
        changeVersion += 1
    }

    /// Persists updates (entity already mutated)
    func update(_ skill: Skill) {
        _ = saveContext()
        changeVersion += 1
    }

    /// Deletes a Skill from the store
    func delete(_ skill: Skill) {
        modelContext.delete(skill)
        saveContext()
        changeVersion += 1
    }

    /// Deletes multiple Skills from the store
    func deleteAll(_ skills: [Skill]) {
        for skill in skills {
            modelContext.delete(skill)
        }
        saveContext()
        changeVersion += 1
    }

    /// Deletes all Skills created during onboarding
    func deleteOnboardingSkills() {
        let skills = onboardingSkills
        for skill in skills {
            modelContext.delete(skill)
        }
        saveContext()
        changeVersion += 1
        Logger.info("🗑️ Deleted \(skills.count) onboarding Skills", category: .ai)
    }

    /// Deletes all pending skills
    func deletePendingSkills() {
        let skillsToDelete = pendingSkills
        for skill in skillsToDelete {
            modelContext.delete(skill)
        }
        saveContext()
        changeVersion += 1
        Logger.info("🗑️ Deleted \(skillsToDelete.count) pending Skills", category: .ai)
    }

    /// Approves pending skills by setting isPending = false
    /// - Parameter skillIds: Set of skill IDs to approve. If nil, approves all pending skills.
    func approveSkills(skillIds: Set<UUID>? = nil) {
        let skillsToApprove: [Skill]
        if let ids = skillIds {
            skillsToApprove = pendingSkills.filter { ids.contains($0.id) }
        } else {
            skillsToApprove = pendingSkills
        }

        for skill in skillsToApprove {
            skill.isPending = false
        }
        saveContext()
        changeVersion += 1
        Logger.info("✅ Approved \(skillsToApprove.count) Skills", category: .ai)
    }

    /// Deletes skills that have evidence from a specific artifact
    /// - Parameter artifactId: The artifact ID to match against evidence
    func deleteSkillsFromArtifact(_ artifactId: String) {
        let skillsToDelete = skills.filter { skill in
            skill.evidence.contains { $0.documentId == artifactId }
        }
        for skill in skillsToDelete {
            modelContext.delete(skill)
        }
        saveContext()
        changeVersion += 1
        Logger.info("🗑️ Deleted \(skillsToDelete.count) skills from artifact \(artifactId)", category: .ai)
    }

    // MARK: - Import/Export

    /// Imports Skills from a JSON file URL
    /// - Parameter url: File URL pointing to a JSON array of Skill objects
    /// - Returns: Number of skills imported
    @discardableResult
    func importFromJSON(url: URL) throws -> Int {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let importedSkills = try decoder.decode([Skill].self, from: data)

        // Check for existing IDs to avoid duplicates
        let existingIDs = Set(skills.map { $0.id })
        var importedCount = 0

        for skill in importedSkills {
            if existingIDs.contains(skill.id) {
                Logger.info("⏭️ Skipping duplicate Skill: \(skill.canonical)", category: .data)
                continue
            }
            modelContext.insert(skill)
            importedCount += 1
        }

        saveContext()
        changeVersion += 1
        Logger.info("📥 Imported \(importedCount) Skills from JSON", category: .data)
        return importedCount
    }

    /// Exports all skills to JSON data
    func exportToJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(skills)
    }

    // MARK: - Query Helpers

    /// Find a skill by ID
    func skill(withId id: UUID) -> Skill? {
        skills.first { $0.id == id }
    }

    /// Find skills by category string
    func skills(inCategory category: String) -> [Skill] {
        skills.filter { $0.category == category }
    }

    /// Find skills by proficiency level
    func skills(withProficiency proficiency: Proficiency) -> [Skill] {
        skills.filter { $0.proficiency == proficiency }
    }

    /// Find skills matching a search term (checks canonical name and variants)
    func skills(matching query: String) -> [Skill] {
        skills.filter { $0.matches(query) }
    }

    /// Find pending skills that have evidence from a specific artifact
    func pendingSkills(forArtifactId artifactId: String) -> [Skill] {
        pendingSkills.filter { skill in
            skill.evidence.contains { $0.documentId == artifactId }
        }
    }

    /// Find skills matching any of the given ATS terms
    func matchingSkills(for terms: [String]) -> [Skill] {
        let normalizedTerms = terms.map { $0.lowercased() }
        return skills.filter { skill in
            let allVariants = skill.allVariants.map { $0.lowercased() }
            return normalizedTerms.contains { term in
                allVariants.contains { variant in
                    variant.contains(term) || term.contains(variant)
                }
            }
        }
    }
}
