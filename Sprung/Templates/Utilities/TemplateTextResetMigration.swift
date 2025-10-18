import Foundation

/// Clears legacy inline text template content stored prior to the SwiftData
/// migration (introduced September 2024). Remove once all users migrate past
/// Q1 2026.
enum TemplateTextResetMigration {
    private static let migrationFlagKey = "TemplateTextResetMigration.v1.completed"

    @MainActor
    static func runIfNeeded(templateStore: TemplateStore) {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: migrationFlagKey) == false else { return }

        let templates = templateStore.templates()
        guard !templates.isEmpty else {
            defaults.set(true, forKey: migrationFlagKey)
            return
        }

        var resetCount = 0
        for template in templates {
            if template.textContent != nil {
                template.textContent = nil
                resetCount += 1
            }
        }

        if resetCount > 0 {
            templateStore.saveContext()
            Logger.info(
                "TemplateTextResetMigration: cleared legacy text content for \(resetCount) template(s)",
                category: .migration
            )
        } else {
            Logger.info(
                "TemplateTextResetMigration: no legacy text content detected",
                category: .migration
            )
        }

        defaults.set(true, forKey: migrationFlagKey)
    }
}
