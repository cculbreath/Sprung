import Foundation
import SwiftData

enum TemplateImporter {
    private static let resetFlagKey = "TemplateDataResetMigration.v1.completed"

    @MainActor
    static func resetTemplatesIfNeeded(context: ModelContext) throws {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: resetFlagKey) == false else { return }

        let templates = try context.fetch(FetchDescriptor<Template>())
        for template in templates {
            context.delete(template)
        }

        let assets = try context.fetch(FetchDescriptor<TemplateAsset>())
        for asset in assets {
            context.delete(asset)
        }

        let seeds = try context.fetch(FetchDescriptor<TemplateSeed>())
        for seed in seeds {
            context.delete(seed)
        }

        try context.save()
        defaults.set(true, forKey: resetFlagKey)
        Logger.info("TemplateImporter: Cleared legacy template data during migration.")
    }
}
