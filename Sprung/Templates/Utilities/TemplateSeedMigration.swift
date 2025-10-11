import Foundation
import SwiftData

enum TemplateSeedMigration {
    private static let migrationFlagKey = "TemplateSeedMigration.v1.completed"

    @MainActor
    static func runIfNeeded(
        context _: ModelContext,
        templateStore _: TemplateStore,
        templateSeedStore _: TemplateSeedStore
    ) {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: migrationFlagKey) {
            return
        }

        defaults.set(true, forKey: migrationFlagKey)
        Logger.info("TemplateSeedMigration: Legacy ResModel migration no longer required; flag set for future runs.")
    }
}
