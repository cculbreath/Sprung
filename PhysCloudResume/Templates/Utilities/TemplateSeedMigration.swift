import Foundation
import SwiftData

enum TemplateSeedMigration {
    private static let migrationFlagKey = "TemplateSeedMigration.v1.completed"
    private static let backupDirectoryName = "MigrationBackups/TemplateSeeds"

    @MainActor
    static func runIfNeeded(
        context: ModelContext,
        templateStore: TemplateStore,
        templateSeedStore: TemplateSeedStore
    ) {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: migrationFlagKey) {
            return
        }

        let descriptor = FetchDescriptor<ResModel>()
        guard let resModels = try? context.fetch(descriptor), !resModels.isEmpty else {
            defaults.set(true, forKey: migrationFlagKey)
            return
        }

        var migratedCount = 0
        for resModel in resModels {
            let slug = resModel.style.lowercased()
            guard !slug.isEmpty else { continue }

            if templateSeedStore.seed(forSlug: slug) != nil {
                Logger.debug("TemplateSeedMigration: Seed already exists for slug \(slug); skipping migration entry")
                continue
            }

            do {
                try backup(resModel: resModel)
            } catch {
                Logger.warning("TemplateSeedMigration: Failed to back up res model \(resModel.id): \(error)")
            }

            let template = templateStore.template(slug: slug)
            templateSeedStore.upsertSeed(
                slug: slug,
                jsonString: resModel.json,
                attachTo: template
            )
            migratedCount += 1
            Logger.info("TemplateSeedMigration: Seed created for slug \(slug) from ResModel '\(resModel.name)'")
        }

        defaults.set(true, forKey: migrationFlagKey)
        Logger.info("TemplateSeedMigration: Migration completed. Seeds created: \(migratedCount)")
    }

    private static func backup(resModel: ResModel) throws {
        let fm = FileManager.default
        let documentsURL = fm.homeDirectoryForCurrentUser.appendingPathComponent("Documents/PhysCloudResume")
        let backupDirectory = documentsURL.appendingPathComponent(backupDirectoryName, isDirectory: true)

        if !fm.fileExists(atPath: backupDirectory.path) {
            try fm.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        }

        let sanitizedName = resModel.name
            .replacingOccurrences(of: "[^A-Za-z0-9_-]", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let filename = "\(sanitizedName.isEmpty ? "resmodel" : sanitizedName)_\(resModel.id.uuidString).json"
        let fileURL = backupDirectory.appendingPathComponent(filename)

        try resModel.json.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}
