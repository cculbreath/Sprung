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
        guard let data = bundledManifest(slug: slug) else {
            Logger.warning("TemplateManifestLoader: No bundled manifest found for slug \(slug)")
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

    private static func bundledManifest(slug: String) -> Data? {
        let resourceName = "\(slug)-manifest"
        if let url = Bundle.main.url(
            forResource: resourceName,
            withExtension: "json",
            subdirectory: "Resources/Templates/\(slug)"
        ) {
            return try? Data(contentsOf: url)
        }
        return nil
    }
}
