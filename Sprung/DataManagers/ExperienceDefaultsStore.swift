import Foundation
import Observation
import SwiftData
@MainActor
@Observable
final class ExperienceDefaultsStore: SwiftDataStore {
    let modelContext: ModelContext
    private var cachedDefaults: ExperienceDefaults?
    init(context: ModelContext) {
        self.modelContext = context
    }
    func currentDefaults() -> ExperienceDefaults {
        if let cachedDefaults {
            return cachedDefaults
        }
        if let existing = try? modelContext.fetch(FetchDescriptor<ExperienceDefaults>()).first {
            cachedDefaults = existing
            return existing
        }
        let defaults = ExperienceDefaults()
        modelContext.insert(defaults)
        saveContext()
        cachedDefaults = defaults
        return defaults
    }
    func save(_ defaults: ExperienceDefaults) {
        cachedDefaults = defaults
        saveContext()
    }
    func loadDraft() -> ExperienceDefaultsDraft {
        let defaults = currentDefaults()
        return ExperienceDefaultsDraft(model: defaults)
    }
    func save(draft: ExperienceDefaultsDraft) {
        let defaults = currentDefaults()
        draft.apply(to: defaults)
        cachedDefaults = defaults
        saveContext()
    }
    func clearCache() {
        cachedDefaults = nil
    }

    /// Check if seed generation has been completed or manual edits saved
    var isSeedCreated: Bool {
        currentDefaults().seedCreated
    }

    /// Mark that seed generation or manual editing is complete
    func markSeedCreated() {
        let defaults = currentDefaults()
        defaults.seedCreated = true
        cachedDefaults = defaults
        saveContext()
    }

    /// Clear SGM-generated content while preserving timeline facts.
    /// Clears: summaries, descriptions, highlights/bullets, categorized skills.
    /// Preserves: names, dates, locations, positions, institutions, etc.
    func clearGeneratedContent() {
        let defaults = currentDefaults()

        // Clear work summaries and highlights (keep name, position, location, dates, url)
        for i in defaults.work.indices {
            defaults.work[i].summary = ""
            defaults.work[i].highlights = []
        }

        // Clear volunteer summaries and highlights (keep org, position, dates, url)
        for i in defaults.volunteer.indices {
            defaults.volunteer[i].summary = ""
            defaults.volunteer[i].highlights = []
        }

        // Clear project descriptions, highlights, keywords (keep name, dates, url, org, type, roles)
        for i in defaults.projects.indices {
            defaults.projects[i].description = ""
            defaults.projects[i].highlights = []
            defaults.projects[i].keywords = []
        }

        // Clear award summaries (keep title, date, awarder)
        for i in defaults.awards.indices {
            defaults.awards[i].summary = ""
        }

        // Clear publication summaries (keep name, publisher, releaseDate, url)
        for i in defaults.publications.indices {
            defaults.publications[i].summary = ""
        }

        // Clear categorized skills entirely (SGM generates these groupings)
        defaults.skills = []

        // Reset the seed generation flag
        defaults.seedCreated = false

        cachedDefaults = defaults
        saveContext()
        Logger.info("Cleared SGM-generated content from ExperienceDefaults", category: .data)
    }
}
