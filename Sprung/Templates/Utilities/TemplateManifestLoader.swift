import Foundation

enum TemplateManifestLoader {
    /// Cache to avoid repeated JSON parsing of manifests
    private static var cache: [UUID: (manifest: TemplateManifest, dataHash: Int)] = [:]

    static func manifest(for template: Template) -> TemplateManifest? {
        let dataHash = template.manifestData?.hashValue ?? 0

        // Check cache
        if let cached = cache[template.id], cached.dataHash == dataHash {
            return cached.manifest
        }

        // Parse and cache
        let manifest = TemplateManifestDefaults.manifest(for: template)
        cache[template.id] = (manifest, dataHash)
        return manifest
    }
}
