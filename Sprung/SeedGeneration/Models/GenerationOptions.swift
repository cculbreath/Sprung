//
//  GenerationOptions.swift
//  Sprung
//
//  User-tunable constraints for seed generation, chosen before
//  generation starts and adjustable from the rejection-feedback form.
//

import Foundation

/// User-selected constraints applied to generated content.
struct GenerationOptions: Equatable {
    /// Maximum number of highlight bullets per entry (work, project, volunteer)
    var maxHighlightsPerEntry: Int
    /// Target rendered lines per highlight bullet — sent to the LLM as a
    /// guideline, not a hard limit
    var targetBulletLines: Int
    /// Number of skill categories to generate
    var skillCategoryCount: Int
    /// Maximum skills listed per category
    var maxSkillsPerCategory: Int

    init(
        maxHighlightsPerEntry: Int = 4,
        targetBulletLines: Int = 2,
        skillCategoryCount: Int = 5,
        maxSkillsPerCategory: Int = 8
    ) {
        self.maxHighlightsPerEntry = maxHighlightsPerEntry
        self.targetBulletLines = targetBulletLines
        self.skillCategoryCount = skillCategoryCount
        self.maxSkillsPerCategory = maxSkillsPerCategory
    }

    // MARK: - UserDefaults Persistence

    enum Keys {
        static let maxHighlightsPerEntry = "seedGenMaxHighlightsPerEntry"
        static let targetBulletLines = "seedGenTargetBulletLines"
        static let skillCategoryCount = "seedGenSkillCategoryCount"
        static let maxSkillsPerCategory = "seedGenMaxSkillsPerCategory"
    }

    /// Load persisted options, falling back to defaults for unset keys.
    static func load() -> GenerationOptions {
        let defaults = UserDefaults.standard
        var options = GenerationOptions()
        if defaults.integer(forKey: Keys.maxHighlightsPerEntry) > 0 {
            options.maxHighlightsPerEntry = defaults.integer(forKey: Keys.maxHighlightsPerEntry)
        }
        if defaults.integer(forKey: Keys.targetBulletLines) > 0 {
            options.targetBulletLines = defaults.integer(forKey: Keys.targetBulletLines)
        }
        if defaults.integer(forKey: Keys.skillCategoryCount) > 0 {
            options.skillCategoryCount = defaults.integer(forKey: Keys.skillCategoryCount)
        }
        if defaults.integer(forKey: Keys.maxSkillsPerCategory) > 0 {
            options.maxSkillsPerCategory = defaults.integer(forKey: Keys.maxSkillsPerCategory)
        }
        return options
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(maxHighlightsPerEntry, forKey: Keys.maxHighlightsPerEntry)
        defaults.set(targetBulletLines, forKey: Keys.targetBulletLines)
        defaults.set(skillCategoryCount, forKey: Keys.skillCategoryCount)
        defaults.set(maxSkillsPerCategory, forKey: Keys.maxSkillsPerCategory)
    }

    // MARK: - Prompt Fragments

    /// Bullet constraints shared by every highlights-producing prompt.
    /// Length is expressed as both a rendered-line target AND a concrete
    /// word ceiling — the line target alone reads as a soft suggestion the
    /// model routinely overruns, so we give it a hard number to self-check.
    var bulletConstraintText: String {
        let lineLabel = targetBulletLines == 1 ? "ONE line" : "\(targetBulletLines) lines"
        let wordCeiling = targetBulletLines * 16
        return """
        ## LENGTH — HARD CONSTRAINT (a strict limit, NOT a guideline)

        On the printed resume each bullet wraps at ~12-16 words per line (10-12pt type, ~5-6 inch column). The user has chosen a length of \(lineLabel) per bullet. Therefore:

        - **HARD CEILING: at most \(wordCeiling) words per bullet.** A bullet longer than \(wordCeiling) words has FAILED the requirement — shorten it before returning it.
        - Generate at most \(maxHighlightsPerEntry) bullets total.
        - Stay within length by CUTTING content, never by spilling onto extra lines. Lead with the single most important fact and stop there.
        - Delete em-dash asides (— like this —), colon-introduced lists (": a, b, c, d"), and trailing "and also…" clauses — these are exactly what overrun the line budget.
        - Dropping a detail to stay short is correct. A long, comprehensive bullet is wrong.
        """
    }
}
