import SwiftUI

// MARK: - CRUD / Edit / Rename Helpers
//
// State-mutating helpers invoked by the child views (SkillBankCategorySection,
// SkillBankRowView, SkillBankNewCategoryRow) via callbacks. These own the shared
// browser state (inline-add, category rename, expansion) and persist through the store.

extension SkillsBankBrowser {

    // MARK: - Inline Add Skill

    func startAddingSkill(to category: String) {
        addingToCategory = category
        newSkillName = ""
        // Ensure category is expanded
        expandedCategories.insert(category)
    }

    func cancelAddingSkill() {
        addingToCategory = nil
        newSkillName = ""
        isAddingSkill = false
    }

    func commitNewSkill() {
        guard let skillStore = skillStore,
              let category = addingToCategory else { return }
        let trimmedName = newSkillName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        isAddingSkill = true

        Task {
            // Create the skill first
            let newSkill = Skill(
                canonical: trimmedName,
                category: category
            )
            skillStore.add(newSkill)

            // Generate ATS variants if we have the facade
            if let facade = llmFacade {
                do {
                    let service = SkillsProcessingService(skillStore: skillStore, facade: facade)
                    let variants = try await service.generateATSVariantsForSkill(newSkill)
                    newSkill.atsVariants = variants
                    skillStore.update(newSkill)
                } catch {
                    Logger.warning("Failed to generate ATS variants for new skill: \(error.localizedDescription)", category: .ai)
                    // Skill was still added, just without ATS variants
                }
            }

            await MainActor.run {
                cancelAddingSkill()
            }
        }
    }

    // MARK: - New Category Creation

    func commitNewCategory() {
        let trimmed = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isCreatingCategory = false
        newCategoryName = ""
        expandedCategories.insert(trimmed)
        startAddingSkill(to: trimmed)
    }

    // MARK: - Skill Editing

    /// Persist an inline-edited skill. `newCategory` has already been resolved
    /// (custom categories collapsed to their entered name) by the row view.
    func commitSkillEdit(_ skill: Skill, newName: String, newCategory: String) {
        var didChange = false
        if !newName.isEmpty && newName != skill.canonical {
            skill.canonical = newName
            didChange = true
        }
        if !newCategory.isEmpty && newCategory != skill.category {
            skill.category = newCategory
            expandedCategories.insert(newCategory)
            didChange = true
        }
        if didChange {
            skillStore?.update(skill)
        }
    }

    func deleteSkill(_ skill: Skill) {
        skillStore?.delete(skill)
    }

    // MARK: - Expansion

    func toggleCategory(_ category: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if expandedCategories.contains(category) {
                expandedCategories.remove(category)
            } else {
                expandedCategories.insert(category)
            }
        }
    }

    func toggleSkillExpansion(_ skill: Skill) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if expandedSkills.contains(skill.id) {
                expandedSkills.remove(skill.id)
            } else {
                expandedSkills.insert(skill.id)
            }
        }
    }

    // MARK: - Category Rename

    func commitCategoryRename(from oldCategory: String) {
        let trimmed = renamingCategoryText.trimmingCharacters(in: .whitespacesAndNewlines)
        Logger.debug("[SkillsBankBrowser] commitCategoryRename called: '\(oldCategory)' -> '\(trimmed)'", category: .ui)
        guard !trimmed.isEmpty, trimmed != oldCategory, let store = skillStore else {
            Logger.debug("[SkillsBankBrowser] commitCategoryRename: guard failed (empty=\(trimmed.isEmpty), same=\(trimmed == oldCategory), store=\(skillStore != nil))", category: .ui)
            renamingCategory = nil
            return
        }

        let skillsToUpdate = store.skills.filter { $0.category == oldCategory }
        Logger.debug("[SkillsBankBrowser] Renaming \(skillsToUpdate.count) skills from '\(oldCategory)' to '\(trimmed)'", category: .ui)
        guard let first = skillsToUpdate.first else {
            Logger.debug("[SkillsBankBrowser] No skills found for category '\(oldCategory)'", category: .ui)
            renamingCategory = nil
            return
        }
        for skill in skillsToUpdate {
            skill.category = trimmed
        }
        store.update(first) // saveContext persists all mutations, changeVersion triggers UI refresh

        // Update expanded state to track the new name
        if expandedCategories.remove(oldCategory) != nil {
            expandedCategories.insert(trimmed)
        }

        renamingCategory = nil
    }
}
