import Foundation

enum TemplateManifestLoader {

    static func manifest(for template: Template) -> TemplateManifest? {
        if let data = template.manifestData,
           let manifest = decode(from: data, slug: template.slug) {
            return manifest
        }
        return manifest(forSlug: template.slug)
    }

    static func manifest(forSlug slug: String) -> TemplateManifest? {
        guard let data = documentsManifest(slug: slug) else {
            Logger.warning("TemplateManifestLoader: No manifest found for slug \(slug)")
            return nil
        }
        return decode(from: data, slug: slug)
    }

    static func decode(from data: Data, slug: String) -> TemplateManifest? {
        do {
            let manifest = try TemplateManifest.decode(from: data)
            if manifest.usesSynthesizedMetadata {
                Logger.info("TemplateManifestLoader: Synthesized field descriptors for legacy manifest '\(slug)'")
            }
            return manifest
        } catch {
            Logger.error("TemplateManifestLoader: Failed to decode manifest for slug \(slug): \(error)")
            return nil
        }
    }

    private static func documentsManifest(slug: String) -> Data? {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Sprung", isDirectory: true)
            .appendingPathComponent("Templates", isDirectory: true)
            .appendingPathComponent(slug, isDirectory: true)
            .appendingPathComponent("\(slug)-manifest.json")

        if let documentsURL,
           let data = try? Data(contentsOf: documentsURL) {
            return data
        }

        return nil
    }
}
