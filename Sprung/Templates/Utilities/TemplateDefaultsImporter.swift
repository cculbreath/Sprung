import Foundation

struct TemplateDefaultsCatalog: Decodable {
    struct Entry: Decodable {
        struct Paths: Decodable {
            let html: String
            let text: String
            let manifest: String
            let seed: String
        }

        let slug: String
        let name: String
        let isDefault: Bool
        let paths: Paths
    }

    let version: Int
    let generatedAt: String?
    let templates: [Entry]
}

enum TemplateDefaultsImporterError: Error {
    case catalogNotFound
    case unableToLoadFile(URL)
    case manifestEncodingFailed(String)
}

@MainActor
struct TemplateDefaultsImporter {
    private let templateStore: TemplateStore
    private let templateSeedStore: TemplateSeedStore
    private let bundle: Bundle

    init(
        templateStore: TemplateStore,
        templateSeedStore: TemplateSeedStore,
        bundle: Bundle = .main
    ) {
        self.templateStore = templateStore
        self.templateSeedStore = templateSeedStore
        self.bundle = bundle
    }

    func installDefaultsIfNeeded() {
        guard templateStore.templates().isEmpty else {
            Logger.debug("TemplateDefaultsImporter: skipping install; templates already exist.")
            return
        }

        do {
            try installDefaults()
            Logger.info("✅ Template defaults installed from bundled resources.", category: .migration)
        } catch {
            Logger.error("❌ TemplateDefaultsImporter failed: \(error)", category: .migration)
        }
    }

    private func installDefaults() throws {
        let catalogURL = try locateCatalog()
        let catalogData = try Data(contentsOf: catalogURL)
        let catalog = try JSONDecoder().decode(TemplateDefaultsCatalog.self, from: catalogData)
        let baseDirectory = catalogURL.deletingLastPathComponent()

        for entry in catalog.templates {
            let html = try readText(relativePath: entry.paths.html, baseDirectory: baseDirectory)
            let text = try readText(relativePath: entry.paths.text, baseDirectory: baseDirectory)
            let manifestString = try readText(relativePath: entry.paths.manifest, baseDirectory: baseDirectory)
            let seedString = try readText(relativePath: entry.paths.seed, baseDirectory: baseDirectory)

            guard let manifestData = manifestString.data(using: .utf8) else {
                throw TemplateDefaultsImporterError.manifestEncodingFailed(entry.slug)
            }

            let template = templateStore.upsertTemplate(
                slug: entry.slug,
                name: entry.name,
                htmlContent: html,
                textContent: text,
                isCustom: false,
                markAsDefault: entry.isDefault
            )

            try templateStore.updateManifest(slug: entry.slug, manifestData: manifestData)
            templateSeedStore.upsertSeed(
                slug: entry.slug,
                jsonString: seedString,
                attachTo: template
            )
        }
    }

    private func locateCatalog() throws -> URL {
        if let url = bundle.url(forResource: "catalog", withExtension: "json", subdirectory: "TemplateDefaults") {
            return url
        }

        if let flattened = bundle.url(forResource: "catalog", withExtension: "json") {
            Logger.debug("🧭 TemplateDefaultsImporter: using flattened catalog resource fallback.", category: .migration)
            return flattened
        }

        throw TemplateDefaultsImporterError.catalogNotFound
    }

    private func readText(relativePath: String, baseDirectory: URL) throws -> String {
        let fileURL = baseDirectory.appendingPathComponent(relativePath)
        do {
            return try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            let lastComponent = URL(fileURLWithPath: relativePath).lastPathComponent
            let flattenedURL = baseDirectory.appendingPathComponent(lastComponent)

            if flattenedURL != fileURL, FileManager.default.fileExists(atPath: flattenedURL.path) {
                Logger.debug(
                    "📁 TemplateDefaultsImporter: falling back to flattened resource for \(relativePath).",
                    category: .migration
                )
                do {
                    return try String(contentsOf: flattenedURL, encoding: .utf8)
                } catch {
                    throw TemplateDefaultsImporterError.unableToLoadFile(flattenedURL)
                }
            }

            throw TemplateDefaultsImporterError.unableToLoadFile(fileURL)
        }
    }
}
