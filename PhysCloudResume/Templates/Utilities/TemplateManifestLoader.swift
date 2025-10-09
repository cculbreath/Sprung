import Foundation

enum TemplateManifestLoader {
    static func manifest(for template: Template) -> TemplateManifest? {
        if let data = template.manifestData, let manifest = decode(from: data) {
            return manifest
        }
        return manifest(forSlug: template.slug)
    }

    static func manifest(forSlug slug: String) -> TemplateManifest? {
        guard let data = bundledManifest(slug: slug) else { return nil }
        return decode(from: data)
    }

    private static func decode(from data: Data) -> TemplateManifest? {
        let decoder = JSONDecoder()
        return try? decoder.decode(TemplateManifest.self, from: data)
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
