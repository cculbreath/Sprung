import Foundation

enum TemplateManifestLoader {

    static func manifest(for template: Template) -> TemplateManifest? {
        guard let data = template.manifestData else {
            Logger.warning("TemplateManifestLoader: No manifest data stored for slug \(template.slug)")
            return nil
        }
        return decode(from: data, slug: template.slug)
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
}
