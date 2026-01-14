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
}
