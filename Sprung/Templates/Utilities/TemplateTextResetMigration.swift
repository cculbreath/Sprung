import Foundation

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

        var didReset = false
        for template in templates {
            if template.textContent != nil {
                template.textContent = nil
                didReset = true
            }
        }

        if didReset {
            templateStore.saveContext()
        }

        defaults.set(true, forKey: migrationFlagKey)
    }
}
