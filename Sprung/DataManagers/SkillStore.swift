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
final class SkillStore: EntityStore {
    typealias Entity = Skill
    unowned let modelContext: ModelContext

    /// @Observable refresh counter (see EntityStore). Touched by `fetchAll()` and
    /// bumped by every mutation so views reading the fetched collections re-render.
    var changeVersion: Int = 0

    // MARK: - Computed Collections

    /// All skills - SwiftData is the single source of truth
    var skills: [Skill] { fetchAll() }

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
    // add / addAll / update / delete / deleteAll are provided by EntityStore.

    /// Deletes all Skills created during onboarding
    func deleteOnboardingSkills() {
        let skills = onboardingSkills
        deleteAll(skills)
        Logger.info("🗑️ Deleted \(skills.count) onboarding Skills", category: .ai)
    }

    /// Deletes all pending skills
    func deletePendingSkills() {
        let skillsToDelete = pendingSkills
        deleteAll(skillsToDelete)
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
        persistChanges()
        Logger.info("✅ Approved \(skillsToApprove.count) Skills", category: .ai)
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

}
